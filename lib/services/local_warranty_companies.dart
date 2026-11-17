import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

/// Company identities and pending edits live in SQLite, including before sync.
class LocalWarrantyCompanies {
  LocalWarrantyCompanies({BriskersLocalDatabase? database,
    BriskersApi api = const BriskersApi(), bool Function()? canSync})
      : _db = database ?? localDatabase, _api = api,
        _canSync = canSync ?? (() =>
          !BriskersConnectionModeController.instance.forceOffline);

  final BriskersLocalDatabase _db;
  final BriskersApi _api;
  final bool Function() _canSync;
  static final _flushes = Expando<Map<String, Future<void>>>();

  Future<void> _prepare(String business) async {
    await _db.customStatement('CREATE TABLE IF NOT EXISTS local_warranty_companies ('
      'business_id TEXT NOT NULL,id TEXT NOT NULL,remote_id TEXT,'
      'payload_json TEXT NOT NULL,revision INTEGER NOT NULL DEFAULT 1,'
      'pending INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(business_id,id))');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('briskers_warranty_companies_$business');
    if (raw == null) return;
    dynamic decoded;
    try { decoded = jsonDecode(raw); } catch (_) { return; }
    if (decoded is! List) return;
    for (final value in decoded.whereType<Map>()) {
      final company = Map<String, dynamic>.from(value);
      final id = company['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      await _db.customStatement('INSERT OR IGNORE INTO local_warranty_companies '
        '(business_id,id,remote_id,payload_json) SELECT ?,?,?,? WHERE NOT EXISTS '
        '(SELECT 1 FROM local_warranty_companies WHERE business_id=? AND remote_id=?)',
        [business,id,id,jsonEncode(company),business,id]);
    }
  }

  Future<List<Map<String, dynamic>>> cached(String business,
      {bool includeInactive = false}) async {
    await _prepare(business);
    final rows = await _db.customSelect('SELECT * FROM local_warranty_companies '
      'WHERE business_id=?', variables: [Variable(business)]).get();
    final values = rows.map((row) => <String, dynamic>{
      ...Map<String, dynamic>.from(jsonDecode(row.read<String>('payload_json')) as Map),
      'id': row.read<String>('id'),
      '_server_id': row.readNullable<String>('remote_id'),
      '_revision': row.read<int>('revision'),
      'pending_sync': row.read<int>('pending') != 0,
    }).where((company) => includeInactive || company['active'] != false).toList();
    values.sort((a,b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
    return values;
  }

  Future<String> save(String business, {String? id, required String name,
    String? claimsPhone, String? submissionEmail, String? portalUrl,
    String? notes, bool active = true}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw StateError('Enter a company name.');
    final companyName = trimmed[0].toUpperCase() + trimmed.substring(1);
    await _prepare(business);
    return _db.transaction(() async {
      final companies = await cached(business, includeInactive: true);
      final duplicate = companies.where((company) =>
        '${company['name']}'.trim().toLowerCase() == companyName.toLowerCase() &&
        company['id'] != id);
      if (duplicate.isNotEmpty) {
        throw StateError('This company is already saved. Select it to edit its details.');
      }
      final existing = companies.where((company) => company['id'] == id).firstOrNull;
      if (id != null && existing == null) throw StateError('Reopen the company before editing.');
      final localId = id ?? 'local-warranty-${DateTime.now().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(1 << 32).toRadixString(16)}';
      final payload = {'name': companyName, 'claims_phone': claimsPhone?.trim(),
        'submission_email': submissionEmail?.trim(), 'portal_url': portalUrl?.trim(),
        'notes': notes?.trim(), 'active': active};
      await _db.customStatement('INSERT INTO local_warranty_companies '
        '(business_id,id,payload_json,pending) VALUES (?,?,?,1) '
        'ON CONFLICT(business_id,id) DO UPDATE SET payload_json=excluded.payload_json,'
        'pending=1,revision=revision+1', [business,localId,jsonEncode(payload)]);
      return localId;
    });
  }

  Future<List<Map<String, dynamic>>> available(String business,
      {bool includeInactive = false}) async {
    if (_canSync()) {
      try { await flush(business); } catch (_) { /* Retain saved companies. */ }
    }
    return cached(business, includeInactive: includeInactive);
  }

  Future<void> flush(String business) {
    if (!_canSync()) return Future<void>.value();
    final active = _flushes[_db] ??= {};
    return active[business] ??= _flush(business).whenComplete(() => active.remove(business));
  }

  Future<void> _flush(String business) async {
    await _prepare(business);
    if (!_canSync()) return;
    final remote = await _api.warrantyCompanies(business, includeInactive: true);
    final pending = await _db.customSelect('SELECT * FROM local_warranty_companies '
      'WHERE business_id=? AND pending=1', variables: [Variable(business)]).get();
    for (final row in pending) {
      if (!_canSync()) return;
      final localId = row.read<String>('id');
      final payload = Map<String, dynamic>.from(jsonDecode(row.read<String>('payload_json')) as Map);
      var serverId = row.readNullable<String>('remote_id');
      if (serverId == null) {
        final matches = remote.where((company) =>
          '${company['name']}'.trim().toLowerCase() == '${payload['name']}'.trim().toLowerCase()).toList();
        if (matches.length > 1) throw StateError('Multiple matching warranty companies require review.');
        serverId = matches.isEmpty ? null : matches.single['id']?.toString();
        serverId ??= await _api.createWarrantyCompany(business,
          name: payload['name'].toString(), claimsPhone: payload['claims_phone'] as String?,
          submissionEmail: payload['submission_email'] as String?);
        // Save the acknowledged identity before sending optional field updates.
        await _db.customStatement('UPDATE local_warranty_companies SET remote_id=? '
          'WHERE business_id=? AND id=?', [serverId,business,localId]);
        remote.add({...payload,'id':serverId});
      }
      if (!_canSync()) return;
      await _api.updateWarrantyCompany(business, serverId,
        name: payload['name'].toString(), claimsPhone: payload['claims_phone'] as String?,
        submissionEmail: payload['submission_email'] as String?,
        portalUrl: payload['portal_url'] as String?, notes: payload['notes'] as String?,
        active: payload['active'] != false);
      await _db.customStatement('UPDATE local_warranty_companies SET pending=0 '
        'WHERE business_id=? AND id=? AND revision=?',
        [business,localId,row.read<int>('revision')]);
      final index = remote.indexWhere((company) => company['id'] == serverId);
      if (index >= 0) remote[index] = {...payload,'id':serverId};
    }
    await _db.transaction(() async {
      for (final company in remote) {
        final id = company['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final found = await _db.customSelect('SELECT id,pending FROM local_warranty_companies '
          'WHERE business_id=? AND (id=? OR remote_id=?)',
          variables: [Variable(business),Variable(id),Variable(id)]).getSingleOrNull();
        if (found == null) {
          await _db.customStatement('INSERT INTO local_warranty_companies '
            '(business_id,id,remote_id,payload_json) VALUES (?,?,?,?)',
            [business,id,id,jsonEncode(company)]);
        } else if (found.read<int>('pending') == 0) {
          await _db.customStatement('UPDATE local_warranty_companies SET payload_json=? '
            'WHERE business_id=? AND id=? AND pending=0',
            [jsonEncode(company),business,found.read<String>('id')]);
        }
      }
    });
  }

  Future<String?> serverId(String business, String? id) async {
    if (id == null || id.isEmpty) return null;
    if (!id.startsWith('local-warranty-')) return id;
    await flush(business);
    final company = (await cached(business, includeInactive: true))
      .where((company) => company['id'] == id).firstOrNull;
    final remote = company?['_server_id']?.toString();
    if (remote == null || remote.isEmpty) throw StateError('Warranty company is waiting to synchronize.');
    return remote;
  }
}
