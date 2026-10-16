import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart';
import 'local_job_deletion_v3.dart';

/// An unavailable server is never evidence that an earlier upload failed.
class OfflineJobPurgeNeedsReconciliation implements Exception {
  const OfflineJobPurgeNeedsReconciliation(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Memory-only consent. Business content is never persisted in a purge intent.
class OfflineJobPurgePreview {
  OfflineJobPurgePreview._(this.businessId, this.jobId, this.actorId,
      this.visibilityGeneration, this.graphHash, Map<String, int> counts, List<Map<String, dynamic>> items)
      : counts = Map.unmodifiable(counts),
        items = List.unmodifiable(items.map((item) => Map<String, dynamic>.unmodifiable(item)));
  final String businessId;
  final String jobId;
  final String actorId;
  final int visibilityGeneration;
  final String graphHash;
  final Map<String, int> counts;
  final List<Map<String, dynamic>> items;
}

class _LocalGraph {
  final rows = <String, List<Map<String, dynamic>>>{};
  final entities = <String, Set<String>>{};
  final queue = <Map<String, dynamic>>[];
  final preferences = <String, String>{};
  final caches = <Map<String, dynamic>>[];
  final media = <String>{};
  Set<String> get ids => entities.values.expand((v) => v).toSet();
  void add(String kind, String id) {
    if (id.isNotEmpty) (entities[kind] ??= <String>{}).add(id);
  }
  List<Map<String, String>> get inventory => [
    for (final kind in entities.keys.toList()..sort())
      for (final id in entities[kind]!.toList()..sort())
        {'entity_kind': kind, 'entity_id': id},
  ];
  String get hash => sha256.convert(utf8.encode(jsonEncode(_canonical({
    'rows': rows, 'queue': queue, 'preferences': preferences, 'caches': caches,
    'inventory': inventory,
  })))).toString();
}

Object? _canonical(Object? value) {
  if (value is Map) {
    return {for (final key in value.keys.map((k) => k.toString()).toList()..sort())
      key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

/// Local cancellation is a separate protocol from a verified server deletion.
/// Only a closed graph with positive never-dispatched proof is eligible.
class OfflineJobPurge {
  static const protocol = 'owner-local-cancellation-1.0';
  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static const _tables = <String, (String, String)>{
    'local_jobs': ('job', 'id'),
    'local_documents': ('document', 'id'),
    'local_job_visits': ('job_visit', 'id'),
    'local_job_assignments': ('job_assignment', 'assignment_id'),
    'local_pre_inspections': ('pre_inspection', 'id'),
    'local_pre_inspection_photos': ('pre_inspection_photo', 'id'),
    'local_findings': ('finding', 'id'),
    'local_finding_photos': ('attachment', 'id'),
  };
  static const _types = <String>{
    'job_create', 'job_admin', 'work_summary', 'preinspection',
    'preinspection_photo', 'finding_create', 'finding_update', 'finding_photo',
    'document_draft_create', 'document_edit', 'invoice_payment_received',
    'financial_create', 'financial_update', 'financial_photo',
  };
  static Never _stop(String why) => throw OfflineJobPurgeNeedsReconciliation(
      '$why Reconnect to reconcile this Job before permanent deletion.');

  static Future<void> ensureSchema(BriskersLocalDatabase db) async {
    await db.transaction(() async {
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_offline_job_purge_entities (
        business_id TEXT NOT NULL,job_id TEXT NOT NULL,operation_id TEXT NOT NULL,
        entity_kind TEXT NOT NULL,entity_id TEXT NOT NULL,
        PRIMARY KEY(business_id,entity_kind,entity_id))''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_offline_job_purge_requests (
        business_id TEXT NOT NULL,job_id TEXT NOT NULL,operation_id TEXT NOT NULL,
        actor_id TEXT NOT NULL,graph_hash TEXT NOT NULL,cleanup_state TEXT NOT NULL,
        registration_state TEXT NOT NULL DEFAULT 'pending',
        PRIMARY KEY(business_id,operation_id))''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_offline_authored_ids (
        business_id TEXT NOT NULL,entity_id TEXT NOT NULL,
        PRIMARY KEY(business_id,entity_id))''');
      // Only rows created after installation gain generic never-dispatched
      // provenance. Never backfill unknown historical operations as safe.
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_offline_dispatch_proof (
        business_id TEXT NOT NULL,outbox_id INTEGER NOT NULL,dispatched INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(business_id,outbox_id))''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_offline_dispatch_ids (
        business_id TEXT NOT NULL,entity_id TEXT NOT NULL,
        PRIMARY KEY(business_id,entity_id))''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS offline_purge_queue_provenance
        AFTER INSERT ON sync_outbox BEGIN
        INSERT OR IGNORE INTO local_offline_dispatch_proof(business_id,outbox_id,dispatched)
        VALUES(NEW.business_id,NEW.id,CASE WHEN NEW.attempt_count<>0 OR NEW.last_attempt_at IS NOT NULL OR NEW.state<>'pending' THEN 1 ELSE 0 END); END''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS offline_purge_queue_attempt
        AFTER UPDATE ON sync_outbox
        WHEN NEW.attempt_count<>0 OR NEW.last_attempt_at IS NOT NULL OR NEW.state='inflight'
        BEGIN UPDATE local_offline_dispatch_proof SET dispatched=1
          WHERE business_id=NEW.business_id AND outbox_id=NEW.id; END''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS offline_purge_proof_no_replace
        BEFORE INSERT ON local_offline_dispatch_proof WHEN NEW.dispatched<>1 AND EXISTS(
          SELECT 1 FROM local_offline_dispatch_proof WHERE business_id=NEW.business_id
          AND outbox_id=NEW.outbox_id AND dispatched=1)
        BEGIN SELECT RAISE(ABORT,'Dispatch history cannot be replaced'); END''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS offline_purge_proof_monotonic
        BEFORE UPDATE ON local_offline_dispatch_proof WHEN (OLD.dispatched=1 AND NEW.dispatched<>1) OR NEW.business_id<>OLD.business_id OR NEW.outbox_id<>OLD.outbox_id
        BEGIN SELECT RAISE(ABORT,'Dispatch history cannot be reset'); END''');
      for (final table in ['local_offline_job_purge_entities', 'local_offline_dispatch_proof', 'local_offline_dispatch_ids', 'local_offline_authored_ids']) {
        await db.customStatement('CREATE TRIGGER IF NOT EXISTS ${table}_immutable_delete '
          "BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT,'Cancellation and dispatch identities are permanent'); END");
      }
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS offline_purge_ids_no_update
        BEFORE UPDATE ON local_offline_dispatch_ids
        BEGIN SELECT RAISE(ABORT,'Dispatch identities cannot be changed'); END''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS offline_purge_entities_no_replace
        BEFORE INSERT ON local_offline_job_purge_entities WHEN EXISTS(
          SELECT 1 FROM local_offline_job_purge_entities WHERE business_id=NEW.business_id
          AND entity_kind=NEW.entity_kind AND entity_id=NEW.entity_id)
        BEGIN SELECT RAISE(ABORT,'Cancelled identities cannot be replaced'); END''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS offline_purge_entities_immutable_update
        BEFORE UPDATE ON local_offline_job_purge_entities
        BEGIN SELECT RAISE(ABORT,'Cancelled identities cannot be reassigned'); END''');
    });
  }

  /// Invoke only in the initial creator transaction, immediately after a new
  /// random identity is generated. Never call from import/restore/retry paths.
  static Future<void> recordNewIntent(BriskersLocalDatabase db, String businessId,
      Iterable<String> ids) async {
    await ensureSchema(db);
    for (final id in ids.toSet()) {
      if (id.isEmpty) throw StateError('A new intent needs its original identity.');
      await db.customStatement('INSERT INTO local_offline_authored_ids VALUES (?,?)', [businessId, id]);
    }
  }

  static void _assertOwnedReferences(Object? value, String job, Set<String> ids) {
    if (value is Map) {
      for (final e in value.entries) {
        final key = e.key.toString();
        final v = e.value;
        if (v is String && v.isNotEmpty) {
          if ((key == 'job_id' || key.endsWith('_job_id')) && v != job) {
            _stop('A record has a relationship to another Job.');
          }
          if (const {'document_id','invoice_id','estimate_id','found_document_id',
              'resolved_document_id','converted_from_estimate_id','converted_invoice_id',
              'finding_id','local_finding_id','inspection_id','local_inspection_id',
              'local_photo_id','attachment_id','transaction_id','local_transaction_id',
              'visit_id','local_id'}.contains(key) && !ids.contains(v)) {
            _stop('A record has a relationship to another document.');
          }
        }
        _assertOwnedReferences(v, job, ids);
      }
    } else if (value is List) {
      for (final child in value) { _assertOwnedReferences(child, job, ids); }
    }
  }

  static Set<String> _references(Object? value) {
    final ids = <String>{};
    void visit(Object? v) {
      if (v is Map) {
        for (final entry in v.entries) {
          final key = entry.key.toString();
          if ((key == 'id' || key.endsWith('_id')) && entry.value is String &&
              (entry.value as String).isNotEmpty &&
              !const {'customer_id', 'vehicle_id', 'employee_id', 'created_by', 'business_id', 'actor_id'}.contains(key)) {
            ids.add(entry.value as String);
          }
          visit(entry.value);
        }
      } else if (v is List) {
        for (final child in v) { visit(child); }
      }
    }
    visit(value);
    return ids;
  }

  // Dispatch correlation excludes shared lookup identities (payment methods,
  // accounts, categories, customers, vehicles, employees and catalog items).
  // Reusing a payment method must not poison an unrelated future local Job.
  static Set<String> _dispatchReferences(Object? value) {
    const keys = {'job_id','provisional_job_id','found_job_id','repair_job_id',
      'resolved_job_id','document_id','invoice_id','estimate_id',
      'found_document_id','resolved_document_id','converted_from_estimate_id',
      'converted_invoice_id','operation_id','local_transaction_id','transaction_id',
      'attachment_id','photo_id','local_photo_id','local_inspection_id',
      'inspection_id','local_finding_id','finding_id','local_id','visit_id',
      'assignment_id','payment_id','server_payment_id','server_transaction_id'};
    final ids = <String>{};
    void visit(Object? child) {
      if (child is Map) {
        for (final entry in child.entries) {
          if (keys.contains(entry.key) && entry.value is String && (entry.value as String).isNotEmpty) ids.add(entry.value as String);
          visit(entry.value);
        }
      } else if (child is List) {
        for (final item in child) { visit(item); }
      }
    }
    visit(value);
    return ids;
  }

  /// Must run immediately before every guarded network request. Transactional
  /// proof makes races one-sided: cancellation wins and send throws, or send
  /// wins and cancellation must reconcile. Lost ACKs stay marked dispatched.
  static Future<void> recordDispatch(BriskersLocalDatabase db, String businessId,
      {int? outboxId}) async {
    await ensureSchema(db);
    await db.transaction(() async {
      if (outboxId == null) {
        // An uncorrelated write makes existing pending graphs ambiguous; it
        // cannot have dispatched identities which have not been created yet.
        final pending = await db.customSelect("SELECT id FROM local_jobs WHERE business_id=? AND sync_state='pending'",
            variables: [Variable<String>(businessId)]).get();
        for (final row in pending) {
          await db.customStatement('INSERT OR IGNORE INTO local_offline_dispatch_ids VALUES (?,?)', [businessId, row.read<String>('id')]);
        }
        return;
      }
      await LocalJobDeletionV3.assertReplayAllowed(db, businessId, outboxId: outboxId);
      final rows = await db.customSelect("SELECT * FROM sync_outbox WHERE business_id=? AND id=? AND state IN ('pending','inflight')",
          variables: [Variable<String>(businessId), Variable<int>(outboxId)]).get();
      if (rows.length != 1) _stop('This queued operation was canceled or changed.');
      final row = rows.single.data;
      final payload = _decode(row['payload_json']);
      if (payload is! Map) throw StateError('Malformed queued operation cannot be dispatched.');
      final ids = {row['entity_id'].toString(), ..._dispatchReferences(payload)};
      await db.customStatement('INSERT INTO local_offline_dispatch_proof VALUES (?,?,1) '
          'ON CONFLICT(business_id,outbox_id) DO UPDATE SET dispatched=1', [businessId, outboxId]);
      for (final id in ids) {
        await db.customStatement('INSERT OR IGNORE INTO local_offline_dispatch_ids VALUES (?,?)', [businessId, id]);
      }
    });
  }

  static Object? _decode(Object? raw) {
    try { return raw is String ? jsonDecode(raw) : null; } catch (_) { return null; }
  }
  static Future<List<Map<String, dynamic>>> _read(BriskersLocalDatabase db,
      String table, String business) async => (await db.customSelect(
      'SELECT * FROM $table WHERE business_id=?', variables: [Variable<String>(business)]).get())
      .map((row) => row.data).toList();
  static bool _mentions(Object? value, Set<String> ids) =>
      _references(value).any(ids.contains);
  static bool _hasServerEvidence(Object? value) {
    if (value is Map) {
      if (value['server_updated_at'] != null || value['_server_document_id'] != null ||
          value['server_payment_id'] != null || value['server_transaction_id'] != null ||
          value['storage_key'] != null || value['storage_bucket'] != null) { return true; }
      return value.values.any(_hasServerEvidence);
    }
    return value is List && value.any(_hasServerEvidence);
  }
  static void _paths(Object? value, Set<String> paths) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (const {'local_file_path', 'local_path'}.contains(entry.key) && entry.value is String && (entry.value as String).isNotEmpty) {
          paths.add(entry.value as String);
        }
        _paths(entry.value, paths);
      }
    } else if (value is List) {
      for (final child in value) { _paths(child, paths); }
    }
  }

  static Future<_LocalGraph> _discover(BriskersLocalDatabase db, String business,
      String job) async {
    final graph = _LocalGraph()..add('job', job);
    final all = <String, List<Map<String, dynamic>>>{};
    for (final table in _tables.keys) { all[table] = await _read(db, table, business); }
    final jobs = all['local_jobs']!.where((r) => r['id'] == job).toList();
    if (jobs.length != 1 || jobs.single['sync_state'] != 'pending' || _hasServerEvidence(jobs.single)) {
      _stop('The Job has no complete never-uploaded local origin.');
    }
    final queue = await _read(db, 'sync_outbox', business);
    final origins = queue.where((r) {
      final p = _decode(r['payload_json']);
      return (r['entity_type'] == 'job_create' && r['entity_id'] == job && p is Map && p['job_id'] == job) ||
          (r['entity_type'] == 'document_draft_create' && r['operation'] == 'create_quick_invoice' &&
           p is Map && p['provisional_job_id'] == job && job == 'local-job-${p['operation_id']}') ||
          (r['entity_type'] == 'document_draft_create' && r['operation'] == 'convert_estimate' &&
           p is Map && p['kind'] == 'convert_invoice' && p['provisional_job_id'] == job &&
           job == 'local-conversion-job-${p['operation_id']}');
    }).toList();
    if (origins.length != 1) _stop('The original Job creation operation cannot be proved.');
    final origin = origins.single;
    final authored = (await _read(db, 'local_offline_authored_ids', business))
        .map((r) => r['entity_id'].toString()).toSet();
    if (!authored.contains(job)) _stop('This older Job has no positive original local-creation provenance.');
    if (origin['entity_type'] == 'job_create' && !_uuid.hasMatch(job)) _stop('The original Job UUID is invalid.');
    graph.rows['local_jobs'] = jobs;
    for (final table in ['local_documents', 'local_job_visits', 'local_job_assignments', 'local_pre_inspections']) {
      graph.rows[table] = all[table]!.where((r) => r['job_id'] == job).toList();
    }
    String? conversionSource;
    if (origin['operation'] == 'convert_estimate') {
      final originData = _decode(origin['payload_json']) as Map;
      conversionSource = originData['estimate_id']?.toString();
      final sources = all['local_documents']!.where((r) => r['id'] == conversionSource &&
          r['kind'] == 'estimate' && (r['job_id'] == null || r['job_id'] == '')).toList();
      final sourceCreates = queue.where((r) {
        final p = _decode(r['payload_json']);
        return r['entity_type'] == 'document_draft_create' && r['operation'] == 'create_estimate' &&
            r['entity_id'] == conversionSource && p is Map &&
            (p['job_id'] == null || p['job_id'] == '') && p['operation_id'] is String &&
            _uuid.hasMatch(p['operation_id'] as String) && conversionSource == 'local-estimate-${p['operation_id']}';
      }).toList();
      if (sources.length != 1 || sourceCreates.length != 1 || !authored.contains(conversionSource)) {
        _stop('The conversion source is not an exclusive never-uploaded standalone estimate.');
      }
      graph.rows['local_documents']!.add(sources.single);
    }
    graph.rows['local_findings'] = all['local_findings']!.where((r) => r['found_job_id'] == job || r['repair_job_id'] == job).toList();
    for (final row in graph.rows['local_findings']!) {
      for (final key in ['found_job_id', 'repair_job_id']) {
        if (row[key] != null && row[key] != '' && row[key] != job) _stop('A finding is shared with another Job.');
      }
    }
    final inspections = graph.rows['local_pre_inspections']!.map((r) => r['id']).toSet();
    final findings = graph.rows['local_findings']!.map((r) => r['id']).toSet();
    graph.rows['local_pre_inspection_photos'] = all['local_pre_inspection_photos']!.where((r) => inspections.contains(r['inspection_id'])).toList();
    graph.rows['local_finding_photos'] = all['local_finding_photos']!.where((r) => findings.contains(r['finding_id'])).toList();
    for (final entry in graph.rows.entries) {
      final (defaultKind, key) = _tables[entry.key]!;
      for (final row in entry.value) {
        if (_hasServerEvidence(row) || (row.containsKey('sync_state') && row['sync_state'] != 'pending') ||
            (row.containsKey('upload_state') && row['upload_state'] != 'pending')) {
          _stop('A related record may already exist on the server.');
        }
        final kind = defaultKind == 'document' ? row['kind'].toString() : defaultKind;
        if (defaultKind == 'document' && !const {'invoice', 'estimate'}.contains(kind)) _stop('An unsupported document is linked.');
        if (!authored.contains(row[key])) _stop('A related record has no original local-creation provenance.');
        if (row['row_version'] != null && row['row_version'] != 1) _stop('A related record has server-version history.');
        graph.add(kind, row[key].toString());
        if (row['attachment_id'] is String) graph.add('attachment', row['attachment_id'] as String);
        _paths(row, graph.media);
      }
    }
    // Expand only explicit owned transaction creates; customer/vehicle sharing
    // is never an ownership edge. Unknown operation types block, never vanish.
    var changed = true;
    while (changed) {
      changed = false;
      for (final row in queue.where((r) => r['entity_type'] == 'financial_create')) {
        final p = _decode(row['payload_json']);
        if (p is Map && _mentions(p, graph.ids) && !graph.ids.contains(row['entity_id'])) {
          graph.add('transaction', row['entity_id'].toString()); changed = true;
        }
      }
    }
    for (final row in queue) {
      final p = _decode(row['payload_json']);
      if (p is! Map) _stop('A queue entry has unknown relationships.');
      if (!graph.ids.contains(row['entity_id']) && !_mentions(p, graph.ids)) continue;
      if (!_types.contains(row['entity_type'])) _stop('A related operation needs server reconciliation.');
      if (row['entity_type'] == 'financial_photo' && graph.ids.contains(p['transaction_id'])) {
        graph.add('attachment', row['entity_id'].toString());
      }
      if (!graph.ids.contains(row['entity_id'])) _stop('A related operation targets content outside this Job.');
      if (row['state'] != 'pending' || row['attempt_count'] != 0 || row['last_attempt_at'] != null || _hasServerEvidence(p)) {
        _stop('An upload was attempted or acknowledged.');
      }
      _assertOwnedReferences(p, job, graph.ids);
      for (final key in ['job_id', 'found_job_id', 'repair_job_id', 'provisional_job_id']) {
        if (p[key] != null && p[key] != '' && p[key] != job) _stop('A queued operation belongs to another Job.');
      }
      for (final key in ['document_id', 'invoice_id', 'estimate_id', 'converted_from_estimate_id']) {
        if (p[key] != null && p[key] != '' && !graph.ids.contains(p[key])) _stop('A queued document is shared outside this Job.');
      }
      final proof = await db.customSelect('SELECT dispatched FROM local_offline_dispatch_proof WHERE business_id=? AND outbox_id=?',
          variables: [Variable<String>(business), Variable<int>(row['id'] as int)]).get();
      if (proof.length != 1 || proof.single.read<int>('dispatched') != 0) {
        _stop('An older queued operation has no reliable dispatch history.');
      }
      if (row['entity_type'] == 'financial_photo') graph.add('attachment', row['entity_id'].toString());
      graph.queue.add(row);
      final op = p['operation_id'];
      if (op is String && !authored.contains(op)) _stop('An operation lacks original local intent provenance.');
      if (!authored.contains(row['entity_id'])) _stop('An operation target lacks original local provenance.');
      String? namespace;
      if (row['entity_type'] == 'invoice_payment_received') namespace = 'invoice_payment';
      if (const {'preinspection', 'preinspection_photo', 'finding_create', 'finding_update', 'finding_photo', 'financial_create', 'financial_photo'}.contains(row['entity_type'])) namespace = 'sync';
      if (row['entity_type'] == 'document_draft_create' && row['operation'] == 'create_quick_invoice') namespace = 'quick_invoice';
      if (row['entity_type'] == 'document_draft_create' && row['operation'] == 'create_estimate' && (p['job_id'] == null || p['job_id'] == '')) namespace = 'standalone_estimate';
      if (namespace != null) {
        if (op is! String || op.isEmpty || op.length > 160 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(op)) _stop('A replay operation identity is invalid.');
        graph.add('operation', '$namespace/$op');
      }
      _paths(p, graph.media);
    }
    final dispatched = await _read(db, 'local_offline_dispatch_ids', business);
    if (dispatched.any((r) => r['entity_id'] == '*' || graph.ids.contains(r['entity_id']) ||
        graph.queue.any((q) => _dispatchReferences(_decode(q['payload_json'])).contains(r['entity_id'])))) {
      _stop('A request may have reached the server, even if its acknowledgement was lost.');
    }
    // Every document/finding/photo requires a retained creation operation;
    // pending state or a temporary ID alone is not proof of local origin.
    bool hasCreate(String type, String id) => graph.queue.any((q) => q['entity_type'] == type && q['entity_id'] == id);
    for (final row in graph.rows['local_documents']!) {
      if (!hasCreate('document_draft_create', row['id'].toString())) _stop('A document has no original queued create.');
    }
    for (final row in graph.rows['local_pre_inspections']!) {
      if (!graph.queue.any((q) => q['entity_type'] == 'preinspection' &&
          (_decode(q['payload_json']) as Map)['local_inspection_id'] == row['id'])) {
        _stop('An inspection has no original queued save.');
      }
    }
    for (final row in graph.rows['local_job_assignments']!) {
      if (row['source'] != 'offline_admin' || !hasCreate('job_admin', job)) {
        _stop('An assignment has no original local change.');
      }
    }
    final originPayload = _decode(origin['payload_json']) as Map;
    for (final row in graph.rows['local_job_visits']!) {
      if (!(origin['operation'] == 'create_quick_invoice' &&
          row['id'] == 'local-visit-${originPayload['operation_id']}') &&
          !graph.queue.any((q) => q['entity_type'] == 'work_summary' &&
              (_decode(q['payload_json']) as Map)['visit_id'] == row['id'])) {
        _stop('A visit has no proved local creation.');
      }
    }
    for (final row in graph.rows['local_findings']!) {
      if (!hasCreate('finding_create', row['id'].toString())) _stop('A finding has no original queued create.');
    }
    for (final table in ['local_pre_inspection_photos', 'local_finding_photos']) {
      for (final row in graph.rows[table]!) {
        if (!hasCreate(table == 'local_finding_photos' ? 'finding_photo' : 'preinspection_photo', row['id'].toString())) _stop('A photo has no original queued upload.');
      }
    }
    // References outside the selected exact graph prohibit erasure.
    for (final entry in all.entries) {
      final key = _tables[entry.key]!.$2;
      final selected = (graph.rows[entry.key] ?? []).map((r) => r[key]).toSet();
      for (final row in entry.value.where((r) => !selected.contains(r[key]))) {
        if (_mentions(row, graph.ids)) _stop('A record is shared with another Job.');
      }
    }
    for (final row in await _read(db, 'local_appointments', business)) {
      if (row['job_id'] == job) _stop('An appointment relationship needs reconciliation.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final prefix = 'briskers_document_detail_${business}_';
    for (final key in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()..sort()) {
      final raw = prefs.getString(key);
      final value = _decode(raw);
      if (value is! Map) _stop('A document cache has unknown ownership.');
      final owned = graph.ids.contains(key.substring(prefix.length));
      if (!owned && !_mentions(value, graph.ids)) continue;
      if (!owned || _hasServerEvidence(value)) _stop('A cached document has shared or server-owned content.');
      final sourceCache = key.substring(prefix.length) == conversionSource;
      if ((!sourceCache && value['job_id'] != job) ||
          (sourceCache && value['job_id'] != null && value['job_id'] != '') ||
          value['id'] != key.substring(prefix.length)) { _stop('A cached document link changed.'); }
      if (sourceCache && value['converted_invoice_id'] != origin['entity_id']) _stop('The source estimate conversion relationship changed.');
      _assertOwnedReferences(value, job, graph.ids);
      graph.preferences[key] = raw!;
      _paths(value, graph.media);
    }
    if (conversionSource != null && !graph.preferences.containsKey('$prefix$conversionSource')) {
      _stop('The original estimate conversion snapshot is unavailable.');
    }
    for (final row in await _read(db, 'local_financial_cache', business)) {
      final value = _decode(row['payload_json']);
      final key = row['cache_key'].toString();
      final exactDetail = key.startsWith('transaction_detail_') && graph.ids.contains(key.substring('transaction_detail_'.length));
      if (value is! Map && value is! List) _stop('A financial cache has unknown ownership.');
      if (exactDetail && (value is! Map || !graph.ids.contains(value['id']))) _stop('A transaction cache identity is inconsistent.');
      if (!exactDetail && !_mentions(value, graph.ids)) continue;
      // Keep unrelated members byte-for-byte in meaning; only exact owned
      // identities may be removed from known aggregate financial projections.
      if (value is List && const {'transactions_snapshot','linked_expenses_complete_v1'}.contains(row['cache_key'])) {
        final keep = <Object?>[];
        for (final item in value) {
          if (!_mentions(item, graph.ids)) { keep.add(item); continue; }
          if (item is! Map || !graph.ids.contains(item['id']) || _hasServerEvidence(item)) {
            _stop('A financial aggregate has an unproved shared member.');
          }
          _assertOwnedReferences(item, job, graph.ids);
          _paths(item, graph.media);
        }
        graph.caches.add({...row, '_replacement_payload_json': jsonEncode(keep)});
      } else {
        if (value is! Map || !graph.ids.contains(value['id']) || _hasServerEvidence(value)) {
          _stop('A shared financial snapshot needs reconciliation.');
        }
        _assertOwnedReferences(value, job, graph.ids);
        graph.caches.add(row); _paths(value, graph.media);
      }
    }
    // Persisted ACK/recovery envelopes always beat a zero counter, including
    // work performed by an older app version before journal installation.
    for (final table in ['local_job_recovery_receipts', 'local_job_recovery_rows']) {
      final exists = await db.customSelect("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", variables: [Variable<String>(table)]).get();
      if (exists.isEmpty) continue;
      for (final row in await _read(db, table, business)) {
        for (final key in ['row_json','response_json']) {
          if (row.containsKey(key) && _decode(row[key]) == null) _stop('A recovery record has unknown ownership.');
        }
        if (_mentions(row, graph.ids) || graph.queue.any((q) => q['id'] == row['outbox_id']) ||
            row.values.whereType<String>().map(_decode).any((p) => _mentions(p, graph.ids))) {
          _stop('A preserved recovery or acknowledgement record needs reconciliation.');
        }
      }
    }
    final blocked = await LocalJobDeletionV3.blockedIds(db, business);
    if (graph.ids.any(blocked.contains)) _stop('The graph contains restricted or previously canceled work.');
    for (final row in graph.queue) {
      try {
        await LocalJobDeletionV3.assertReplayAllowed(db, business, outboxId: row['id'] as int);
      } catch (_) { _stop('A queued operation is quarantined or requires reconciliation.'); }
    }
    final dirtyCacheKeys = (await db.customSelect(
        'SELECT cache_key FROM local_job_deletion_v3_cache_scope WHERE business_id=? AND dirty=1',
        variables: [Variable<String>(business)]).get()).map((r) => r.read<String>('cache_key')).toSet();
    if (graph.preferences.keys.any(dirtyCacheKeys.contains) ||
        graph.caches.any((r) => dirtyCacheKeys.contains('financial:${r['cache_key']}'))) {
      _stop('A retained cache needs authorization reconciliation.');
    }
    if (graph.media.isNotEmpty) {
      void rejectShared(Object? value) {
        final paths = <String>{}; _paths(value, paths);
        if (paths.any(graph.media.contains)) _stop('A local media file is shared outside this Job.');
      }
      for (final table in ['local_pre_inspection_photos', 'local_finding_photos']) {
        final owned = (graph.rows[table] ?? []).map((r) => r['id']).toSet();
        for (final row in await db.customSelect('SELECT * FROM $table').get()) {
          if (row.data['business_id'] != business || !owned.contains(row.data['id'])) rejectShared(row.data);
        }
      }
      final ownedQueueIds = graph.queue.map((r) => r['id']).toSet();
      for (final row in await db.customSelect('SELECT * FROM sync_outbox').get()) {
        if (row.data['business_id'] != business || !ownedQueueIds.contains(row.data['id'])) rejectShared(_decode(row.data['payload_json']));
      }
      final ownedCacheKeys = graph.caches.map((r) => r['cache_key']).toSet();
      for (final row in await db.customSelect('SELECT * FROM local_financial_cache').get()) {
        if (row.data['business_id'] != business || !ownedCacheKeys.contains(row.data['cache_key'])) rejectShared(_decode(row.data['payload_json']));
      }
      for (final row in graph.caches.where((r) => r.containsKey('_replacement_payload_json'))) {
        rejectShared(_decode(row['_replacement_payload_json']));
      }
      for (final key in prefs.getKeys()) {
        if (!graph.preferences.containsKey(key)) {
          final value = prefs.get(key);
          if (value is String) rejectShared(_decode(value));
        }
      }
    }
    return graph;
  }

  static Object? _transactionField(_LocalGraph graph, String id, String field) {
    for (final row in graph.caches) {
      final value = _decode(row['payload_json']);
      final entries = value is List ? value : [value];
      for (final item in entries) {
        if (item is Map && item['id'] == id && item[field] != null) return item[field];
      }
    }
    return null;
  }

  static Future<OfflineJobPurgePreview> preview(BriskersLocalDatabase db, {
    required String businessId, required String jobId, required String actorId, required bool isOwner,
  }) async {
    if (!isOwner) throw StateError('Only the Owner can permanently delete a Job.');
    await ensureSchema(db);
    final generation = await LocalJobDeletionV3.captureVisibilityGeneration(db, businessId);
    _assertActor(actorId);
    return db.transaction(() async {
      final graph = await _discover(db, businessId, jobId);
      await LocalJobDeletionV3.assertVisibilityGeneration(db, businessId, generation);
      _assertActor(actorId);
      return OfflineJobPurgePreview._(businessId, jobId, actorId, generation, graph.hash,
        Map.unmodifiable({for (final e in graph.entities.entries) e.key: e.value.length,
          'queued_operation': graph.queue.length, 'local_media': graph.media.length,
          'payment': graph.queue.where((r) => r['entity_type'] == 'invoice_payment_received').length}),
        List.unmodifiable([for (final entry in graph.rows.entries)
          for (final row in entry.value) {'kind': entry.key, 'id': row[_tables[entry.key]!.$2],
            'document_kind': row['kind'], 'document_number': row['document_number'],
            'label': row['document_number'] ?? row['job_number'] ?? row['title'] ?? row['filename'] ?? row[_tables[entry.key]!.$2]},
          for (final row in graph.queue.where((q) => q['entity_type'] == 'invoice_payment_received'))
            {'kind': 'payment', 'id': (_decode(row['payload_json']) as Map)['operation_id'], 'label': 'Queued payment',
              'amount_cents': (_decode(row['payload_json']) as Map)['amount_cents'],
              'method_name': (_decode(row['payload_json']) as Map)['method_name']},
          for (final row in graph.queue.where((q) => q['entity_type'] == 'financial_create'))
            {'kind': 'transaction', 'id': row['entity_id'], 'label': 'Queued transaction',
              'amount': (_decode(row['payload_json']) as Map)['amount'],
              'direction': (_decode(row['payload_json']) as Map)['direction'],
              'account_id': (_decode(row['payload_json']) as Map)['account_id'],
              'account_name': _transactionField(graph, row['entity_id'].toString(), 'account'),
              'currency': _transactionField(graph, row['entity_id'].toString(), 'currency')}]));
    });
  }
  static void _assertActor(String actorId) {
    if (actorId.isEmpty || (LocalJobDeletionV3.currentActorIdProvider != null && LocalJobDeletionV3.currentActorIdProvider!() != actorId)) {
      throw StateError('The authenticated Owner changed.');
    }
  }

  static Future<LocalDeletionCleanupResult> confirm(BriskersLocalDatabase db,
      OfflineJobPurgePreview preview, {required String operationId, required String actorId, required bool isOwner,
      Future<Directory> Function()? mediaDirectoryProvider}) async {
    if (!isOwner) throw StateError('Only the Owner can permanently delete a Job.');
    if (!_uuid.hasMatch(operationId) || actorId != preview.actorId) throw StateError('Invalid cancellation identity.');
    _assertActor(actorId);
    await ensureSchema(db);
    await LocalJobDeletionV3.ensureSchema(db);
    await db.transaction(() async {
      await LocalJobDeletionV3.assertVisibilityGeneration(db, preview.businessId, preview.visibilityGeneration);
      _assertActor(actorId);
      final graph = await _discover(db, preview.businessId, preview.jobId);
      await LocalJobDeletionV3.assertVisibilityGeneration(db, preview.businessId, preview.visibilityGeneration);
      _assertActor(actorId);
      if (graph.hash != preview.graphHash) throw StateError('The Job changed. Review a fresh deletion preview.');
      final existing = await db.customSelect('SELECT 1 FROM local_offline_job_purge_requests WHERE business_id=? AND operation_id=?',
          variables: [Variable<String>(preview.businessId), Variable<String>(operationId)]).get();
      if (existing.isNotEmpty) throw StateError('Cancellation operation already exists. Resume its cleanup.');
      await db.customStatement('INSERT INTO local_offline_job_purge_requests '
          '(business_id,job_id,operation_id,actor_id,graph_hash,cleanup_state) VALUES (?,?,?,?,?,?)',
          [preview.businessId, preview.jobId, operationId, actorId, graph.hash, 'pending']);
      for (final e in graph.inventory) {
        await db.customStatement('INSERT INTO local_offline_job_purge_entities VALUES (?,?,?,?,?)',
          [preview.businessId, preview.jobId, operationId, e['entity_kind'], e['entity_id']]);
      }
      for (final path in graph.media) {
        await db.customStatement('INSERT OR IGNORE INTO local_job_deletion_v3_media VALUES (?,?,?)', [preview.businessId, operationId, path]);
      }
      for (final row in graph.queue) {
        await db.customStatement('DELETE FROM sync_outbox WHERE business_id=? AND id=?', [preview.businessId, row['id']]);
      }
      for (final entry in graph.rows.entries.toList().reversed) {
        final key = _tables[entry.key]!.$2;
        for (final row in entry.value) {
          await db.customStatement('DELETE FROM ${entry.key} WHERE business_id=? AND $key=?', [preview.businessId, row[key]]);
        }
      }
      for (final row in graph.caches) {
        if (row.containsKey('_replacement_payload_json')) {
          await db.customStatement('UPDATE local_financial_cache SET payload_json=? WHERE business_id=? AND cache_key=?', [row['_replacement_payload_json'], preview.businessId, row['cache_key']]);
        } else {
          await db.customStatement('DELETE FROM local_financial_cache WHERE business_id=? AND cache_key=?', [preview.businessId, row['cache_key']]);
        }
      }
      await LocalJobDeletionV3.assertVisibilityGeneration(db, preview.businessId, preview.visibilityGeneration);
      _assertActor(actorId);
      // A permanent fence is committed with cancellation. Preferences/media
      // are independently resumable and cannot revive queued uploads.
    });
    LocalJobDeletionV3.notifyLocalPurge(db, preview.businessId, preview.jobId);
    return resumeCleanup(db, preview.businessId, operationId,
        mediaDirectoryProvider: mediaDirectoryProvider);
  }

  /// Minimal persisted registration only: no names, numbers, amounts, payloads,
  /// media locations or fabricated server receipt. Caller sends this to the
  /// absent-only register_local_v3 RPC and verifies its result before ack.
  static Future<List<Map<String, dynamic>>> pendingRegistrations(
      BriskersLocalDatabase db, String businessId, String actorId) async {
    await ensureSchema(db);
    _assertActor(actorId);
    final result = <Map<String, dynamic>>[];
    final requests = await db.customSelect(
        "SELECT * FROM local_offline_job_purge_requests WHERE business_id=? AND actor_id=? AND registration_state='pending'",
        variables: [Variable<String>(businessId), Variable<String>(actorId)]).get();
    for (final request in requests) {
      final localJob = request.read<String>('job_id');
      final quick = localJob.startsWith('local-job-');
      final conversion = localJob.startsWith('local-conversion-job-');
      final canonicalJob = quick ? localJob.substring('local-job-'.length) :
          conversion ? localJob.substring('local-conversion-job-'.length) : localJob;
      if (!_uuid.hasMatch(canonicalJob)) throw StateError('Invalid cancellation root identity.');
      final entities = await db.customSelect(
          'SELECT entity_kind,entity_id FROM local_offline_job_purge_entities WHERE business_id=? AND operation_id=? ORDER BY entity_kind,entity_id',
          variables: [Variable<String>(businessId), Variable<String>(request.read<String>('operation_id'))]).get();
      final standaloneKeys = entities.where((r) => r.read<String>('entity_kind') == 'operation' &&
          r.read<String>('entity_id').startsWith('standalone_estimate/')).map((r) => r.read<String>('entity_id').substring('standalone_estimate/'.length)).toList();
      if (conversion && (standaloneKeys.length != 1 || !_uuid.hasMatch(standaloneKeys.single))) {
        throw StateError('Standalone conversion cancellation lacks its source replay identity.');
      }
      final wire = <Map<String, String>>[
        {'entity_kind': 'job', 'entity_id': canonicalJob},
        if (conversion) {'entity_kind': 'estimate', 'entity_id': standaloneKeys.single},
        for (final row in entities)
          if (row.read<String>('entity_kind') != 'job' &&
              (_uuid.hasMatch(row.read<String>('entity_id')) || row.read<String>('entity_kind') == 'operation'))
            {'entity_kind': row.read<String>('entity_kind'), 'entity_id': row.read<String>('entity_id')},
      ]..sort((a,b) => ('${a['entity_kind']}\u0000${a['entity_id']}').compareTo('${b['entity_kind']}\u0000${b['entity_id']}'));
      if (quick && !wire.any((e) => e['entity_kind'] == 'operation' && e['entity_id'] == 'quick_invoice/$canonicalJob')) {
        throw StateError('Quick Invoice cancellation lacks its replay identity.');
      }
      result.add({
        'business_id': businessId, 'job_id': canonicalJob,
        'local_job_id': localJob, 'operation_id': request.read<String>('operation_id'),
        'confirmation': {
          'schema_version': 1, 'protocol_version': protocol,
          'scope': 'unpublished-local-job', 'business_id': businessId,
          'job_id': canonicalJob, 'actor_id': actorId,
          'graph_hash': request.read<String>('graph_hash'),
          'root_origin': quick ? 'quick_invoice' : conversion ? 'standalone_estimate_conversion' : 'job_create', 'deleted_entities': wire,
        },
      });
    }
    return result;
  }

  /// Only a validated matching server registration receipt authorizes this
  /// acknowledgement. An ambiguous timeout leaves the same operation pending.
  static Future<void> acknowledgeRegistration(BriskersLocalDatabase db,
      String businessId, String operationId) async {
    await db.customStatement("UPDATE local_offline_job_purge_requests SET registration_state='registered' WHERE business_id=? AND operation_id=?", [businessId, operationId]);
  }

  static Future<LocalDeletionCleanupResult> resumeCleanup(BriskersLocalDatabase db,
      String businessId, String operationId, {Future<Directory> Function()? mediaDirectoryProvider}) async {
    try {
      final entities = await db.customSelect('SELECT entity_kind,entity_id FROM local_offline_job_purge_entities WHERE business_id=? AND operation_id=?',
          variables: [Variable<String>(businessId), Variable<String>(operationId)]).get();
      if (entities.isEmpty) throw StateError('No committed local cancellation exists.');
      final documents = entities.where((r) => const {'invoice','estimate'}.contains(r.read<String>('entity_kind')))
          .map((r) => r.read<String>('entity_id')).toSet();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      for (final id in documents) {
        if (!await prefs.remove('briskers_document_detail_${businessId}_$id')) {
          return const LocalDeletionCleanupResult(false, issueCode: 'preference_cleanup_pending');
        }
      }
      final complete = await LocalJobDeletionV3.cleanupProvenLocalMedia(db, businessId, operationId,
          mediaDirectoryProvider: mediaDirectoryProvider);
      if (!complete) return const LocalDeletionCleanupResult(false, issueCode: 'media_cleanup_pending');
      await db.customStatement("UPDATE local_offline_job_purge_requests SET cleanup_state='complete' WHERE business_id=? AND operation_id=?", [businessId, operationId]);
      return const LocalDeletionCleanupResult(true);
    } catch (_) {
      return const LocalDeletionCleanupResult(false, issueCode: 'local_cleanup_pending');
    }
  }
}
