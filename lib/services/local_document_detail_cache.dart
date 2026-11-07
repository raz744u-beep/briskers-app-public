import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import 'recovery_commit_store.dart';
import 'local_document_sql_store.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_job_retirement.dart';
import 'test_job_cleanup_policy.dart';
import 'local_invoice_task_store.dart';

class LocalDocumentDetailCache {
  static bool sqliteWritesEnabled=false;
  static String key(String business,String document)=>'briskers_document_detail_${business}_$document';
  static Future<void> ensureSchema(BriskersLocalDatabase db)=>LocalDocumentSqlStore.ensure(db);
  static Future<void> initialize(BriskersLocalDatabase db) async {
    await LocalDocumentSqlStore.ensure(db);
    sqliteWritesEnabled=true;
  }

  const LocalDocumentDetailCache({BriskersLocalDatabase? database})
    : _injectedDatabase = database;

  final BriskersLocalDatabase? _injectedDatabase;
  BriskersLocalDatabase get _database => _injectedDatabase ?? localDatabase;

  Future<bool> _blocked(
    String businessId,
    String documentId, [
    Map<String, dynamic>? detail,
  ]) async {
    if(await LocalDocumentSqlStore.deleted(_database,_key(businessId,documentId))) return true;
    final payload = detail ?? const <String, dynamic>{};
    final ids = <String>{
      documentId,
      if (payload['id'] != null) payload['id'].toString(),
      if (payload['_server_document_id'] != null)
        payload['_server_document_id'].toString(),
    };
    for (final id in ids) {
      if (await LocalJobRetirement.isDocumentBlocked(
        _database,
        businessId,
        id,
      )) {
        return true;
      }
    }
    final jobId = payload['job_id']?.toString() ?? '';
    // Invoice details can arrive before the index row. Estimates and other
    // accounting kinds remain accessible; an unknown kind fails closed.
    return (payload['kind'] == null || payload['kind'] == 'invoice') &&
        jobId.isNotEmpty &&
        await LocalJobRetirement.isJobBlocked(_database, businessId, jobId);
  }

  Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _projectRetiredConversion(
    String businessId,
    Map<String, dynamic> detail,
  ) async {
    final invoiceId = detail['converted_invoice_id']?.toString() ?? '';
    if (detail['kind'] != 'estimate' ||
        invoiceId.isEmpty ||
        !await LocalJobRetirement.isDocumentBlocked(
          _database,
          businessId,
          invoiceId,
        )) {
      return detail;
    }
    // This is a presentation projection. The saved estimate, accepted status,
    // invoice history and exact original conversion identity stay untouched.
    return {
      ...detail,
      'converted': false,
      'converted_invoice_id': null,
      'converted_invoice_number': null,
      'converted_invoice_date': null,
      '_retired_conversion': true,
    };
  }

  // Serialize every read/write/invalidation for an identity, including across
  // different service instances. A newer edit queued behind cleanup is saved
  // afterwards, rather than disappearing in a check/remove race.
  static final Map<String, Future<void>> _pending = {};

  String _key(String businessId, String documentId) =>
      'briskers_document_detail_${businessId}_$documentId';

  Future<T> _serialized<T>(String key, Future<T> Function() operation) async {
    final before = _pending[key];
    final done = Completer<void>();
    _pending[key] = done.future;
    if (before != null) await before;
    try {
      return await operation();
    } finally {
      done.complete();
      if (identical(_pending[key], done.future)) _pending.remove(key);
    }
  }

  Future<void> save(
    String businessId,
    String documentId,
    Map<String, dynamic> detail,
  ) {
    final key = _key(businessId, documentId);
    final encoded = jsonEncode(detail);
    // Always acquire SQLite before the preference queue. Callers may already
    // hold a SQLite transaction; reversing that order can deadlock a cache
    // writer against a transactional sync reader.
    return _database.transaction(
      () => _serialized(key, () async {
        if (await _blocked(businessId, documentId, detail)) return;
        if (await RecoveryCommitStore.isOriginal(_database,businessId,documentId)) return;
        if (await RecoveryCommitStore.snapshot(_database,businessId,documentId) != null) {
          await _database.customStatement(
            'UPDATE recovery_document_cache SET payload_json=? WHERE business_id=? AND document_id=?',
            [encoded,businessId,documentId]);
          await LocalInvoiceTaskStore(_database).save(businessId, documentId, detail);
          return;
        }
        final prefs = await SharedPreferences.getInstance();
        // A late response may omit a provisional alias's canonical identity.
        // The existing association remains authoritative while it is blocked.
        if (await _blocked(
          businessId,
          documentId,
          _decode(prefs.getString(key)),
        )) {
          return;
        }
        if(sqliteWritesEnabled) {
          await LocalDocumentSqlStore.write(_database,key,encoded);
        } else { await prefs.setString(key,encoded); }
        await LocalInvoiceTaskStore(_database).save(businessId, documentId, detail);
      }),
    );
  }

  Future<Map<String, dynamic>?> load(String businessId, String documentId) {
    final key = _key(businessId, documentId);
    return _database.transaction(
      () => _serialized(key, () async {
        if (await _blocked(businessId, documentId)) return null;
        if (await RecoveryCommitStore.isOriginal(_database,businessId,documentId)) return null;
        final durable=await RecoveryCommitStore.snapshot(_database,businessId,documentId);
        final prefs = await SharedPreferences.getInstance();
        final detail = durable == null ? _decode(sqliteWritesEnabled
            ? await LocalDocumentSqlStore.read(_database,key) : prefs.getString(key))
            : _decode(durable.readNullable<String>('payload_json'));
        if (detail == null) return null;
        if (await _blocked(businessId, documentId, detail)) return null;
        // Derive tasks in the same serialized snapshot read. No financial row
        // changes, and an older background read cannot revert a newer edit.
        if(detail['kind']=='invoice'){
          await LocalInvoiceTaskStore(_database).reconcileCached(businessId,documentId,detail);
        }
        return _projectRetiredConversion(businessId, detail);
      }),
    );
  }

  /// Read existing local snapshots for exact payment-ID reporting links.
  /// Missing snapshots remain unknown; this never deletes or changes data.
  Future<List<Map<String, dynamic>>> loadAll(String businessId) {
    return _database.transaction(() async {
      final prefs = await SharedPreferences.getInstance();
      final prefix = 'briskers_document_detail_${businessId}_';
      final result = <Map<String, dynamic>>[];
      await RecoveryCommitStore.ensure(_database);
      final durable=await _database.customSelect(
        'SELECT document_id FROM recovery_document_cache WHERE business_id=?',
        variables:[Variable<String>(businessId)]).get();
      await LocalDocumentSqlStore.ensure(_database);
      final sqlDetails=await _database.customSelect('SELECT cache_key FROM local_document_details').get();
      final ids={...sqlDetails.map((r)=>r.read<String>('cache_key')).where((k)=>k.startsWith(prefix)).map((k)=>k.substring(prefix.length)),
          ...prefs.getKeys().where((key)=>key.startsWith(prefix))
          .map((key)=>key.substring(prefix.length)),
          ...durable.map((r)=>r.read<String>('document_id'))};
      for (final id in ids) {
        final snapshot = await load(businessId, id);
        if (snapshot != null) result.add(snapshot);
      }
      return result;
    });
  }

  /// Conditional cleanup invalidation. Snapshot comparison and removal share
  /// the same per-document queue with all writes. Unknown/dirty state is kept.
  Future<bool> removeIfUnchanged(
    String businessId,
    String documentId,
    Map<String, dynamic>? expected,
  ) {
    final key = _key(businessId, documentId);
    return _database.transaction(
      () => _serialized(key, () async {
        if (await _blocked(businessId, documentId, expected)) return false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final durable=await RecoveryCommitStore.snapshot(_database,businessId,documentId);
        final raw = durable == null ? (sqliteWritesEnabled ? await LocalDocumentSqlStore.read(_database,key) : prefs.getString(key)) : durable.readNullable<String>('payload_json');
        if (raw == null) return true;
        if (await _blocked(businessId, documentId, _decode(raw))) return false;
        if (expected == null ||
            raw != jsonEncode(expected) ||
            TestJobCleanupPolicy.hasPendingSnapshot(expected)) {
          return false;
        }
        if (durable != null) {
          await _database.customStatement(
            'UPDATE recovery_document_cache SET payload_json=NULL WHERE business_id=? AND document_id=?',
            [businessId,documentId]);
          return true;
        }
        if(sqliteWritesEnabled) {
          await LocalDocumentSqlStore.write(_database,key,null);
          return true;
        }
        return prefs.remove(key);
      }),
    );
  }

  Future<void> remove(String businessId, String documentId) {
    final key = _key(businessId, documentId);
    return _database.transaction(
      () => _serialized(key, () async {
        if (await _blocked(businessId, documentId)) return;
        final prefs = await SharedPreferences.getInstance();
        if (await _blocked(
          businessId,
          documentId,
          _decode(prefs.getString(key)),
        )) {
          return;
        }
        if (await RecoveryCommitStore.snapshot(_database,businessId,documentId) != null) {
          await _database.customStatement(
            'UPDATE recovery_document_cache SET payload_json=NULL WHERE business_id=? AND document_id=?',
            [businessId,documentId]);
        }
        if(sqliteWritesEnabled) { await LocalDocumentSqlStore.write(_database,key,null); }
        else { await prefs.remove(key); }
      }),
    );
  }
}
