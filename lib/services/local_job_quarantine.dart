import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_cleanup_safety.dart';

class LocalJobQuarantineException implements Exception {
  const LocalJobQuarantineException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Inaccessible recovery storage for a positive server revocation whose reason
/// cannot yet be classified. Active readers never need to read this archive.
/// Original payloads and file paths are immutable; no files are deleted and no
/// archived operation is ever restored or replayed automatically.
class LocalJobQuarantine {
  static final StreamController<({String businessId, Set<String> jobIds})> _events =
      StreamController<({String businessId, Set<String> jobIds})>.broadcast(sync: true);
  static Stream<({String businessId, Set<String> jobIds})> get events => _events.stream;

  static const _ownedTables = <String, String>{
    'local_jobs': 'id',
    'local_job_visits': 'id',
    'local_job_assignments': 'assignment_id',
    'local_pre_inspections': 'id',
    'local_pre_inspection_photos': 'id',
    'local_findings': 'id',
    'local_finding_photos': 'id',
  };

  static Future<bool> _installed(BriskersLocalDatabase db) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
      "('local_job_quarantines','local_job_quarantine_entities','local_job_recovery_rows','local_job_recovery_receipts')",
    ).get();
    if (rows.isEmpty) return false;
    final triggers = await db.customSelect(
      "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='trigger' AND name LIKE 'quarantine_%'",
    ).getSingle();
    final receiptColumns = await db.customSelect('PRAGMA table_info(local_job_recovery_receipts)').get();
    if (rows.length != 4 || triggers.read<int>('n') != 16 ||
        !receiptColumns.any((row) => row.read<String>('name') == 'request_generation')) {
      await db.transaction(() => _ensureSchema(db));
    }
    return true;
  }

  static Future<void> _ensureSchema(BriskersLocalDatabase db) async {
    await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_quarantines (
      business_id TEXT NOT NULL, job_id TEXT NOT NULL,
      generation INTEGER NOT NULL, state TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY(business_id,job_id)
    )''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_quarantine_entities (
      business_id TEXT NOT NULL, job_id TEXT NOT NULL,
      entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
      PRIMARY KEY(business_id,job_id,entity_type,entity_id)
    )''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_recovery_rows (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      business_id TEXT NOT NULL, job_id TEXT NOT NULL,
      generation INTEGER NOT NULL, table_name TEXT NOT NULL,
      original_key TEXT NOT NULL, row_json TEXT NOT NULL,
      captured_at INTEGER NOT NULL,
      UNIQUE(business_id,job_id,generation,table_name,original_key)
    )''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_recovery_receipts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      business_id TEXT NOT NULL, outbox_id INTEGER,
      response_json TEXT NOT NULL, request_generation INTEGER NOT NULL, captured_at INTEGER NOT NULL
    )''');
    final receiptColumns = await db.customSelect('PRAGMA table_info(local_job_recovery_receipts)').get();
    if (!receiptColumns.any((row) => row.read<String>('name') == 'request_generation')) {
      // An interrupted older install cannot make an unstamped receipt replayable.
      await db.customStatement('ALTER TABLE local_job_recovery_receipts ADD COLUMN request_generation INTEGER NOT NULL DEFAULT -1');
    }
    // Fixed active-table guards: stale acknowledgements cannot recreate cache
    // rows hidden by quarantine, including after process restart.
    for (final entry in _ownedTables.entries) {
      final table = entry.key;
      final primaryKey = entry.value;
      String reference;
      if (table == 'local_jobs') {
        reference = 'q.job_id=NEW.id';
      } else if (const ['local_job_visits', 'local_job_assignments', 'local_pre_inspections'].contains(table)) {
        reference = 'q.job_id=NEW.job_id';
      } else if (table == 'local_findings') {
        reference = '(q.job_id=NEW.found_job_id OR q.job_id=NEW.repair_job_id)';
      } else {
        final parent = table == 'local_pre_inspection_photos' ? 'inspection_id' : 'finding_id';
        reference = '''EXISTS(SELECT 1 FROM local_job_quarantine_entities e
          WHERE e.business_id=q.business_id AND e.job_id=q.job_id
            AND e.entity_id=NEW.$parent)''';
      }
      final blocked = '''EXISTS(SELECT 1 FROM local_job_quarantines q
        WHERE q.business_id=NEW.business_id AND q.state<>'authorized'
          AND ($reference OR EXISTS(SELECT 1 FROM local_job_quarantine_entities e
            WHERE e.business_id=q.business_id AND e.job_id=q.job_id
              AND e.entity_type='$table' AND e.entity_id=NEW.$primaryKey)))''';
      for (final action in const ['INSERT', 'UPDATE']) {
        await db.customStatement('''CREATE TRIGGER IF NOT EXISTS quarantine_${table}_${action.toLowerCase()}
          BEFORE $action ON $table WHEN $blocked
          BEGIN SELECT RAISE(ABORT,'Job access is quarantined; recovery preserved'); END''');
      }
    }
    // JSON1 is also used by application SQLite queries. Abort installation if
    // unavailable; never install a partial permissive replay guard.
    await db.customSelect("SELECT json_valid('{}') AS valid").getSingle();
    for (final action in const ['INSERT', 'UPDATE']) {
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS quarantine_outbox_${action.toLowerCase()}
        BEFORE $action ON sync_outbox
        WHEN EXISTS(SELECT 1 FROM local_job_quarantines q
          WHERE q.business_id=NEW.business_id AND q.state<>'authorized'
            AND (json_valid(NEW.payload_json)=0 OR EXISTS(
              SELECT 1 FROM local_job_quarantine_entities e
              WHERE e.business_id=q.business_id AND e.job_id=q.job_id
                AND (e.entity_id=NEW.entity_id OR EXISTS(
                  SELECT 1 FROM json_tree(CASE WHEN json_valid(NEW.payload_json)
                    THEN NEW.payload_json ELSE '{}' END) j
                  WHERE j.type='text' AND j.value=e.entity_id)))))
        BEGIN SELECT RAISE(ABORT,'Job operation is quarantined; recovery preserved'); END''');
    }
  }

  static Future<int> captureGeneration(BriskersLocalDatabase db, String businessId) async {
    if (!await _installed(db)) return 0;
    final row = await db.customSelect(
      'SELECT COALESCE(MAX(generation),0) AS generation FROM local_job_quarantines WHERE business_id=?',
      variables: [Variable<String>(businessId)],
    ).getSingle();
    return row.read<int>('generation');
  }

  static Future<Map<String, int>> quarantineGenerations(BriskersLocalDatabase db, String businessId) async {
    if (!await _installed(db)) return {};
    final rows = await db.customSelect(
      'SELECT job_id,generation FROM local_job_quarantines WHERE business_id=?',
      variables: [Variable<String>(businessId)],
    ).get();
    return {for (final row in rows) row.read<String>('job_id'): row.read<int>('generation')};
  }

  static Future<Map<String, int>> entityQuarantineGenerations(BriskersLocalDatabase db, String businessId,
      {String? entityType}) async {
    if (!await _installed(db)) return {};
    final rows = await db.customSelect(
      'SELECT e.entity_id,MAX(q.generation) AS generation FROM local_job_quarantine_entities e JOIN local_job_quarantines q '
      'ON q.business_id=e.business_id AND q.job_id=e.job_id '
      "WHERE e.business_id=?${entityType == null ? '' : ' AND e.entity_type=?'} GROUP BY e.entity_id",
      variables: [Variable<String>(businessId), if (entityType != null) Variable<String>(entityType)],
    ).get();
    return {for (final row in rows) row.read<String>('entity_id'): row.read<int>('generation')};
  }

  static Future<Set<String>> blockedJobIds(BriskersLocalDatabase db, String businessId) async {
    if (!await _installed(db)) return {};
    final rows = await db.customSelect(
      "SELECT job_id FROM local_job_quarantines WHERE business_id=? AND state<>'authorized'",
      variables: [Variable<String>(businessId)],
    ).get();
    return rows.map((row) => row.read<String>('job_id')).toSet();
  }

  static Future<Set<String>> blockedEntityIds(BriskersLocalDatabase db, String businessId,
      {String? entityType}) async {
    if (!await _installed(db)) return {};
    final rows = await db.customSelect(
      "SELECT e.entity_id FROM local_job_quarantine_entities e JOIN local_job_quarantines q "
      "ON q.business_id=e.business_id AND q.job_id=e.job_id "
      "WHERE e.business_id=? AND q.state<>'authorized'${entityType == null ? '' : ' AND e.entity_type=?'}",
      variables: [Variable<String>(businessId), if (entityType != null) Variable<String>(entityType)],
    ).get();
    return rows.map((row) => row.read<String>('entity_id')).toSet();
  }

  static Future<bool> hasRecovery(BriskersLocalDatabase db, String businessId) async {
    if (!await _installed(db)) return false;
    return (await db.customSelect(
      'SELECT 1 FROM local_job_recovery_rows WHERE business_id=? LIMIT 1',
      variables: [Variable<String>(businessId)],
    ).get()).isNotEmpty;
  }

  static Future<bool> isJobBlocked(BriskersLocalDatabase db, String businessId, String jobId) async {
    if (!await _installed(db)) return false;
    return (await db.customSelect(
      "SELECT 1 FROM local_job_quarantines WHERE business_id=? AND job_id=? AND state<>'authorized'",
      variables: [Variable<String>(businessId), Variable<String>(jobId)],
    ).get()).isNotEmpty;
  }

  static Future<bool> isEntityBlocked(BriskersLocalDatabase db, String businessId,
      Iterable<String?> entityIds) async {
    final ids = entityIds.whereType<String>().where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty || !await _installed(db)) return false;
    final placeholders = List.filled(ids.length, '?').join(',');
    return (await db.customSelect(
      "SELECT 1 FROM local_job_quarantine_entities e JOIN local_job_quarantines q "
      "ON q.business_id=e.business_id AND q.job_id=e.job_id "
      "WHERE e.business_id=? AND q.state<>'authorized' AND e.entity_id IN ($placeholders) LIMIT 1",
      variables: [Variable<String>(businessId), ...ids.map(Variable<String>.new)],
    ).get()).isNotEmpty;
  }

  static Future<void> quarantineJobs(
    BriskersLocalDatabase db, String businessId, Iterable<String> jobIds,
  ) async {
    final ids = jobIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    await db.transaction(() async {
      await _ensureSchema(db);
      final generation = await captureGeneration(db, businessId) + 1;
      for (final jobId in ids) {
        await _quarantineOne(db, businessId, jobId, generation);
      }
    });
    _events.add((businessId: businessId, jobIds: Set.unmodifiable(ids)));
  }

  static Future<void> _quarantineOne(
    BriskersLocalDatabase db, String businessId, String jobId, int nextGeneration,
  ) async {
    // Every new observation invalidates requests started before it, even when
    // the previous archive is still unresolved. Recovery rows remain immutable.
    final generation = nextGeneration;
    await db.customStatement('''INSERT INTO local_job_quarantines
      (business_id,job_id,generation,state,created_at) VALUES (?,?,?,'unclassified',?)
      ON CONFLICT(business_id,job_id) DO UPDATE SET
        generation=excluded.generation,state='unclassified'
    ''', [businessId, jobId, generation, DateTime.now().toUtc().millisecondsSinceEpoch]);

    final rowsByTable = <String, List<QueryRow>>{};
    Future<List<QueryRow>> read(String table, String where, List<String> values) =>
      db.customSelect('SELECT * FROM $table WHERE business_id=? AND ($where)',
        variables: [Variable<String>(businessId), ...values.map(Variable<String>.new)],
      ).get();
    rowsByTable['local_jobs'] = await read('local_jobs', 'id=?', [jobId]);
    for (final table in const ['local_job_visits', 'local_job_assignments', 'local_pre_inspections']) {
      rowsByTable[table] = await read(table, 'job_id=?', [jobId]);
    }
    rowsByTable['local_pre_inspection_photos'] = await read('local_pre_inspection_photos',
      'inspection_id IN (SELECT id FROM local_pre_inspections WHERE business_id=? AND job_id=?)',
      [businessId, jobId]);
    final vehicleId = rowsByTable['local_jobs']!.firstOrNull?.readNullable<String>('vehicle_id');
    var soleVehicle = false;
    if (vehicleId != null) {
      soleVehicle = (await db.customSelect(
        'SELECT 1 FROM local_jobs WHERE business_id=? AND vehicle_id=? AND id<>?',
        variables: [Variable<String>(businessId), Variable<String>(vehicleId), Variable<String>(jobId)],
      ).get()).isEmpty;
    }
    rowsByTable['local_findings'] = await read('local_findings',
      soleVehicle ? '(found_job_id=? OR repair_job_id=? OR vehicle_id=?)' : '(found_job_id=? OR repair_job_id=?)',
      [jobId, jobId, if (soleVehicle) vehicleId!]);
    final findingIds = rowsByTable['local_findings']!.map((row) => row.read<String>('id')).toList();
    rowsByTable['local_finding_photos'] = findingIds.isEmpty ? [] : await read('local_finding_photos',
      'finding_id IN (${List.filled(findingIds.length, '?').join(',')})', findingIds);

    final affected = <String>{jobId};
    for (final entry in rowsByTable.entries) {
      for (final row in entry.value) {
        final id = row.data[_ownedTables[entry.key]].toString();
        affected.add(id);
        await _registerEntity(db, businessId, jobId, entry.key, id);
        await _archiveRow(db, businessId, jobId, generation, entry.key, id, row.data);
      }
    }
    await _registerEntity(db, businessId, jobId, 'local_jobs', jobId);
    // Documents retain their independent invoice read permissions. Their IDs
    // still connect any pending payment/conversion operations to this recovery.
    final documents = await read('local_documents', 'job_id=?', [jobId]);
    for (final row in documents) {
      final id = row.read<String>('id');
      affected.add(id);
      await _registerEntity(db, businessId, jobId, 'queue_dependency', id);
    }
    // Receipt uploads may carry only a transaction ID after their parent
    // transaction was acknowledged. Recover that relationship from the local
    // financial snapshots instead of treating the photo as unrelated.
    final linkedTransactions = <String>{};
    final knownUnrelatedTransactions = <String>{};
    void collectTransactions(Object? value) {
      if (value is List) {
        for (final child in value) { collectTransactions(child); }
      } else if (value is Map) {
        final id = (value['transaction_id'] ?? value['id'])?.toString();
        if (id != null && id.isNotEmpty) {
          if (LocalCleanupSafety.referencesAny(value, affected)) {
            linkedTransactions.add(id);
          } else if (value.containsKey('job_id') || value.containsKey('document_id')) {
            knownUnrelatedTransactions.add(id);
          }
        }
        for (final child in value.values) { collectTransactions(child); }
      }
    }
    final financial = await db.customSelect(
      "SELECT payload_json FROM local_financial_cache WHERE business_id=? AND "
      "(cache_key LIKE 'transaction_detail_%' OR cache_key IN ('transactions_snapshot','linked_expenses_complete_v1'))",
      variables: [Variable<String>(businessId)],
    ).get();
    for (final row in financial) {
      try { collectTransactions(jsonDecode(row.read<String>('payload_json'))); }
      catch (_) { /* Unknown receipt relationships stay conservative below. */ }
    }
    for (final id in linkedTransactions) {
      affected.add(id);
      await _registerEntity(db, businessId, jobId, 'queue_dependency', id);
    }
    final queue = await db.customSelect('SELECT * FROM sync_outbox WHERE business_id=?',
      variables: [Variable<String>(businessId)]).get();
    final selected = <int>{};
    void collectOperationIdentities(Object? value) {
      if (value is List) {
        for (final child in value) { collectOperationIdentities(child); }
      } else if (value is Map) {
        for (final entry in value.entries) {
          if (const ['job_id', 'document_id', 'transaction_id', 'local_transaction_id',
              'finding_id', 'inspection_id', 'visit_id', 'attachment_id'].contains(entry.key) &&
              entry.value is String && (entry.value as String).isNotEmpty) {
            affected.add(entry.value as String);
          }
          collectOperationIdentities(entry.value);
        }
      }
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final row in queue) {
        final id = row.read<int>('id');
        if (selected.contains(id)) continue;
        Object? payload;
        var opaque = false;
        try {
          payload = jsonDecode(row.read<String>('payload_json'));
          opaque = payload is! Map;
        } catch (_) { opaque = true; }
        final uncertainReceipt = row.read<String>('entity_type') == 'financial_photo' &&
            (payload is! Map || !knownUnrelatedTransactions.contains(payload['transaction_id']?.toString()));
        if (opaque || uncertainReceipt || affected.contains(row.read<String>('entity_id')) ||
            LocalCleanupSafety.referencesAny(payload, affected)) {
          selected.add(id);
          affected.add(row.read<String>('entity_id'));
          collectOperationIdentities(payload);
          changed = true;
        }
      }
    }
    for (final id in affected) {
      await _registerEntity(db, businessId, jobId, 'queue_dependency', id);
    }
    for (final row in queue.where((row) => selected.contains(row.read<int>('id')))) {
      await _registerEntity(db, businessId, jobId, 'queue_dependency', row.read<String>('entity_id'));
      await _archiveRow(db, businessId, jobId, generation, 'sync_outbox',
        row.read<int>('id').toString(), row.data);
      await db.customStatement('DELETE FROM sync_outbox WHERE business_id=? AND id=?',
        [businessId, row.read<int>('id')]);
    }
    for (final table in _ownedTables.keys.toList().reversed) {
      for (final row in rowsByTable[table]!) {
        await db.customStatement('DELETE FROM $table WHERE business_id=? AND ${_ownedTables[table]}=?',
          [businessId, row.data[_ownedTables[table]]]);
      }
    }
  }

  static Future<void> _registerEntity(BriskersLocalDatabase db, String businessId,
      String jobId, String type, String id) => db.customStatement(
    'INSERT OR IGNORE INTO local_job_quarantine_entities(business_id,job_id,entity_type,entity_id) VALUES (?,?,?,?)',
    [businessId, jobId, type, id]);

  static Future<void> _archiveRow(BriskersLocalDatabase db, String businessId,
      String jobId, int generation, String table, String key, Map<String, dynamic> row) => db.customStatement(
    '''INSERT OR IGNORE INTO local_job_recovery_rows
       (business_id,job_id,generation,table_name,original_key,row_json,captured_at)
       VALUES (?,?,?,?,?,?,?)''',
    [businessId, jobId, generation, table, key, jsonEncode(row), DateTime.now().toUtc().millisecondsSinceEpoch]);

  static Future<Set<String>> unclassifiedJobIds(BriskersLocalDatabase db, String businessId) async {
    if (!await _installed(db)) return {};
    final rows = await db.customSelect("SELECT job_id FROM local_job_quarantines WHERE business_id=? AND state='unclassified'",
      variables: [Variable<String>(businessId)]).get();
    return rows.map((row) => row.read<String>('job_id')).toSet();
  }

  static Future<void> classifyJobs(BriskersLocalDatabase db, String businessId,
      Iterable<String> jobIds, {required Set<String> cleanupJobIds, int? observedGeneration}) async {
    if (!await _installed(db)) return;
    for (final id in jobIds) {
      await db.customStatement("UPDATE local_job_quarantines SET state=? "
        "WHERE business_id=? AND job_id=? AND state<>'authorized' AND (? IS NULL OR generation<=? OR ?=1)",
        [cleanupJobIds.contains(id) ? 'cleanup_deleted' : 'permission_revoked', businessId, id,
          observedGeneration, observedGeneration, cleanupJobIds.contains(id) ? 1 : 0]);
    }
  }

  /// Only a positive server response requested at or after quarantine may
  /// rebuild current display. Archived historical edits are never restored.
  static Future<bool> authorizeFreshJob(BriskersLocalDatabase db, String businessId,
      String jobId, {required int requestGeneration}) async {
    if (!await _installed(db)) return true;
    final rows = await db.customSelect('SELECT generation,state FROM local_job_quarantines WHERE business_id=? AND job_id=?',
      variables: [Variable<String>(businessId), Variable<String>(jobId)]).get();
    if (rows.isEmpty) return true;
    if (rows.single.read<int>('generation') > requestGeneration) return false;
    await db.customStatement("UPDATE local_job_quarantines SET state='authorized' WHERE business_id=? AND job_id=? AND generation<=?",
      [businessId, jobId, requestGeneration]);
    final current = await db.customSelect(
      "SELECT 1 FROM local_job_quarantines WHERE business_id=? AND job_id=? AND state='authorized' AND generation<=?",
      variables: [Variable<String>(businessId), Variable<String>(jobId), Variable<int>(requestGeneration)],
    ).get();
    return current.isNotEmpty;
  }

  static Future<void> assertReplayAllowed(BriskersLocalDatabase db, String businessId,
      {int? outboxId}) async {
    if (await _installed(db)) {
      final unknown = await db.customSelect("SELECT 1 FROM local_job_quarantines WHERE business_id=? AND state='unclassified' LIMIT 1",
        variables: [Variable<String>(businessId)]).get();
      if (unknown.isNotEmpty) {
        throw const LocalJobQuarantineException('Synchronization is paused while revoked Job access is verified. Pending work is preserved.');
      }
    }
    if (outboxId != null) {
      if (await _installed(db)) {
        final interrupted = await db.customSelect(
          'SELECT 1 FROM local_job_recovery_receipts r WHERE r.business_id=? AND r.outbox_id=? '
          'AND r.request_generation < (SELECT COALESCE(MAX(generation),0) FROM local_job_quarantines WHERE business_id=?) LIMIT 1',
          variables: [Variable<String>(businessId), Variable<int>(outboxId), Variable<String>(businessId)],
        ).get();
        if (interrupted.isNotEmpty) {
          throw const LocalJobQuarantineException('This operation has a server acknowledgement interrupted by access revocation. Review its preserved receipt before retrying.');
        }
      }
      final row = await db.customSelect("SELECT 1 FROM sync_outbox WHERE business_id=? AND id=? AND state IN ('pending','inflight')",
        variables: [Variable<String>(businessId), Variable<int>(outboxId)]).get();
      if (row.isEmpty) {
        throw const LocalJobQuarantineException('This queued operation is no longer active. Its recovery must be reviewed before replay.');
      }
    }
  }

  static Future<T> guardReplay<T>(BriskersLocalDatabase db, String businessId,
      Future<T> Function() request, {int? outboxId}) async {
    if (!await _installed(db)) {
      await db.transaction(() => _ensureSchema(db));
    }
    final requestGeneration = await captureGeneration(db, businessId);
    await assertReplayAllowed(db, businessId, outboxId: outboxId);
    final response = await request();
    // Persist every returned acknowledgement before a later await can let
    // quarantine retire the queue. The next caller-side guard may then throw
    // without losing the server's payment/registration/operation identity.
    String serialized;
    try {
      serialized = jsonEncode(response);
    } catch (_) {
      serialized = jsonEncode({'response': response.toString()});
    }
    await db.transaction(() async {
      await _ensureSchema(db);
      await db.customStatement('INSERT INTO local_job_recovery_receipts(business_id,outbox_id,response_json,request_generation,captured_at) VALUES (?,?,?,?,?)',
        [businessId, outboxId, serialized, requestGeneration, DateTime.now().toUtc().millisecondsSinceEpoch]);
    });
    await assertReplayAllowed(db, businessId, outboxId: outboxId);
    return response;
  }
}
