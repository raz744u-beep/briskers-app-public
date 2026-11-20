import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:drift/drift.dart';
import '../core/repair_group.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_document_detail_cache.dart';
import 'repair_group_schema.dart';
import 'local_attachment_cache.dart';

class LocalRepairGroups {
  LocalRepairGroups({BriskersLocalDatabase? database, LocalDocumentDetailCache? cache})
    : db = database ?? localDatabase,
      cache = cache ?? LocalDocumentDetailCache(database: database);
  final BriskersLocalDatabase db;
  final LocalDocumentDetailCache cache;
  static String newId() => List.generate(24, (_) => Random.secure().nextInt(256)
    .toRadixString(16).padLeft(2, '0')).join();
  List<Variable<String>> _vars(String business, String estimate) =>
    [Variable(business), Variable(estimate)];

  Future<bool> enabled(String business, String estimate) async {
    await RepairGroupSchema.ensure(db);
    return (await db.customSelect('SELECT 1 FROM repair_group_documents_v1 WHERE business=? AND estimate=?',
      variables: _vars(business, estimate)).get()).isNotEmpty;
  }

  Future<Map<String, dynamic>> _editable(String business, String estimate) async {
    if (business.isEmpty || estimate.isEmpty) { throw ArgumentError('Missing document scope.'); }
    final detail = await cache.load(business, estimate);
    if (detail == null || detail['kind'] != 'estimate' || detail['converted'] == true ||
        (detail['business_id'] != null && detail['business_id'] != business)) {
      throw StateError('Select an editable saved estimate.');
    }
    return detail;
  }

  Future<List<RepairGroup>> groups(String business, String estimate,
      Map<String, dynamic> detail) async {
    await RepairGroupSchema.ensure(db);
    final rows = await db.customSelect('SELECT * FROM repair_groups_v1 WHERE business=? AND estimate=? ORDER BY position,id',
      variables: _vars(business, estimate)).get();
    final members = await db.customSelect('SELECT line,group_id FROM repair_group_members_v1 WHERE business=? AND estimate=?',
      variables: _vars(business, estimate)).get();
    final membership = {for (final row in members) row.read<String>('line'): row.read<String>('group_id')};
    final ids = rows.map((row) => row.read<String>('id')).toSet();
    final lines = (detail['lines'] as List? ?? const []).whereType<Map>()
      .map((line) => Map<String, dynamic>.from(line)).where((line) => !RepairGroup.isGeneralCharge(line)).toList();
    return [
      for (final row in rows) RepairGroup(id: row.read<String>('id'), name: row.read<String>('name'),
        description: row.read<String>('description'), position: row.read<int>('position'),
        evidence: (jsonDecode(row.read<String>('evidence_json')) as List).whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)).toList(),
        lines: lines.where((line) => membership[line['id']] == row.read<String>('id')).toList()),
      RepairGroup(id: RepairGroup.otherId, name: 'Other Items',
        lines: lines.where((line) => !ids.contains(membership[line['id']])).toList()),
    ];
  }

  /// Called at every saved estimate edit, including edits outside group UI.
  /// A price changed and later reverted cannot revive an earlier approval.
  Future<void> observe(String business, String estimate, Map<String, dynamic> detail) async {
    if (detail['kind'] != 'estimate' || !await enabled(business, estimate)) { return; }
    for (final group in await groups(business, estimate, detail)) {
      final hash = group.fingerprint(detail);
      await db.customStatement('''INSERT INTO repair_group_scope_v1 VALUES(?,?,?,?,1)
        ON CONFLICT(business,estimate,group_id) DO UPDATE SET
        fingerprint=excluded.fingerprint,generation=repair_group_scope_v1.generation+1
        WHERE repair_group_scope_v1.fingerprint<>excluded.fingerprint''',
        [business, estimate, group.id, hash]);
    }
  }

  Future<Map<String, dynamic>> snapshot(String business, String estimate,
      Map<String, dynamic> detail) async {
    await RepairGroupSchema.ensure(db);
    final scopes = await db.customSelect('SELECT * FROM repair_group_scope_v1 WHERE business=? AND estimate=? ORDER BY group_id',
      variables: _vars(business, estimate)).get();
    final current = {for (final row in scopes) row.read<String>('group_id'): row};
    return {for (final group in await groups(business, estimate, detail)) group.id: {
      'fingerprint': group.fingerprint(detail),
      'generation': (current[group.id]?.read<int>('generation') ?? 0) +
        (current[group.id]?.read<String>('fingerprint') == group.fingerprint(detail) ? 0 : 1),
    }};
  }

  Future<String> add(String business, String estimate, String name) => db.transaction(() async {
    final detail = await _editable(business, estimate);
    if (name.trim().isEmpty) { throw ArgumentError('Enter a repair group name.'); }
    await RepairGroupSchema.ensure(db);
    final id = newId();
    await db.customStatement('INSERT OR IGNORE INTO repair_group_documents_v1 VALUES(?,?)', [business, estimate]);
    await db.customStatement('''INSERT INTO repair_groups_v1
      SELECT ?,?,?,?, '',coalesce(max(position),0)+1,'[]' FROM repair_groups_v1 WHERE business=? AND estimate=?''',
      [business, estimate, id, name.trim(), business, estimate]);
    await observe(business, estimate, detail);
    return id;
  });

  Future<void> edit(String business, String estimate, String id, {required String name,
      required String description, List<Map<String, dynamic>> evidence = const []}) => db.transaction(() async {
    final detail = await _editable(business, estimate);
    if (id == RepairGroup.otherId || name.trim().isEmpty) { throw ArgumentError('Invalid group.'); }
    await RepairGroupSchema.ensure(db);
    await db.customStatement('UPDATE repair_groups_v1 SET name=?,description=?,evidence_json=? WHERE business=? AND estimate=? AND id=?',
      [name.trim(), description.trim(), jsonEncode(evidence), business, estimate, id]);
    await observe(business, estimate, detail);
  });

  Future<void> remove(String business, String estimate, String id) => db.transaction(() async {
    final detail = await _editable(business, estimate);
    await RepairGroupSchema.ensure(db);
    await db.customStatement('DELETE FROM repair_group_members_v1 WHERE business=? AND estimate=? AND group_id=?', [business, estimate, id]);
    await db.customStatement('DELETE FROM repair_groups_v1 WHERE business=? AND estimate=? AND id=?', [business, estimate, id]);
    await observe(business, estimate, detail);
  });

  Future<void> reorder(String business, String estimate, List<String> ids) => db.transaction(() async {
    final detail = await _editable(business, estimate);
    final current = (await groups(business, estimate, detail)).where((group) => !group.isOther).map((group) => group.id).toSet();
    if (ids.length != current.length || ids.toSet().length != ids.length || !current.containsAll(ids)) {
      throw ArgumentError('Group order must contain each saved group once.');
    }
    for (var i = 0; i < ids.length; i++) {
      await db.customStatement('UPDATE repair_groups_v1 SET position=? WHERE business=? AND estimate=? AND id=?', [i, business, estimate, ids[i]]);
    }
  });

  Future<void> move(String business, String estimate, String lineId, String groupId) => db.transaction(() async {
    final detail = await _editable(business, estimate);
    final all = await groups(business, estimate, detail);
    if (!all.any((group) => group.id == groupId) ||
        !all.any((group) => group.lines.any((line) => line['id'] == lineId))) {
      throw ArgumentError('Select an existing part or labor item and group.');
    }
    await db.customStatement('INSERT INTO repair_group_members_v1 VALUES(?,?,?,?) ON CONFLICT(business,estimate,line) DO UPDATE SET group_id=excluded.group_id',
      [business, estimate, lineId, groupId]);
    await observe(business, estimate, detail);
  });

  Future<List<Map<String, dynamic>>> history(String business, String estimate) async {
    await RepairGroupSchema.ensure(db);
    final rows = await db.customSelect('SELECT payload_json FROM repair_authorizations_v1 WHERE business=? AND estimate=? ORDER BY rowid',
      variables: _vars(business, estimate)).get();
    return rows.map((row) => Map<String, dynamic>.from(jsonDecode(row.read<String>('payload_json')) as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> availableEvidence(String business, Map<String, dynamic> detail) async {
    final vehicle = detail['vehicle_id']?.toString() ?? '';
    final job = detail['job_id']?.toString() ?? '';
    if (vehicle.isEmpty && job.isEmpty) { return []; }
    final findings = await db.customSelect('''SELECT * FROM local_findings
      WHERE business_id=? AND ((?<>'') AND vehicle_id=? OR (?<>'') AND found_job_id=?) ORDER BY created_at,id''',
      variables: [business, vehicle, vehicle, job, job].map(Variable<String>.new).toList()).get();
    final result = <Map<String, dynamic>>[];
    for (final finding in findings) {
      final photos = await db.customSelect('SELECT * FROM local_finding_photos WHERE business_id=? AND finding_id=? ORDER BY id',
        variables: [Variable(business), Variable(finding.read<String>('id'))]).get();
      result.add({'id': finding.read<String>('id'), 'body': finding.read<String>('body'),
        'photos': [for (final photo in photos) {
          'id': photo.read<String>('id'), 'local_file_path': photo.readNullable<String>('local_file_path'),
          'bucket': photo.readNullable<String>('storage_bucket'), 'key': photo.readNullable<String>('storage_key'),
        }],
      });
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> vehicleHistory(String business, String vehicle) async {
    if (vehicle.isEmpty) { return []; }
    await RepairGroupSchema.ensure(db);
    final rows = await db.customSelect('''SELECT payload_json FROM repair_authorizations_v1
      WHERE business=? AND json_extract(payload_json,'\$.vehicle_id')=? ORDER BY rowid DESC''',
      variables: [Variable(business), Variable(vehicle)]).get();
    return rows.map((row) => Map<String, dynamic>.from(jsonDecode(row.read<String>('payload_json')) as Map)).toList();
  }

  Future<Uint8List?> media(String business, String id) async {
    await RepairGroupSchema.ensure(db);
    final row = await db.customSelect('SELECT image_bytes FROM repair_authorization_media_v1 WHERE business=? AND media_id=?',
      variables: [Variable(business), Variable(id)]).getSingleOrNull();
    return row?.read<Uint8List>('image_bytes');
  }

  Future<Uint8List?> signature(String business, String id) async {
    await RepairGroupSchema.ensure(db);
    final row = await db.customSelect('SELECT image_bytes FROM repair_signatures_v1 WHERE business=? AND signature_id=?',
      variables: [Variable(business), Variable(id)]).getSingleOrNull();
    return row?.read<Uint8List>('image_bytes');
  }

  Future<Map<String, dynamic>> _preserveEvidence(String business, String eventId,
      RepairGroup group, Map<String, Uint8List> media) async {
    final evidence = <Map<String, dynamic>>[];
    for (final finding in group.evidence) {
      final photos = <Map<String, dynamic>>[];
      for (final raw in (finding['photos'] as List? ?? const []).whereType<Map>()) {
        final reference = raw['media_ref']?.toString() ?? '';
        Uint8List? bytes = reference.isEmpty ? null : await this.media(business, reference);
        File? file;
        final path = raw['local_file_path']?.toString() ?? '';
        if (bytes == null) {
          if (path.isNotEmpty && await File(path).exists()) file = File(path);
          file ??= await LocalAttachmentCache().existing(raw['bucket']?.toString() ?? '', raw['key']?.toString() ?? '');
          if (file == null || !await file.exists()) { throw StateError('Save the linked finding photographs locally before authorization.'); }
          bytes = await file.readAsBytes();
        }
        if (bytes.isEmpty) { throw StateError('A linked photograph is empty.'); }
        final hash = RepairGroup.hash(base64Encode(bytes));
        final id = '$eventId-$hash';
        media[id] = bytes;
        photos.add({...Map<String, dynamic>.from(raw), 'media_ref': id, 'content_hash': hash});
      }
      evidence.add({...finding, 'photos': photos});
    }
    return {'id': group.id, 'name': group.name, 'description': group.description,
      'lines': group.lines, 'evidence': evidence};
  }

  /// Selects existing priced lines; never edits the source estimate or charges
  /// an undecided group. Legacy documents retain their existing behavior.
  Future<Map<String, dynamic>> authorizedDocument(String business, String estimate,
      Map<String, dynamic> detail) async {
    if (!await enabled(business, estimate)) { return detail; }
    final states = await decisions(business, estimate, detail);
    final allGroups = await groups(business, estimate, detail);
    final approved = allGroups
      .where((group) => states[group.id] == RepairDecision.approved).toList();
    final ids = approved.expand((group) => group.lines).map((line) => line['id']).toSet();
    if (ids.isEmpty) { throw StateError('No currently approved billable repairs. Supplies will not be charged.'); }
    if ((detail['lines'] as List).whereType<Map>().any((line) => line['line_kind'] == 'discount') &&
        allGroups.any((group) => group.lines.isNotEmpty && states[group.id] != RepairDecision.approved)) {
      throw StateError('Partial repair selection needs the existing discount calculation to be reviewed. Conversion is blocked to preserve quoted pricing.');
    }
    final membership = {for (final group in approved)
      for (final line in group.lines) line['id']: group.id};
    final lines = (detail['lines'] as List).whereType<Map>()
      .map((line) => Map<String, dynamic>.from(line))
      .where((line) => ids.contains(line['id']) || RepairGroup.isGeneralCharge(line))
      .map((line) => <String, dynamic>{...line, 'repair_group_id': membership[line['id']],
        'repair_source_line_id': line['id']}).toList();
    // Aggregate saved pricing results, including the existing general charges.
    // Quantities, rates, discounts and prices are not independently recomputed.
    var netCents = 0;
    var taxCents = 0;
    for (final line in lines) {
      final net = num.tryParse('${line['net_amount']}');
      final tax = num.tryParse('${line['tax_amount']}');
      if (net == null || tax == null || !net.isFinite || !tax.isFinite) {
        throw StateError('Save complete item amounts before conversion.');
      }
      netCents += (net * 100).round();
      taxCents += (tax * 100).round();
    }
    return {...detail, 'lines': lines, 'net_amount': netCents / 100,
      'tax_amount': taxCents / 100, 'total_amount': (netCents + taxCents) / 100,
      'repair_group_invoice': [for (final group in approved) {
        'id': group.id, 'name': group.name, 'description': group.description,
        'source_line_ids': group.lines.map((line) => line['id']).toList(),
        'authorized_cents': group.quotedCents, 'evidence': group.evidence,
      }],
    };
  }

  Future<Map<String, RepairDecision>> decisions(String business, String estimate, Map<String, dynamic> detail) async {
    final scope = await snapshot(business, estimate, detail);
    final result = <String, RepairDecision>{};
    for (final event in await history(business, estimate)) {
      for (final raw in event['groups'] as List) {
        final item = raw as Map;
        final id = item['id'] as String;
        result[id] = jsonEncode(RepairGroup.canonical(item['scope'])) == jsonEncode(RepairGroup.canonical(scope[id]))
          ? RepairDecision.values.byName(item['decision'] as String) : RepairDecision.awaitingDecision;
      }
    }
    return result;
  }

  Future<void> authorize(String business, String estimate, {
    required String eventId, required Map<String, dynamic> expectedScope,
    required Map<String, RepairDecision> decisions, required RepairAuthorizationMethod method,
    required String actor, String notes = '', Uint8List? signature,
  }) => db.transaction(() async {
    await RepairGroupSchema.ensure(db);
    // A durable event is its own acknowledgment even if the document has
    // since been converted or edited, or the original photo was removed.
    final replay = await db.customSelect('SELECT payload_json FROM repair_authorizations_v1 WHERE business=? AND event_id=?',
      variables: [Variable(business), Variable(eventId)]).getSingleOrNull();
    if (replay != null) {
      final prior = jsonDecode(replay.read<String>('payload_json')) as Map;
      final priorGroups = (prior['groups'] as List).cast<Map>();
      final matches = prior['estimate_id'] == estimate && prior['method'] == method.name &&
        prior['actor'] == actor.trim() && prior['notes'] == notes.trim() &&
        prior['signature_hash'] == (signature == null ? null : RepairGroup.hash(base64Encode(signature))) &&
        priorGroups.length == decisions.length && priorGroups.every((group) =>
          decisions[group['id']]?.name == group['decision'] &&
          RepairGroup.hash(expectedScope[group['id']]) == RepairGroup.hash(group['scope']));
      if (!matches) { throw StateError('Conflicting authorization event replay.'); }
      return;
    }
    final detail = await _editable(business, estimate);
    final scope = await snapshot(business, estimate, detail);
    if (eventId.isEmpty || actor.trim().isEmpty || decisions.isEmpty ||
        decisions.values.contains(RepairDecision.awaitingDecision)) { throw ArgumentError('Complete the authorization.'); }
    final signed = method == RepairAuthorizationMethod.kioskSignature || method == RepairAuthorizationMethod.deviceSignature;
    if (signed && (signature == null || signature.length < 8 ||
        base64Encode(signature.sublist(0, 8)) != 'iVBORw0KGgo=')) { throw ArgumentError('A PNG customer signature is required.'); }
    if (!signed && notes.trim().isEmpty) { throw ArgumentError('Record authorization notes.'); }
    final all = await groups(business, estimate, detail);
    final selected = all.where((group) => decisions.containsKey(group.id)).toList();
    if (selected.length != decisions.length || selected.any((group) => group.lines.isEmpty)) { throw ArgumentError('Select nonempty repair groups.'); }
    for (final group in selected) {
      if (jsonEncode(RepairGroup.canonical(scope[group.id])) != jsonEncode(RepairGroup.canonical(expectedScope[group.id]))) {
        throw StateError('Repair scope changed. Review the current estimate before authorizing.');
      }
    }
    final mediaBytes = <String, Uint8List>{};
    final preserved = <String, Map<String, dynamic>>{};
    for (final group in selected) {
      preserved[group.id] = await _preserveEvidence(business, eventId, group, mediaBytes);
    }
    final payload = <String, dynamic>{
      'event_id': eventId, 'estimate_id': estimate, 'revision': RepairGroup.hash(scope),
      'vehicle_id': detail['vehicle_id'], 'customer_id': detail['customer_id'],
      'customer_name': detail['customer_name'], 'vehicle': detail['vehicle'],
      'method': method.name, 'actor': actor.trim(), 'notes': notes.trim(),
      'signature_ref': signed ? eventId : null,
      'signature_hash': signed ? RepairGroup.hash(base64Encode(signature!)) : null,
      'groups': [for (final group in selected) {
        ...preserved[group.id]!,
        'scope': scope[group.id], 'decision': decisions[group.id]!.name,
        'quoted_cents': group.quotedCents,
        'approved_cents': decisions[group.id] == RepairDecision.approved ? group.quotedCents : 0,
      }],
    };
    payload['timestamp'] = DateTime.now().toUtc().toIso8601String();
    for (final entry in mediaBytes.entries) {
      await db.customStatement('INSERT INTO repair_authorization_media_v1 VALUES(?,?,?) ON CONFLICT DO NOTHING',
        [business, entry.key, entry.value]);
    }
    if (signed) await db.customStatement('INSERT INTO repair_signatures_v1 VALUES(?,?,?)', [business, eventId, signature]);
    await db.customStatement('INSERT INTO repair_authorizations_v1 VALUES(?,?,?,?,?)',
      [business, estimate, eventId, payload['revision'], jsonEncode(payload)]);
  });
}
