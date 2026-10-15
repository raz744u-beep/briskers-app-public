import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_cleanup_safety.dart';

/// Durable visibility/replay fences. Rows, photos and shared findings are kept.
/// Pending is reversible; accepted tombstones are permanent, including on restart.
class LocalJobRetirement {
  static final _events =
      StreamController<({String businessId, Set<String> jobIds})>.broadcast(
        sync: true,
      );
  static Stream<({String businessId, Set<String> jobIds})> get events =>
      _events.stream;
  static const blockedStates = "('pending','accepted','locally_cancelled')";

  static final _installed = Expando<bool>('retirement_schema');
  static Future<void> ensureSchema(BriskersLocalDatabase db) async {
    if (_installed[db] == true &&
        (await db
                .customSelect(
                  "SELECT 1 FROM sqlite_master WHERE type='trigger' AND name='retirement_accepted_no_change'",
                )
                .get())
            .isNotEmpty) {
      return;
    }
    await db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_job_retirement_requests (
      business_id TEXT NOT NULL, job_id TEXT NOT NULL, operation_id TEXT NOT NULL,
      actor_id TEXT NOT NULL, snapshot_json TEXT NOT NULL, state TEXT NOT NULL,
      created_at INTEGER NOT NULL, attempt_count INTEGER NOT NULL DEFAULT 0, outcome_uncertain INTEGER NOT NULL DEFAULT 0,
      last_error TEXT, receipt_json TEXT,
      PRIMARY KEY(business_id,operation_id), UNIQUE(business_id,job_id)
    )''',
    );
    final requestColumns = await db
        .customSelect('PRAGMA table_info(local_job_retirement_requests)')
        .get();
    if (!requestColumns.any(
      (r) => r.read<String>('name') == 'outcome_uncertain',
    )) {
      await db.customStatement(
        'ALTER TABLE local_job_retirement_requests ADD COLUMN outcome_uncertain INTEGER NOT NULL DEFAULT 1',
      );
    }
    await db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_job_retirement_feed_context (
      business_id TEXT PRIMARY KEY NOT NULL, visibility_scope TEXT NOT NULL)''',
    );
    await db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_job_retirement_dependencies (
      business_id TEXT NOT NULL, job_id TEXT NOT NULL, entity_id TEXT NOT NULL,
      PRIMARY KEY(business_id,job_id,entity_id))''',
    );
    await db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_job_retirement_entities (
      business_id TEXT NOT NULL, job_id TEXT NOT NULL, entity_kind TEXT NOT NULL,
      entity_id TEXT NOT NULL, operation_id TEXT NOT NULL, state TEXT NOT NULL,
      PRIMARY KEY(business_id,entity_kind,entity_id)
    )''',
    );
    await db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_job_retirement_previews (
      business_id TEXT NOT NULL, job_id TEXT NOT NULL, actor_id TEXT NOT NULL,
      snapshot_json TEXT NOT NULL, PRIMARY KEY(business_id,job_id)
    )''',
    );
    await db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_job_retirement_recovery (
      business_id TEXT NOT NULL, job_id TEXT NOT NULL, outbox_id INTEGER NOT NULL,
      original_json TEXT NOT NULL, PRIMARY KEY(business_id,job_id,outbox_id)
    )''',
    );
    // SQLite fences cover every writer, including late acknowledgements and
    // older code paths that do not know about the deletion service yet.
    final refs = <String, String>{
      'local_jobs': "e.entity_kind='job' AND e.entity_id=NEW.id",
      'local_documents': "(e.entity_kind='invoice' AND e.entity_id=NEW.id) OR (NEW.kind='invoice' AND e.entity_kind='job' AND e.entity_id=NEW.job_id)",
      'local_job_visits': "e.entity_kind='job' AND e.entity_id=NEW.job_id",
      'local_job_assignments': "e.entity_kind='job' AND e.entity_id=NEW.job_id",
      'local_pre_inspections': "e.entity_kind='job' AND e.entity_id=NEW.job_id",
    };
    for (final entry in refs.entries) {
      for (final action in ['INSERT', 'UPDATE', 'DELETE']) {
        final next = action == 'DELETE'
            ? '0'
            : "EXISTS(SELECT 1 FROM local_job_retirement_entities e WHERE e.business_id=NEW.business_id AND e.state IN $blockedStates AND (${entry.value}))";
        final old = action == 'INSERT'
            ? '0'
            : "EXISTS(SELECT 1 FROM local_job_retirement_entities e WHERE e.business_id=OLD.business_id AND e.state IN $blockedStates AND (${entry.value.replaceAll('NEW.', 'OLD.')}))";
        await db.customStatement(
          '''CREATE TRIGGER IF NOT EXISTS retirement_${entry.key}_${action.toLowerCase()}
          BEFORE $action ON ${entry.key}
          WHEN ($next) OR ($old)
          BEGIN SELECT RAISE(ABORT,'Job deletion pending or accepted; preserved data is read-only'); END''',
        );
      }
    }
    for (final action in ['INSERT', 'UPDATE']) {
      await db.customStatement(
        '''CREATE TRIGGER IF NOT EXISTS retirement_outbox_${action.toLowerCase()}
        BEFORE $action ON sync_outbox
        WHEN NEW.state IN ('pending','inflight') AND EXISTS(
          SELECT 1 FROM local_job_retirement_entities e WHERE e.business_id=NEW.business_id
          AND e.state IN $blockedStates AND (e.entity_id=NEW.entity_id OR
            json_valid(NEW.payload_json)=0 OR EXISTS(
              SELECT 1 FROM json_tree(CASE WHEN json_valid(NEW.payload_json)
                THEN NEW.payload_json ELSE '{}' END) j WHERE j.type='text' AND j.value=e.entity_id) OR EXISTS(
              SELECT 1 FROM local_job_retirement_dependencies d WHERE d.business_id=e.business_id AND d.job_id=e.job_id
              AND (d.entity_id=NEW.entity_id OR EXISTS(SELECT 1 FROM json_tree(CASE WHEN json_valid(NEW.payload_json) THEN NEW.payload_json ELSE '{}' END) j
                WHERE j.type='text' AND j.value=d.entity_id)))))
        BEGIN SELECT RAISE(ABORT,'Job deletion blocks replay; recoverable work is preserved'); END''',
      );
    }
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS retirement_accepted_no_delete BEFORE DELETE ON local_job_retirement_entities "
      "WHEN OLD.state='accepted' BEGIN SELECT RAISE(ABORT,'Accepted retirement tombstones are permanent'); END",
    );
    await db.customStatement(
      "CREATE TRIGGER IF NOT EXISTS retirement_accepted_no_change BEFORE UPDATE ON local_job_retirement_entities "
      "WHEN OLD.state='accepted' AND (NEW.state<>OLD.state OR NEW.entity_id<>OLD.entity_id OR NEW.business_id<>OLD.business_id OR NEW.entity_kind<>OLD.entity_kind OR NEW.job_id<>OLD.job_id) "
      "BEGIN SELECT RAISE(ABORT,'Accepted retirement tombstones are permanent'); END",
    );
    _installed[db] = true;
  }

  static Future<Set<String>> _ids(
    BriskersLocalDatabase db,
    String businessId,
    String kind,
  ) async {
    await ensureSchema(db);
    return (await db
            .customSelect(
              'SELECT entity_id FROM local_job_retirement_entities '
              'WHERE business_id=? AND entity_kind=? AND state IN $blockedStates',
              variables: [Variable<String>(businessId), Variable<String>(kind)],
            )
            .get())
        .map((row) => row.read<String>('entity_id'))
        .toSet();
  }

  static Future<Set<String>> blockedJobIds(
    BriskersLocalDatabase db,
    String businessId,
  ) => _ids(db, businessId, 'job');
  static Future<Set<String>> blockedDocumentIds(
    BriskersLocalDatabase db,
    String businessId,
  ) async {
    final ids = await _ids(db, businessId, 'invoice');
    final linked = await db
        .customSelect(
          "SELECT d.id FROM local_documents d WHERE d.business_id=? AND d.kind='invoice' "
          "AND EXISTS(SELECT 1 FROM local_job_retirement_entities e WHERE e.business_id=d.business_id "
          "AND e.entity_kind='job' AND e.entity_id=d.job_id AND e.state IN $blockedStates)",
          variables: [Variable<String>(businessId)],
        )
        .get();
    ids.addAll(linked.map((r) => r.read<String>('id')));
    return ids;
  }

  static Future<bool> isJobBlocked(
    BriskersLocalDatabase db,
    String businessId,
    String jobId,
  ) async => (await blockedJobIds(db, businessId)).contains(jobId);
  static Future<bool> isDocumentBlocked(
    BriskersLocalDatabase db,
    String businessId,
    String documentId,
  ) async => (await blockedDocumentIds(db, businessId)).contains(documentId);

  static void notify(
    BriskersLocalDatabase db,
    String businessId,
    Iterable<String> jobIds,
  ) {
    db.notifyUpdates({
      const TableUpdate('local_jobs'),
      const TableUpdate('local_documents'),
    });
    _events.add((businessId: businessId, jobIds: Set.unmodifiable(jobIds)));
  }

  static Future<void> recordEntity(
    BriskersLocalDatabase db, {
    required String businessId,
    required String jobId,
    required String entityKind,
    required String entityId,
    required String operationId,
    required String state,
  }) async {
    await db.customStatement(
      '''INSERT INTO local_job_retirement_entities
      (business_id,job_id,entity_kind,entity_id,operation_id,state) VALUES (?,?,?,?,?,?)
      ON CONFLICT(business_id,entity_kind,entity_id) DO UPDATE SET
      state=CASE WHEN local_job_retirement_entities.state='accepted' THEN 'accepted' ELSE excluded.state END,
      operation_id=CASE WHEN local_job_retirement_entities.state='accepted'
        THEN local_job_retirement_entities.operation_id ELSE excluded.operation_id END''',
      [businessId, jobId, entityKind, entityId, operationId, state],
    );
  }

  /// Archive related queue rows without deleting them or their local files.
  /// Never restore automatically after a rejection: a human must review work
  /// that raced an authoritative deletion on another device.
  static Future<void> quarantineRelated(
    BriskersLocalDatabase db,
    String businessId,
    String jobId,
  ) async {
    final ids = <String>{jobId};
    for (final table in [
      'local_documents',
      'local_job_visits',
      'local_pre_inspections',
    ]) {
      final rows = await db
          .customSelect(
            'SELECT id FROM $table WHERE business_id=? AND job_id=?',
            variables: [Variable<String>(businessId), Variable<String>(jobId)],
          )
          .get();
      ids.addAll(rows.map((row) => row.read<String>('id')));
    }
    final entities = await db
        .customSelect(
          'SELECT entity_id FROM local_job_retirement_entities WHERE business_id=? AND job_id=?',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();
    ids.addAll(entities.map((row) => row.read<String>('entity_id')));
    final findings = await db
        .customSelect(
          'SELECT id FROM local_findings WHERE business_id=? AND (found_job_id=? OR repair_job_id=?)',
          variables: [
            Variable<String>(businessId),
            Variable<String>(jobId),
            Variable<String>(jobId),
          ],
        )
        .get();
    ids.addAll(findings.map((row) => row.read<String>('id')));
    final photos = await db
        .customSelect(
          '''SELECT p.id,p.attachment_id FROM local_pre_inspection_photos p
      JOIN local_pre_inspections i ON i.business_id=p.business_id AND i.id=p.inspection_id
      WHERE i.business_id=? AND i.job_id=? UNION ALL
      SELECT p.id,p.attachment_id FROM local_finding_photos p JOIN local_findings f
      ON f.business_id=p.business_id AND f.id=p.finding_id WHERE f.business_id=? AND (f.found_job_id=? OR f.repair_job_id=?)''',
          variables: [
            Variable<String>(businessId),
            Variable<String>(jobId),
            Variable<String>(businessId),
            Variable<String>(jobId),
            Variable<String>(jobId),
          ],
        )
        .get();
    for (final photo in photos) {
      ids.add(photo.read<String>('id'));
      final attachment = photo.readNullable<String>('attachment_id');
      if (attachment != null) ids.add(attachment);
    }
    final knownUnrelatedTransactions = <String>{};
    void collectTransactions(Object? value) {
      if (value is List) {
        for (final child in value) {
          collectTransactions(child);
        }
      }
      if (value is Map) {
        final id = (value['transaction_id'] ?? value['id'])?.toString();
        if (id != null && id.isNotEmpty) {
          if (LocalCleanupSafety.referencesAny(value, ids)) {
            ids.add(id);
          } else if (value.containsKey('job_id') ||
              value.containsKey('document_id')) {
            knownUnrelatedTransactions.add(id);
          }
        }
        for (final child in value.values) {
          collectTransactions(child);
        }
      }
    }

    final financial = await db
        .customSelect(
          "SELECT payload_json FROM local_financial_cache WHERE business_id=? AND (cache_key LIKE 'transaction_detail_%' OR cache_key IN ('transactions_snapshot','linked_expenses_complete_v1'))",
          variables: [Variable<String>(businessId)],
        )
        .get();
    for (final row in financial) {
      try {
        collectTransactions(jsonDecode(row.read<String>('payload_json')));
      } catch (_) {
        /* unknown financial relationships remain quarantined */
      }
    }
    final rows = await db
        .customSelect(
          "SELECT * FROM sync_outbox WHERE business_id=? AND state NOT IN ('retirement_quarantine','cancelled')",
          variables: [Variable<String>(businessId)],
        )
        .get();
    final selected = <int>{};
    var changed = true;
    while (changed) {
      changed = false;
      for (final row in rows) {
        final id = row.read<int>('id');
        if (selected.contains(id)) continue;
        Object? payload;
        try {
          payload = jsonDecode(row.read<String>('payload_json'));
        } catch (_) {
          /* Preserve unknown payloads. */
        }
        final unknownReceipt =
            row.read<String>('entity_type') == 'financial_photo' &&
            (payload is! Map ||
                !knownUnrelatedTransactions.contains(
                  payload['transaction_id']?.toString(),
                ));
        if (payload is! Map ||
            unknownReceipt ||
            ids.contains(row.read<String>('entity_id')) ||
            LocalCleanupSafety.referencesAny(payload, ids)) {
          selected.add(id);
          ids.add(row.read<String>('entity_id'));
          changed = true;
        }
      }
    }
    for (final id in ids) {
      await db.customStatement(
        'INSERT OR IGNORE INTO local_job_retirement_dependencies (business_id,job_id,entity_id) VALUES (?,?,?)',
        [businessId, jobId, id],
      );
    }
    for (final row in rows.where((r) => selected.contains(r.read<int>('id')))) {
      await db.customStatement(
        'INSERT OR IGNORE INTO local_job_retirement_recovery '
        '(business_id,job_id,outbox_id,original_json) VALUES (?,?,?,?)',
        [businessId, jobId, row.read<int>('id'), jsonEncode(row.data)],
      );
      await db.customStatement(
        "UPDATE sync_outbox SET state='retirement_quarantine',last_error=? WHERE business_id=? AND id=?",
        [
          'Job deleted or deletion pending. Work and files preserved for review.',
          businessId,
          row.read<int>('id'),
        ],
      );
    }
  }

  static Future<void> assertReplayAllowed(
    BriskersLocalDatabase db,
    String businessId, {
    int? outboxId,
  }) async {
    await ensureSchema(db);
    if (outboxId == null) return;
    final rows = await db
        .customSelect(
          'SELECT entity_id,payload_json,state FROM sync_outbox WHERE business_id=? AND id=?',
          variables: [Variable<String>(businessId), Variable<int>(outboxId)],
        )
        .get();
    if (rows.isEmpty) return;
    final row = rows.single;
    final ids = {
      ...await blockedJobIds(db, businessId),
      ...await blockedDocumentIds(db, businessId),
    };
    final dependencies = await db
        .customSelect(
          "SELECT d.entity_id FROM local_job_retirement_dependencies d JOIN local_job_retirement_entities e "
          "ON e.business_id=d.business_id AND e.job_id=d.job_id AND e.entity_kind='job' WHERE d.business_id=? AND e.state IN $blockedStates",
          variables: [Variable<String>(businessId)],
        )
        .get();
    ids.addAll(dependencies.map((r) => r.read<String>('entity_id')));
    Object? payload;
    try {
      payload = jsonDecode(row.read<String>('payload_json'));
    } catch (_) {
      /* fail closed with active fence */
    }
    if (row.read<String>('state') == 'retirement_quarantine' ||
        (ids.isNotEmpty &&
            (payload is! Map ||
                ids.contains(row.read<String>('entity_id')) ||
                LocalCleanupSafety.referencesAny(payload, ids)))) {
      throw StateError(
        'This Job has a pending or accepted deletion. Queued work is preserved for review.',
      );
    }
  }
}
