import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart';

/// Server deletion and local erasure are separate outcomes. A committed server
/// receipt hides data immediately; interrupted cleanup remains resumable.
class LocalDeletionCleanupResult {
  const LocalDeletionCleanupResult(this.completed, {this.issueCode});
  final bool completed;
  bool get complete => completed;
  final String? issueCode;
}

/// v3 deliberately never uses retirement/quarantine graph discovery. Only
/// identities in a verified server receipt authorize destructive selection.
/// Callers must verify the authenticated actor, tenant, request and full receipt
/// before calling applyVerifiedReceipt. This class validates its wire shape too.
class LocalJobDeletionV3 {
  static const protocol = 'owner-deletion-3.0';
  // Set by the authenticated application boundary; tests may inject an actor.
  static String? Function()? currentActorIdProvider;
  static const entityKinds = <String>{
    'job', 'invoice', 'estimate', 'payment', 'transaction', 'job_assignment',
    'job_visit', 'pre_inspection', 'pre_inspection_photo', 'finding',
    'attachment', 'appointment', 'operation',
    'authorization', 'document_line', 'document_disclaimer', 'document_revision',
    'document_attachment', 'job_attachment', 'job_assignment_request',
    'job_visit_assignment', 'job_labor', 'job_internal_note', 'job_status_event',
    'payment_allocation', 'expense_allocation', 'payroll_allocation',
    // Explicit identity-only fence for optional server audit-graph support.
    // No local audit-table deletion is implied by receiving this identity.
    'payment_edit_audit',
    'expense_attachment', 'receipt_item', 'appointment_request', 'conversation',
    'conversation_member', 'message', 'message_attachment', 'activity_event',
    'notification', 'kiosk_registration', 'legacy_link', 'finding_attachment_link',
    'sales_estimate_link', 'sales_receipt_link', 'receipt_detail', 'document_restore',
    'import_row', 'import_issue', 'legacy_photo_map', 'legacy_stage',
  };
  static final _events =
      StreamController<({String businessId, Set<String> jobIds})>.broadcast(sync: true);
  static Stream<({String businessId, Set<String> jobIds})> get events => _events.stream;

  // These are schema identifiers, never server-supplied SQL identifiers.
  static const _tables = <String, (String, String, String)>{
    'job': ('local_jobs', 'id', ''),
    'invoice': ('local_documents', 'id', " AND kind='invoice'"),
    'estimate': ('local_documents', 'id', " AND kind='estimate'"),
    'job_assignment': ('local_job_assignments', 'assignment_id', ''),
    'job_visit': ('local_job_visits', 'id', ''),
    'pre_inspection': ('local_pre_inspections', 'id', ''),
    'pre_inspection_photo': ('local_pre_inspection_photos', 'id', ''),
    'finding': ('local_findings', 'id', ''),
    'appointment': ('local_appointments', 'id', ''),
    // Delete only the app's SAF pointer; never the external source bytes.
    'transaction': ('local_expense_iq_photos', 'transaction_id', ''),
  };

  static String _matches(String kind, String value) =>
      "(e.entity_kind='$kind' AND e.entity_id=$value)";

  static final _installed = Expando<bool>('deletion_v3_schema');

  static const _outboxOperationSql = "e.entity_kind='operation' AND e.entity_id=(CASE "
      "WHEN NEW.entity_type='invoice_payment_received' THEN 'invoice_payment/' "
      "WHEN NEW.entity_type='document_draft_create' AND NEW.operation='create_quick_invoice' THEN 'quick_invoice/' "
      "WHEN NEW.entity_type='document_draft_create' AND NEW.operation='create_estimate' "
      "AND COALESCE(json_extract(CASE WHEN json_valid(NEW.payload_json) THEN NEW.payload_json ELSE '{}' END,'\$.job_id'),'')='' THEN 'standalone_estimate/' "
      "WHEN NEW.entity_type IN ('preinspection','preinspection_photo','finding_create','finding_update','finding_photo','financial_create','financial_photo') THEN 'sync/' "
      "ELSE NULL END)||json_extract(CASE WHEN json_valid(NEW.payload_json) THEN NEW.payload_json ELSE '{}' END,'\$.operation_id')";

  static Future<void> ensureSchema(BriskersLocalDatabase db) async {
    if (_installed[db] == true && (await db.customSelect(
        "SELECT 1 FROM sqlite_master WHERE type='trigger' AND name='deletion_v3_scope_outbox_delete'").get()).isNotEmpty &&
        (await db.customSelect('SELECT 1 FROM local_job_deletion_v3_schema WHERE singleton=1 AND version=7').get()).isNotEmpty) { return; }
    await db.transaction(() async {
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_schema (
        singleton INTEGER PRIMARY KEY CHECK(singleton=1), version INTEGER NOT NULL)''');
      // Replace only our owned triggers, atomically. Installed draft candidates
      // must not retain obsolete CREATE IF NOT EXISTS guard semantics.
      final ownedTriggers = <String>{
        'deletion_v3_marker_no_delete', 'deletion_v3_marker_no_update', 'deletion_v3_marker_no_replace',
        'deletion_v3_alias_no_delete', 'deletion_v3_alias_no_update', 'deletion_v3_alias_no_replace',
        'deletion_v3_scope_outbox_update', 'deletion_v3_scope_outbox_insert', 'deletion_v3_scope_outbox_delete', 'deletion_v3_scope_dirty_financial_delete',
        'deletion_v3_scope_dirty_financial_insert', 'deletion_v3_scope_dirty_financial_update',
        for (final table in {..._tables.values.map((entry) => entry.$1), 'local_finding_photos'})
          'deletion_v3_scope_dirty_${table}_delete',
        for (final table in {..._tables.values.map((entry) => entry.$1), 'local_finding_photos', 'sync_outbox', 'local_financial_cache'})
          for (final action in const ['insert', 'update']) 'deletion_v3_${table}_$action',
      };
      for (final name in ownedTriggers) { await db.customStatement('DROP TRIGGER IF EXISTS $name'); }
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_entities (
        business_id TEXT NOT NULL, job_id TEXT NOT NULL,
        operation_id TEXT NOT NULL, entity_kind TEXT NOT NULL, entity_id TEXT NOT NULL,
        PRIMARY KEY(business_id,entity_kind,entity_id))''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_offline_job_purge_entities (
        business_id TEXT NOT NULL, job_id TEXT NOT NULL, operation_id TEXT NOT NULL,
        entity_kind TEXT NOT NULL, entity_id TEXT NOT NULL,
        PRIMARY KEY(business_id,entity_kind,entity_id))''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_pending (
        business_id TEXT NOT NULL, job_id TEXT NOT NULL, operation_id TEXT NOT NULL,
        entity_kind TEXT NOT NULL, entity_id TEXT NOT NULL,
        PRIMARY KEY(business_id,operation_id,entity_kind,entity_id))''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_aliases (
        business_id TEXT NOT NULL, job_id TEXT NOT NULL, operation_id TEXT NOT NULL,
        entity_kind TEXT NOT NULL, entity_id TEXT NOT NULL,
        PRIMARY KEY(business_id,entity_kind,entity_id))''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_scope (
        business_id TEXT PRIMARY KEY NOT NULL, actor_id TEXT NOT NULL,
        visibility_scope TEXT NOT NULL, reader_scope TEXT NOT NULL,
        generation INTEGER NOT NULL, state TEXT NOT NULL)''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_scope_entities (
        business_id TEXT NOT NULL, entity_kind TEXT NOT NULL, entity_id TEXT NOT NULL,
        generation INTEGER NOT NULL, dirty INTEGER NOT NULL,
        PRIMARY KEY(business_id,entity_kind,entity_id))''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_scope_outbox (
        business_id TEXT NOT NULL, outbox_id INTEGER NOT NULL,
        PRIMARY KEY(business_id,outbox_id))''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_cache_scope (
        business_id TEXT NOT NULL, cache_key TEXT NOT NULL,
        generation INTEGER NOT NULL, dirty INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(business_id,cache_key))''');
      // Recreate the view for databases which installed the first v3 candidate.
      await db.customStatement('DROP VIEW IF EXISTS local_job_deletion_v3_fences');
      await db.customStatement('''CREATE VIEW local_job_deletion_v3_fences AS
        SELECT business_id,job_id,operation_id,entity_kind,entity_id FROM local_job_deletion_v3_entities
        UNION ALL SELECT business_id,job_id,operation_id,entity_kind,entity_id FROM local_job_deletion_v3_pending
        UNION ALL SELECT business_id,job_id,operation_id,entity_kind,entity_id FROM local_job_deletion_v3_aliases
        UNION ALL SELECT business_id,'','',entity_kind,entity_id FROM local_job_deletion_v3_scope_entities
        UNION ALL SELECT business_id,job_id,operation_id,entity_kind,entity_id FROM local_offline_job_purge_entities''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_scope_outbox_update
        BEFORE UPDATE ON sync_outbox
        WHEN EXISTS(SELECT 1 FROM local_job_deletion_v3_scope_outbox s
          WHERE s.business_id=OLD.business_id AND s.outbox_id=OLD.id)
        BEGIN SELECT RAISE(ABORT,'Authorization changed; retained work requires reconciliation'); END''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_scope_outbox_insert
        BEFORE INSERT ON sync_outbox
        WHEN EXISTS(SELECT 1 FROM local_job_deletion_v3_scope_outbox s
          WHERE s.business_id=NEW.business_id AND s.outbox_id=NEW.id)
        BEGIN SELECT RAISE(ABORT,'Retained queued work cannot be replaced'); END''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_scope_outbox_delete
        BEFORE DELETE ON sync_outbox
        WHEN EXISTS(SELECT 1 FROM local_job_deletion_v3_scope_outbox s
          WHERE s.business_id=OLD.business_id AND s.outbox_id=OLD.id)
        BEGIN SELECT RAISE(ABORT,'Retained queued work requires authorized reconciliation'); END''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_origins (
        business_id TEXT NOT NULL, operation_id TEXT NOT NULL, job_id TEXT NOT NULL, root_origin TEXT NOT NULL,
        PRIMARY KEY(business_id,operation_id))''');
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_cleanup (
        business_id TEXT NOT NULL, job_id TEXT NOT NULL, operation_id TEXT NOT NULL,
        graph_hash TEXT NOT NULL, state TEXT NOT NULL, issue_code TEXT, inventory_generation INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(business_id,operation_id))''');
      // A pending locator is necessary only until verified binary removal. It is
      // deleted on success, and never contains attachment/business row payloads.
      await db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_media (
        business_id TEXT NOT NULL, operation_id TEXT NOT NULL, local_path TEXT NOT NULL,
        PRIMARY KEY(business_id,operation_id,local_path))''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_marker_no_delete
        BEFORE DELETE ON local_job_deletion_v3_entities
        BEGIN SELECT RAISE(ABORT,'Verified deletion identities are permanent'); END''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_marker_no_update
        BEFORE UPDATE ON local_job_deletion_v3_entities
        BEGIN SELECT RAISE(ABORT,'Verified deletion identities are permanent'); END''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_marker_no_replace
        BEFORE INSERT ON local_job_deletion_v3_entities
        WHEN EXISTS(SELECT 1 FROM local_job_deletion_v3_entities e
          WHERE e.business_id=NEW.business_id AND e.entity_kind=NEW.entity_kind
          AND e.entity_id=NEW.entity_id AND (e.job_id<>NEW.job_id OR e.operation_id<>NEW.operation_id))
        BEGIN SELECT RAISE(ABORT,'Verified deletion identity cannot be reassigned'); END''');
      await db.customStatement("CREATE TRIGGER IF NOT EXISTS deletion_v3_alias_no_delete BEFORE DELETE ON local_job_deletion_v3_aliases BEGIN SELECT RAISE(ABORT,'Verified deletion aliases are permanent'); END");
      await db.customStatement("CREATE TRIGGER IF NOT EXISTS deletion_v3_alias_no_update BEFORE UPDATE ON local_job_deletion_v3_aliases BEGIN SELECT RAISE(ABORT,'Verified deletion aliases are permanent'); END");
      await db.customStatement("CREATE TRIGGER IF NOT EXISTS deletion_v3_alias_no_replace BEFORE INSERT ON local_job_deletion_v3_aliases WHEN EXISTS(SELECT 1 FROM local_job_deletion_v3_aliases e WHERE e.business_id=NEW.business_id AND e.entity_kind=NEW.entity_kind AND e.entity_id=NEW.entity_id AND (e.job_id<>NEW.job_id OR e.operation_id<>NEW.operation_id)) BEGIN SELECT RAISE(ABORT,'Verified deletion alias cannot be reassigned'); END");
      // An independently authorized document may refresh while its parent is
      // scope-hidden. Actual parent deletion/consent/cancellation still fences
      // it, and the document's own exact scope fence must be released first.
      final refs = <String, String>{
        'local_jobs': _matches('job', 'NEW.id'),
        'local_documents': "(e.entity_kind=NEW.kind AND e.entity_id=NEW.id) OR (e.operation_id<>'' AND ${_matches('job', 'NEW.job_id')})",
        'local_job_assignments': '${_matches('job_assignment', 'NEW.assignment_id')} OR ${_matches('job', 'NEW.job_id')}',
        'local_job_visits': '${_matches('job_visit', 'NEW.id')} OR ${_matches('job', 'NEW.job_id')}',
        'local_pre_inspections': '${_matches('pre_inspection', 'NEW.id')} OR ${_matches('job', 'NEW.job_id')}',
        'local_pre_inspection_photos': '${_matches('pre_inspection_photo', 'NEW.id')} OR ${_matches('attachment', 'NEW.attachment_id')} OR ${_matches('pre_inspection', 'NEW.inspection_id')}',
        'local_findings': _matches('finding', 'NEW.id'),
        'local_finding_photos': '${_matches('finding_photo', 'NEW.id')} OR ${_matches('attachment', 'NEW.attachment_id')} OR ${_matches('finding', 'NEW.finding_id')}',
        'local_appointments': _matches('appointment', 'NEW.id'),
        'local_expense_iq_photos': _matches('transaction', 'NEW.transaction_id'),
      };
      // OLD foreign-key associations are not ownership proof. A preserved,
      // reassigned row may correct its stale parent link; its exact deleted
      // identity, if present, is still permanently fenced.
      final oldRefs = <String, String>{
        'local_jobs': _matches('job', 'OLD.id'),
        'local_documents': "(e.entity_kind=OLD.kind AND e.entity_id=OLD.id)",
        'local_job_assignments': _matches('job_assignment', 'OLD.assignment_id'),
        'local_job_visits': _matches('job_visit', 'OLD.id'),
        'local_pre_inspections': _matches('pre_inspection', 'OLD.id'),
        'local_pre_inspection_photos': '${_matches('pre_inspection_photo', 'OLD.id')} OR ${_matches('attachment', 'OLD.attachment_id')}',
        'local_findings': _matches('finding', 'OLD.id'),
        'local_finding_photos': '${_matches('finding_photo', 'OLD.id')} OR ${_matches('attachment', 'OLD.attachment_id')}',
        'local_appointments': _matches('appointment', 'OLD.id'),
        'local_expense_iq_photos': _matches('transaction', 'OLD.transaction_id'),
      };
      await db.customStatement('DROP TRIGGER IF EXISTS deletion_v3_local_finding_photos_insert');
      await db.customStatement('DROP TRIGGER IF EXISTS deletion_v3_local_finding_photos_update');
      for (final entry in refs.entries) {
        await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_scope_dirty_${entry.key}_delete
          BEFORE DELETE ON ${entry.key}
          WHEN EXISTS(SELECT 1 FROM local_job_deletion_v3_scope_entities e
            WHERE e.business_id=OLD.business_id AND e.dirty=1 AND (${oldRefs[entry.key]}))
          BEGIN SELECT RAISE(ABORT,'Retained work requires authorized reconciliation'); END''');
        for (final action in const ['INSERT', 'UPDATE']) {
          final old = action == 'UPDATE'
              ? ' OR EXISTS(SELECT 1 FROM local_job_deletion_v3_fences e '
                'WHERE e.business_id=OLD.business_id AND (${oldRefs[entry.key]}))' : '';
          await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_${entry.key}_${action.toLowerCase()}
            BEFORE $action ON ${entry.key}
            WHEN EXISTS(SELECT 1 FROM local_job_deletion_v3_fences e
              WHERE e.business_id=NEW.business_id AND (${entry.value}))$old
            BEGIN SELECT RAISE(ABORT,'Verified deletion blocks stale recreation'); END''');
        }
      }
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_scope_dirty_financial_delete
        BEFORE DELETE ON local_financial_cache
        WHEN EXISTS(SELECT 1 FROM local_job_deletion_v3_cache_scope s
          WHERE s.business_id=OLD.business_id AND s.cache_key='financial:'||OLD.cache_key AND s.dirty=1)
        BEGIN SELECT RAISE(ABORT,'Retained financial work requires authorized reconciliation'); END''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_scope_dirty_financial_insert
        BEFORE INSERT ON local_financial_cache
        WHEN EXISTS(SELECT 1 FROM local_job_deletion_v3_cache_scope s
          WHERE s.business_id=NEW.business_id AND s.cache_key='financial:'||NEW.cache_key AND s.dirty=1)
        BEGIN SELECT RAISE(ABORT,'Retained financial work cannot be replaced'); END''');
      await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_scope_dirty_financial_update
        BEFORE UPDATE ON local_financial_cache
        WHEN EXISTS(SELECT 1 FROM local_job_deletion_v3_cache_scope s WHERE s.dirty=1 AND
          ((s.business_id=NEW.business_id AND s.cache_key='financial:'||NEW.cache_key) OR
           (s.business_id=OLD.business_id AND s.cache_key='financial:'||OLD.cache_key)))
        BEGIN SELECT RAISE(ABORT,'Retained financial work cannot be overwritten'); END''');
      // Unknown malformed payloads fail closed for replay, but cleanup never
      // deletes them on that basis. Shared/unknown work remains recoverable.
      for (final table in const ['sync_outbox', 'local_financial_cache']) {
        for (final action in const ['INSERT', 'UPDATE']) {
          final scopeFilter = table == 'sync_outbox' ? '' : " AND (e.operation_id<>'' OR EXISTS(SELECT 1 FROM local_job_deletion_v3_scope_entities s WHERE s.business_id=e.business_id AND s.entity_kind=e.entity_kind AND s.entity_id=e.entity_id AND s.dirty=1))";
          final identity = table == 'sync_outbox'
              ? 'e.entity_id=NEW.entity_id OR'
              : "(e.entity_kind='transaction' AND NEW.cache_key='transaction_detail_'||e.entity_id) OR";
          final operationCheck = table == 'sync_outbox' ? _outboxOperationSql : '0';
          await db.customStatement('DROP TRIGGER IF EXISTS deletion_v3_${table}_${action.toLowerCase()}');
          await db.customStatement('''CREATE TRIGGER IF NOT EXISTS deletion_v3_${table}_${action.toLowerCase()}
            BEFORE $action ON $table
            WHEN EXISTS(SELECT 1 FROM local_job_deletion_v3_fences e
              WHERE e.business_id=NEW.business_id$scopeFilter AND ($identity
                json_valid(NEW.payload_json)=0 OR ($operationCheck) OR EXISTS(
                  SELECT 1 FROM json_tree(CASE WHEN json_valid(NEW.payload_json)
                    THEN NEW.payload_json ELSE '{}' END) j
                  WHERE j.type='text' AND j.value=e.entity_id)))
            BEGIN SELECT RAISE(ABORT,'Verified deletion blocks stale payload replay'); END''');
        }
      }
      await db.customStatement('INSERT INTO local_job_deletion_v3_schema(singleton,version) VALUES (1,7) '
          'ON CONFLICT(singleton) DO UPDATE SET version=excluded.version');
    });
    _installed[db] = true;
  }

  /// This is a visibility epoch, separate from irreversible deletion markers.
  /// A current authenticated response may rehydrate clean rows only. Unknown
  /// unsynced work remains hidden until explicit authorized reconciliation.
  static Future<void> assertVisibilityActor(BriskersLocalDatabase db,
      String businessId) async {
    final provider = currentActorIdProvider;
    if (provider == null) { return; }
    await ensureSchema(db);
    final actor = provider();
    final rows = await db.customSelect(
        'SELECT actor_id,state FROM local_job_deletion_v3_scope WHERE business_id=?',
        variables: [Variable<String>(businessId)]).get();
    if (actor == null || rows.isEmpty || rows.single.read<String>('actor_id') != actor ||
        rows.single.read<String>('state') == 'scope_verification_required' || provider() != actor) {
      throw StateError('Authenticated cache scope has not been verified for this actor');
    }
  }

  static Future<void> lockKnownRoleChange(BriskersLocalDatabase db,
      String businessId) async {
    await ensureSchema(db);
    await db.customStatement("UPDATE local_job_deletion_v3_scope SET "
        "state='scope_verification_required',generation=generation+1 WHERE business_id=?", [businessId]);
    db.notifyUpdates({const TableUpdate('local_jobs'), const TableUpdate('local_documents'), const TableUpdate('local_financial_cache')});
    _events.add((businessId: businessId, jobIds: <String>{}));
  }

  static Future<int> captureVisibilityGeneration(BriskersLocalDatabase db,
      String businessId) async {
    await ensureSchema(db);
    final provider = currentActorIdProvider;
    final actor = provider?.call();
    final rows = await db.customSelect(
        'SELECT actor_id,state,generation FROM local_job_deletion_v3_scope WHERE business_id=?',
        variables: [Variable<String>(businessId)]).get();
    if (provider != null && (actor == null || rows.isEmpty ||
        rows.single.read<String>('actor_id') != actor ||
        rows.single.read<String>('state') == 'scope_verification_required' || provider() != actor)) {
      throw StateError('Authenticated cache scope changed during this request');
    }
    return rows.isEmpty ? 0 : rows.single.read<int>('generation');
  }

  static Future<void> assertVisibilityGeneration(BriskersLocalDatabase db,
      String businessId, int expected) async {
    if (await captureVisibilityGeneration(db, businessId) != expected) {
      throw StateError('Authorization changed during this request');
    }
  }

  static int? visibilityGenerationOf(Object? value, String businessId) {
    if (value is Map) {
      final stamp = value['_local_visibility_generation'];
      return stamp is int ? stamp : null;
    }
    if (value is List && value.isNotEmpty) {
      final stamps = value.map((row) => visibilityGenerationOf(row, businessId)).toSet();
      return stamps.length == 1 ? stamps.single : null;
    }
    return null;
  }

  /// Private transport metadata never enters snapshots or queued business JSON.
  static Object? stripVisibilityMetadata(Object? value) {
    if (value is Map) {
      return <String, dynamic>{for (final entry in value.entries)
        if (entry.key != '_local_visibility_generation')
          entry.key.toString(): stripVisibilityMetadata(entry.value)};
    }
    if (value is List) { return value.map(stripVisibilityMetadata).toList(); }
    return value;
  }

  static Future<bool> visibilityCacheReadable(BriskersLocalDatabase db,
      String businessId, String cacheKey) async {
    final generation = await captureVisibilityGeneration(db, businessId);
    if (generation == 0) { return true; }
    final rows = await db.customSelect(
        'SELECT generation,dirty FROM local_job_deletion_v3_cache_scope WHERE business_id=? AND cache_key=?',
        variables: [Variable<String>(businessId), Variable<String>(cacheKey)]).get();
    return rows.isNotEmpty && rows.single.read<int>('generation') == generation &&
        rows.single.read<int>('dirty') == 0;
  }

  static Future<int?> validateVisibilityCacheWrite(BriskersLocalDatabase db,
      String businessId, String cacheKey, Object? value, {int? visibilityGeneration}) async {
    final current = await captureVisibilityGeneration(db, businessId);
    final token = visibilityGeneration ?? visibilityGenerationOf(value, businessId);
    bool mismatchedStamp(Object? item) {
      if (item is Map) {
        final stamp = item['_local_visibility_generation'];
        if (stamp != null && stamp != current) { return true; }
        return item.values.any(mismatchedStamp);
      }
      return item is List && item.any(mismatchedStamp);
    }
    if ((current != 0 && token == null) || (token != null && token != current) || mismatchedStamp(value)) {
      return null;
    }
    // Even a current read must never overwrite the sole copy of older work.
    final dirty = await db.customSelect(
        'SELECT 1 FROM local_job_deletion_v3_cache_scope WHERE business_id=? AND cache_key=? AND dirty=1',
        variables: [Variable<String>(businessId), Variable<String>(cacheKey)]).get();
    return dirty.isEmpty ? current : null;
  }

  static Future<void> markVisibilityCacheWritten(BriskersLocalDatabase db,
      String businessId, String cacheKey, int generation) async {
    await assertVisibilityGeneration(db, businessId, generation);
    await db.customStatement('INSERT INTO local_job_deletion_v3_cache_scope '
        '(business_id,cache_key,generation,dirty) VALUES (?,?,?,0) '
        'ON CONFLICT(business_id,cache_key) DO UPDATE SET generation=excluded.generation',
        [businessId, cacheKey, generation]);
  }

  /// Call within the same SQLite transaction as replacing these exact rows.
  /// Deletion and pending-consent fences are never affected by authorization.
  static Future<void> authorizeScopedEntities(BriskersLocalDatabase db,
      String businessId, int expectedGeneration, List<Map<String, dynamic>> entities) async {
    await assertVisibilityGeneration(db, businessId, expectedGeneration);
    for (final entity in entities) {
      final kind = entity['entity_kind'];
      final id = entity['entity_id'];
      if (kind is! String || id is! String || id.isEmpty) {
        throw const FormatException('Exact authorization identity required');
      }
      await db.customStatement('DELETE FROM local_job_deletion_v3_scope_entities '
          'WHERE business_id=? AND entity_kind=? AND entity_id=? AND dirty=0',
          [businessId, kind, id]);
    }
  }

  static Future<String?> visibilityScopeState(BriskersLocalDatabase db,
      String businessId) async {
    await ensureSchema(db);
    final rows = await db.customSelect(
        'SELECT state FROM local_job_deletion_v3_scope WHERE business_id=?',
        variables: [Variable<String>(businessId)]).get();
    return rows.isEmpty ? null : rows.single.read<String>('state');
  }

  static Future<bool> invalidateVisibilityScope(BriskersLocalDatabase db, {
    required String businessId, required String actorId,
    required String visibilityScope, required String readerScope,
  }) async {
    await ensureSchema(db);
    if (businessId.isEmpty || actorId.isEmpty || visibilityScope.isEmpty ||
        !const {'staff', 'customer'}.contains(readerScope)) {
      throw const FormatException('Authenticated visibility scope required');
    }
    final jobs = <String>{};
    final changed = await db.transaction(() async {
      final previous = await db.customSelect(
          'SELECT * FROM local_job_deletion_v3_scope WHERE business_id=?',
          variables: [Variable<String>(businessId)]).get();
      if (previous.isNotEmpty && previous.single.read<String>('actor_id') == actorId &&
          previous.single.read<String>('visibility_scope') == visibilityScope &&
          previous.single.read<String>('reader_scope') == readerScope &&
          previous.single.read<String>('state') != 'scope_verification_required') { return false; }
      // Legacy cache provenance is unknown even for the first staff scope.
      const invalidate = true;
      final generation = previous.isEmpty ? 1 :
          previous.single.read<int>('generation') + 1;
      var dirtyFound = false;
      if (invalidate) {
        final pendingRows = await db.customSelect('SELECT * FROM sync_outbox WHERE business_id=?',
            variables: [Variable<String>(businessId)]).get();
        final dirtyIds = <String>{};
        var unknownOutbox = false;
        void gather(Object? value) {
          if (value is Map) {
            for (final entry in value.entries) {
              if (entry.value is String && (entry.key == 'id' || entry.key.toString().endsWith('_id'))) {
                dirtyIds.add(entry.value as String);
              }
              gather(entry.value);
            }
          } else if (value is List) { for (final item in value) { gather(item); } }
        }
        for (final row in pendingRows) {
          dirtyIds.add(row.read<String>('entity_id'));
          final payload = _decode(row.data['payload_json']);
          unknownOutbox = unknownOutbox || payload is! Map;
          gather(payload);
        }
        Future<void> fence(String kind, String id, bool dirty) async {
          if (id.isEmpty) { return; }
          dirty = dirty || unknownOutbox || dirtyIds.contains(id);
          dirtyFound = dirtyFound || dirty;
          if (kind == 'job') { jobs.add(id); }
          await db.customStatement('INSERT INTO local_job_deletion_v3_scope_entities '
              '(business_id,entity_kind,entity_id,generation,dirty) VALUES (?,?,?,?,?) '
              'ON CONFLICT(business_id,entity_kind,entity_id) DO UPDATE SET '
              'generation=excluded.generation,dirty=MAX(dirty,excluded.dirty)',
              [businessId, kind, id, generation, dirty ? 1 : 0]);
        }
        for (final entry in _tables.entries) {
          final (table, key, predicate) = entry.value;
          final rows = await db.customSelect('SELECT * FROM $table WHERE business_id=?$predicate',
              variables: [Variable<String>(businessId)]).get();
          for (final row in rows) {
            await fence(entry.key, row.read<String>(key), _hasUnconfirmedContent(row.data));
          }
        }
        for (final table in const ['local_pre_inspection_photos', 'local_finding_photos']) {
          final rows = await db.customSelect('SELECT * FROM $table WHERE business_id=?',
              variables: [Variable<String>(businessId)]).get();
          for (final row in rows) {
            await fence('attachment', row.read<String>('attachment_id'), _hasUnconfirmedContent(row.data));
            if (table == 'local_finding_photos') {
              await fence('finding_photo', row.read<String>('id'), _hasUnconfirmedContent(row.data));
            }
          }
        }
        final outbox = await db.customSelect('SELECT * FROM sync_outbox WHERE business_id=?',
            variables: [Variable<String>(businessId)]).get();
        for (final row in outbox) {
          dirtyFound = true;
          await db.customStatement('INSERT OR IGNORE INTO local_job_deletion_v3_scope_outbox '
              '(business_id,outbox_id) VALUES (?,?)', [businessId, row.read<int>('id')]);
          // A pending edit also protects its existing synced projection from
          // automatic overwrite. Exact scalar IDs only; no ownership inference.
          final payload = _decode(row.data['payload_json']);
          final candidates = await db.customSelect(
              'SELECT entity_kind,entity_id FROM local_job_deletion_v3_scope_entities WHERE business_id=?',
              variables: [Variable<String>(businessId)]).get();
          for (final candidate in candidates) {
            final id = candidate.read<String>('entity_id');
            if (id == row.data['entity_id'] || referencesAny(payload, {id}) || payload == null) {
              await fence(candidate.read<String>('entity_kind'), id, true);
            }
          }
        }
        Future<void> cache(String key, Object? value) async {
          final structurallyValid = key.startsWith('briskers_document_detail_')
              ? value is Map : value is Map || value is List;
          final dirty = !structurallyValid || unknownOutbox || referencesAny(value, dirtyIds) || _hasUnconfirmedContent(value);
          dirtyFound = dirtyFound || dirty;
          await db.customStatement('INSERT INTO local_job_deletion_v3_cache_scope '
              '(business_id,cache_key,generation,dirty) VALUES (?,?,?,?) '
              'ON CONFLICT(business_id,cache_key) DO UPDATE SET dirty=MAX(dirty,excluded.dirty)',
              [businessId, key, generation - 1, dirty ? 1 : 0]);
        }
        final financial = await db.customSelect('SELECT cache_key,payload_json FROM local_financial_cache WHERE business_id=?',
            variables: [Variable<String>(businessId)]).get();
        for (final row in financial) {
          final value = _decode(row.data['payload_json']);
          await cache('financial:${row.read<String>('cache_key')}', value);
          final key = row.read<String>('cache_key');
          if (key.startsWith('transaction_detail_')) {
            await fence('transaction', key.substring('transaction_detail_'.length), value == null || _hasUnconfirmedContent(value));
          }
          if (value is List) {
            for (final item in value.whereType<Map>()) {
              if (item['id'] is String) { await fence('transaction', item['id'] as String, _hasUnconfirmedContent(item)); }
            }
          }
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final prefix = 'briskers_document_detail_${businessId}_';
        for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
          final value = _decode(prefs.getString(key));
          await cache(key, value);
          final kind = value is Map && const {'invoice', 'estimate'}.contains(value['kind'])
              ? value['kind'] as String : null;
          final ids = <String>{key.substring(prefix.length),
            if (value is Map && value['id'] is String) value['id'] as String,
            if (value is Map && value['_server_document_id'] is String) value['_server_document_id'] as String};
          for (final id in ids) {
            for (final k in kind == null ? const ['invoice', 'estimate'] : [kind]) {
              await fence(k, id, value is! Map || _hasUnconfirmedContent(value));
            }
          }
        }
      }
      await db.customStatement('INSERT INTO local_job_deletion_v3_scope '
          '(business_id,actor_id,visibility_scope,reader_scope,generation,state) VALUES (?,?,?,?,?,?) '
          'ON CONFLICT(business_id) DO UPDATE SET actor_id=excluded.actor_id,'
          'visibility_scope=excluded.visibility_scope,reader_scope=excluded.reader_scope,'
          'generation=excluded.generation,state=excluded.state',
          [businessId, actorId, visibilityScope, readerScope, generation,
           dirtyFound ? 'authorized_reconciliation_required' : 'refresh_required']);
      return invalidate;
    });
    if (changed) {
      db.notifyUpdates({const TableUpdate('local_jobs'), const TableUpdate('local_documents'), const TableUpdate('local_financial_cache')});
      _events.add((businessId: businessId, jobIds: jobs));
    }
    return changed;
  }

  static Future<void> setPendingIntent(BriskersLocalDatabase db, {
    required String businessId, required String jobId, required String operationId,
    required List<Map<String, dynamic>> deletedEntities,
  }) async {
    await ensureSchema(db);
    for (final entity in deletedEntities) {
      if (!entityKinds.contains(entity['entity_kind']) || entity['entity_id'] is! String ||
          (entity['entity_id'] as String).isEmpty) {
        throw const FormatException('Unknown pending deletion identity');
      }
    }
    await db.transaction(() async {
      await db.customStatement('DELETE FROM local_job_deletion_v3_pending WHERE business_id=? AND operation_id=?',
          [businessId, operationId]);
      for (final entity in deletedEntities) {
        await db.customStatement('INSERT OR IGNORE INTO local_job_deletion_v3_pending '
            '(business_id,job_id,operation_id,entity_kind,entity_id) VALUES (?,?,?,?,?)',
            [businessId, jobId, operationId, entity['entity_kind'], entity['entity_id']]);
      }
    });
    _notify(db, businessId, jobId);
  }

  static Future<void> releasePendingIntent(BriskersLocalDatabase db,
      String businessId, String operationId) async {
    await ensureSchema(db);
    final jobs = await db.customSelect('SELECT DISTINCT job_id FROM local_job_deletion_v3_pending '
        'WHERE business_id=? AND operation_id=?',
        variables: [Variable<String>(businessId), Variable<String>(operationId)]).get();
    await db.customStatement('DELETE FROM local_job_deletion_v3_pending WHERE business_id=? AND operation_id=?',
        [businessId, operationId]);
    for (final job in jobs) { _notify(db, businessId, job.read<String>('job_id')); }
  }

  static Future<Set<String>> scopeDirtyIds(BriskersLocalDatabase db,
      String businessId) async {
    await ensureSchema(db);
    return (await db.customSelect(
        'SELECT entity_id FROM local_job_deletion_v3_scope_entities WHERE business_id=? AND dirty=1',
        variables: [Variable<String>(businessId)]).get())
        .map((row) => row.read<String>('entity_id')).toSet();
  }

  static Future<Set<String>> blockedIds(BriskersLocalDatabase db,
      String businessId, {String? kind, bool includeVisibilityScope = true}) async {
    await ensureSchema(db);
    final source = includeVisibilityScope ? 'local_job_deletion_v3_fences' :
        '(SELECT * FROM local_job_deletion_v3_entities UNION ALL SELECT * FROM local_job_deletion_v3_pending UNION ALL SELECT * FROM local_job_deletion_v3_aliases UNION ALL SELECT * FROM local_offline_job_purge_entities)';
    return (await db.customSelect('SELECT entity_id FROM $source '
        'WHERE business_id=?${kind == null ? '' : ' AND entity_kind=?'}',
        variables: [Variable<String>(businessId), if (kind != null) Variable<String>(kind)])
        .get()).map((r) => r.read<String>('entity_id')).toSet();
  }

  static Future<bool> _tableExists(BriskersLocalDatabase db, String name) async =>
      (await db.customSelect("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
          variables: [Variable<String>(name)]).get()).isNotEmpty;

  static Future<Set<String>> deletedIds(BriskersLocalDatabase db,
      String businessId, {String? kind}) async {
    await ensureSchema(db);
    return (await db.customSelect('SELECT entity_id FROM local_job_deletion_v3_entities '
        'WHERE business_id=?${kind == null ? '' : ' AND entity_kind=?'}',
        variables: [Variable<String>(businessId), if (kind != null) Variable<String>(kind)])
        .get()).map((r) => r.read<String>('entity_id')).toSet();
  }

  static Future<bool> isEntityDeleted(BriskersLocalDatabase db,
      String businessId, String entityKind, String entityId) async =>
      (await deletedIds(db, businessId, kind: entityKind)).contains(entityId);
  static Future<Set<String>> blockedJobIds(BriskersLocalDatabase db, String businessId,
      {bool includeVisibilityScope = true}) =>
      blockedIds(db, businessId, kind: 'job', includeVisibilityScope: includeVisibilityScope);
  static Future<Set<String>> blockedDocumentIds(BriskersLocalDatabase db, String businessId,
      {bool includeVisibilityScope = true}) async =>
      {...await blockedIds(db, businessId, kind: 'invoice', includeVisibilityScope: includeVisibilityScope),
       ...await blockedIds(db, businessId, kind: 'estimate', includeVisibilityScope: includeVisibilityScope)};

  static Future<Set<String>> blockedIdsForTable(BriskersLocalDatabase db,
      String businessId, String? table) async {
    if (table == null) { return blockedIds(db, businessId); }
    final ids = <String>{};
    for (final entry in _tables.entries.where((entry) => entry.value.$1 == table)) {
      ids.addAll(await blockedIds(db, businessId, kind: entry.key));
    }
    if (table == 'local_finding_photos') {
      ids.addAll(await blockedIds(db, businessId, kind: 'finding_photo'));
    }
    if (const ['local_pre_inspection_photos', 'local_finding_photos'].contains(table)) {
      final attachments = await blockedIds(db, businessId, kind: 'attachment');
      for (final id in attachments) {
        final rows = await db.customSelect('SELECT id FROM $table WHERE business_id=? AND attachment_id=?',
            variables: [Variable<String>(businessId), Variable<String>(id)]).get();
        ids.addAll(rows.map((row) => row.read<String>('id')));
      }
    }
    return ids;
  }

  static bool referencesAny(Object? value, Set<String> ids) {
    if (value is String) { return ids.contains(value); }
    if (value is List) { return value.any((v) => referencesAny(v, ids)); }
    if (value is Map) { return value.values.any((v) => referencesAny(v, ids)); }
    return false;
  }

  /// Cache rows are replaceable projections. Do not persist late snapshots
  /// containing a deleted identity, even when nested in a payment/attachment.
  static Future<bool> payloadIsDeleted(BriskersLocalDatabase db,
      String businessId, Object? payload, {bool includeVisibilityScope = true}) async =>
      referencesAny(payload, await blockedIds(db, businessId, includeVisibilityScope: includeVisibilityScope));

  static Future<void> assertReplayAllowed(BriskersLocalDatabase db,
      String businessId, {int? outboxId, Object? response}) async {
    await ensureSchema(db);
    if (outboxId != null && (await db.customSelect(
        'SELECT 1 FROM local_job_deletion_v3_scope_outbox WHERE business_id=? AND outbox_id=?',
        variables: [Variable<String>(businessId), Variable<int>(outboxId)]).get()).isNotEmpty) {
      throw StateError('Authorization changed; retained work requires reconciliation');
    }
    final ids = await blockedIds(db, businessId);
    final operations = await blockedIds(db, businessId, kind: 'operation');
    if (ids.isEmpty) { return; }
    if (referencesAny(response, ids)) {
      throw StateError('A deleted identity cannot be restored from an acknowledgement');
    }
    if (outboxId == null) { return; }
    final rows = await db.customSelect('SELECT * FROM sync_outbox '
        'WHERE business_id=? AND id=?',
        variables: [Variable<String>(businessId), Variable<int>(outboxId)]).get();
    if (rows.isEmpty) { throw StateError('Deleted or completed outbox operation is no longer replayable'); }
    final row = rows.single;
    final payload = _decode(row.read<String>('payload_json'));
    if (payload is! Map || ids.contains(row.read<String>('entity_id')) || referencesAny(payload, ids) ||
        _approvedOperation(row.data, {'operation': operations})) {
      throw StateError('A deleted identity cannot be replayed');
    }
  }

  static List<Map<String, String>> _validateReceipt(Map<String, dynamic> receipt, {bool requireJob = true}) {
    if (receipt['schema_version'] != 3 || receipt['protocol_version'] != protocol ||
        !const {'deleted', 'purging'}.contains(receipt['status']) ||
        !const {'not_required', 'pending', 'failed', 'completed'}.contains(receipt['storage_cleanup']) ||
        receipt['status_version'] is! int || (receipt['status_version'] as int) < 1) {
      throw const FormatException('A committed v3 receipt is required');
    }
    for (final key in const ['business_id', 'job_id', 'operation_id', 'graph_hash']) {
      if (receipt[key] is! String || (receipt[key] as String).isEmpty) {
        throw FormatException('Missing receipt $key');
      }
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(receipt['graph_hash'] as String)) {
      throw const FormatException('Invalid receipt graph hash');
    }
    if ((receipt['status'] == 'deleted') !=
        const {'not_required', 'completed'}.contains(receipt['storage_cleanup'])) {
      throw const FormatException('Inconsistent deletion cleanup status');
    }
    final raw = receipt['deleted_entities'];
    if (raw is! List || raw.isEmpty) { throw const FormatException('Missing deletion inventory'); }
    final seen = <String>{};
    final result = <Map<String, String>>[];
    for (final item in raw) {
      if (item is! Map || item['entity_kind'] is! String || item['entity_id'] is! String ||
          !entityKinds.contains(item['entity_kind']) || (item['entity_id'] as String).isEmpty) {
        throw const FormatException('Unknown deletion identity');
      }
      final kind = item['entity_kind'] as String;
      final id = item['entity_id'] as String;
      const composite = {'finding_attachment_link', 'sales_estimate_link',
        'sales_receipt_link', 'receipt_detail', 'document_restore'};
      final uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      if (kind == 'operation') {
        if (!RegExp(r'^[a-z_]+/.+$').hasMatch(id)) { throw const FormatException('Operation namespace is required'); }
      } else if (kind == 'legacy_photo_map' || kind == 'legacy_stage') {
        final key = _decode(id);
        final expected = kind == 'legacy_photo_map'
            ? const {'business_id', 'source_record_key'}
            : const {'business_id', 'batch_tag', 'source_system', 'record_type', 'source_key'};
        if (key is! Map || key.length != expected.length || !expected.every(key.containsKey) ||
            key['business_id'] != receipt['business_id'] ||
            key.values.any((value) => value is! String || value.isEmpty || value.length > 2048)) {
          throw const FormatException('Invalid legacy deletion identity');
        }
      } else if (composite.contains(kind)) {
        final key = _decode(id);
        if (key is! Map || key.isEmpty || key.values.any((value) => value is! String || !uuid.hasMatch(value))) {
          throw const FormatException('Invalid composite deletion identity');
        }
      } else if (!uuid.hasMatch(id)) {
        throw const FormatException('Deletion identity must be an immutable UUID');
      }
      if (!seen.add('$kind\u0000$id')) { throw const FormatException('Duplicate deletion identity'); }
      result.add({'entity_kind': kind, 'entity_id': id});
    }
    if (requireJob && !result.any((e) => e['entity_kind'] == 'job' && e['entity_id'] == receipt['job_id'])) {
      throw const FormatException('Receipt does not contain the selected job');
    }
    return result;
  }

  static Future<LocalDeletionCleanupResult> applyVerifiedReceipt(
    BriskersLocalDatabase db, {required Map<String, dynamic> receipt,
    Future<Directory> Function()? mediaDirectoryProvider,
  }) async {
    final entities = _validateReceipt(receipt);
    return _acceptVerified(db, receipt, entities, strict: true,
        mediaDirectoryProvider: mediaDirectoryProvider);
  }

  /// Only the authenticated feed reader may call this after validating the
  /// actor, visibility scope, cursor and scope_complete operation boundary.
  static Future<LocalDeletionCleanupResult> applyVerifiedTombstone(
    BriskersLocalDatabase db, Map<String, dynamic> entry,
    {Future<Directory> Function()? mediaDirectoryProvider}
  ) async {
    if (entry['scope_complete'] != true) {
      throw const FormatException('Incomplete deletion tombstone group');
    }
    final normalized = <String, dynamic>{...entry, 'schema_version': 3,
      'protocol_version': protocol, 'graph_hash': List.filled(64, '0').join()};
    final entities = _validateReceipt(normalized, requireJob: false);
    return _acceptVerified(db, {...normalized, 'graph_hash': ''}, entities, strict: false,
        mediaDirectoryProvider: mediaDirectoryProvider);
  }

  /// The caller authenticates the separate local-origin envelope and matches
  /// its scope to the complete accepted tombstone group before invoking this.
  /// Only explicit server-projected aliases are accepted; graph shape is never
  /// used to invent conversion or financial identities.
  static Future<LocalDeletionCleanupResult> applyVerifiedLocalOrigin(
      BriskersLocalDatabase db, {required String businessId,
      required Map<String, dynamic> origin,
      Future<Directory> Function()? mediaDirectoryProvider}) async {
    await ensureSchema(db);
    final visibilityGeneration = await captureVisibilityGeneration(db, businessId);
    final operation = origin['operation_id'];
    final job = origin['job_id'];
    final root = origin['root_origin'];
    final rawAliases = origin['local_aliases'];
    if (operation is! String || job is! String || rawAliases is! List ||
        !const {null, 'job_create', 'quick_invoice', 'standalone_estimate_conversion'}.contains(root)) {
      throw const FormatException('Unverified local cancellation origin');
    }
    return _serialized(db, '$businessId:$operation', () async {
      await db.transaction(() async {
        await assertVisibilityGeneration(db, businessId, visibilityGeneration);
        final accepted = await db.customSelect(
            'SELECT job_id FROM local_job_deletion_v3_cleanup WHERE business_id=? AND operation_id=?',
            variables: [Variable<String>(businessId), Variable<String>(operation)]).get();
        if (accepted.isEmpty || accepted.single.read<String>('job_id') != job) {
          throw StateError('Local origin requires its accepted operation and root');
        }
        if (root == null && rawAliases.isNotEmpty) {
          throw const FormatException('Remote deletion cannot assert local origin aliases');
        }
        final inventory = await _inventory(db, businessId, operation);
        final seen = <String>{};
        final aliases = <Map<String, String>>[];
        for (final raw in rawAliases) {
          if (raw is! Map || raw.length != 2 || raw['entity_kind'] is! String || raw['entity_id'] is! String) {
            throw const FormatException('Exact local cancellation alias required');
          }
          final kind = raw['entity_kind'] as String;
          final id = raw['entity_id'] as String;
          final valid = (kind == 'job' &&
              id == (root == 'standalone_estimate_conversion' ? 'local-conversion-job-$job' : 'local-job-$job') &&
              _has(inventory, 'job', job)) ||
              (kind == 'invoice' && const {'quick_invoice', 'standalone_estimate_conversion'}.contains(root) &&
               id == 'local-invoice-$job') ||
              (kind == 'estimate' && root == 'standalone_estimate_conversion' && id.startsWith('local-estimate-') &&
               _has(inventory, 'estimate', id.substring('local-estimate-'.length)));
          if (root == null || !valid || !seen.add('$kind:$id')) {
            throw const FormatException('Local alias is not bound to this visible cancellation inventory');
          }
          aliases.add({'entity_kind': kind, 'entity_id': id});
        }
        final previous = await db.customSelect(
            'SELECT job_id,root_origin FROM local_job_deletion_v3_origins WHERE business_id=? AND operation_id=?',
            variables: [Variable<String>(businessId), Variable<String>(operation)]).get();
        if (previous.isNotEmpty && (previous.single.read<String>('job_id') != job ||
            previous.single.read<String>('root_origin') != (root ?? 'remote'))) {
          throw StateError('Accepted local origin cannot change');
        }
        await db.customStatement('INSERT OR IGNORE INTO local_job_deletion_v3_origins '
            '(business_id,operation_id,job_id,root_origin) VALUES (?,?,?,?)',
            [businessId, operation, job, root ?? 'remote']);
        var expanded = false;
        for (final alias in aliases) {
          final exists = await db.customSelect('SELECT 1 FROM local_job_deletion_v3_aliases '
              'WHERE business_id=? AND entity_kind=? AND entity_id=?',
              variables: [Variable<String>(businessId), Variable<String>(alias['entity_kind']!), Variable<String>(alias['entity_id']!)]).get();
          await db.customStatement('INSERT OR IGNORE INTO local_job_deletion_v3_aliases '
              '(business_id,job_id,operation_id,entity_kind,entity_id) VALUES (?,?,?,?,?)',
              [businessId, job, operation, alias['entity_kind'], alias['entity_id']]);
          expanded = expanded || exists.isEmpty;
        }
        await assertVisibilityGeneration(db, businessId, visibilityGeneration);
        if (expanded) {
          await db.customStatement("UPDATE local_job_deletion_v3_cleanup SET state='cleanup_pending',issue_code=NULL,"
              'inventory_generation=inventory_generation+1 WHERE business_id=? AND operation_id=?', [businessId, operation]);
        }
      });
      return _cleanup(db, businessId, job, operation, mediaDirectoryProvider: mediaDirectoryProvider);
    });
  }

  static final _serialWork = Expando<Map<String, Future<void>>>('deletion_v3_work');
  static Future<T> _serialized<T>(BriskersLocalDatabase db, String key, Future<T> Function() action) async {
    final pending = _serialWork[db] ??= {};
    final previous = pending[key];
    final done = Completer<void>();
    pending[key] = done.future;
    if (previous != null) { await previous; }
    try { return await action(); } finally {
      done.complete();
      if (identical(pending[key], done.future)) { pending.remove(key); }
    }
  }

  static Future<LocalDeletionCleanupResult> _acceptVerified(
    BriskersLocalDatabase db, Map<String, dynamic> receipt,
    List<Map<String, String>> entities, {required bool strict,
    Future<Directory> Function()? mediaDirectoryProvider}
  ) => _serialized(db, '${receipt['business_id']}:${receipt['operation_id']}',
      () => _acceptVerifiedUnlocked(db, receipt, entities, strict: strict,
        mediaDirectoryProvider: mediaDirectoryProvider));

  static Future<LocalDeletionCleanupResult> _acceptVerifiedUnlocked(
    BriskersLocalDatabase db, Map<String, dynamic> receipt,
    List<Map<String, String>> entities, {required bool strict,
    Future<Directory> Function()? mediaDirectoryProvider}
  ) async {
    final business = receipt['business_id'] as String;
    final job = receipt['job_id'] as String;
    final operation = receipt['operation_id'] as String;
    final hash = receipt['graph_hash'] as String;
    await ensureSchema(db);
    // Commit the permanent fences before best-effort erasure. A crash or failed
    // plugin call must not roll back the knowledge of server-side deletion.
    await db.transaction(() async {
      final existing = await db.customSelect('SELECT job_id,graph_hash FROM local_job_deletion_v3_cleanup '
          'WHERE business_id=? AND operation_id=?',
          variables: [Variable<String>(business), Variable<String>(operation)]).get();
      if (existing.isNotEmpty && (existing.first.read<String>('job_id') != job ||
          (strict && existing.first.read<String>('graph_hash').isNotEmpty &&
           existing.first.read<String>('graph_hash') != hash))) {
        throw StateError('Deletion operation receipt mismatch');
      }
      if (strict && existing.isNotEmpty && existing.first.read<String>('graph_hash').isNotEmpty) {
        final prior = await _inventory(db, business, operation);
        final oldKeys = {for (final kind in prior.keys)
          for (final id in prior[kind]!) '$kind\u0000$id'};
        final newKeys = {for (final e in entities) '${e['entity_kind']}\u0000${e['entity_id']}'};
        if (oldKeys.length != newKeys.length || !oldKeys.containsAll(newKeys)) {
          throw StateError('Deletion inventory receipt mismatch');
        }
      }
      for (final entity in entities) {
        final previous = await db.customSelect('SELECT job_id,operation_id FROM local_job_deletion_v3_entities '
            'WHERE business_id=? AND entity_kind=? AND entity_id=?', variables: [
              Variable<String>(business), Variable<String>(entity['entity_kind']!),
              Variable<String>(entity['entity_id']!)]).get();
        if (previous.isNotEmpty && (previous.first.read<String>('job_id') != job ||
            previous.first.read<String>('operation_id') != operation)) {
          throw StateError('Deletion identity belongs to another receipt');
        }
        await db.customStatement('INSERT OR IGNORE INTO local_job_deletion_v3_entities '
            '(business_id,job_id,operation_id,entity_kind,entity_id) VALUES (?,?,?,?,?)',
            [business, job, operation, entity['entity_kind'], entity['entity_id']]);
      }
      await _recordKnownAliases(db, business, job, operation, await _inventory(db, business, operation));
      await db.customStatement('INSERT OR IGNORE INTO local_job_deletion_v3_cleanup '
          '(business_id,job_id,operation_id,graph_hash,state) VALUES (?,?,?,?,?)',
          [business, job, operation, hash, 'cleanup_pending']);
      await db.customStatement("UPDATE local_job_deletion_v3_cleanup SET state='cleanup_pending',issue_code=NULL,inventory_generation=inventory_generation+1 WHERE business_id=? AND operation_id=?", [business, operation]);
      if (strict) {
        await db.customStatement('UPDATE local_job_deletion_v3_cleanup SET graph_hash=? '
            'WHERE business_id=? AND operation_id=? AND graph_hash=?',
            [hash, business, operation, '']);
      }
    });
    await releasePendingIntent(db, business, operation);
    _notify(db, business, job);
    return _cleanup(db, business, job, operation,
        mediaDirectoryProvider: mediaDirectoryProvider);
  }

  static Future<void> resumePendingCleanup(BriskersLocalDatabase db, String businessId,
      {Future<Directory> Function()? mediaDirectoryProvider}) async {
    await ensureSchema(db);
    final rows = await db.customSelect('SELECT job_id,operation_id FROM local_job_deletion_v3_cleanup '
        "WHERE business_id=? AND state<>'complete'",
        variables: [Variable<String>(businessId)]).get();
    for (final row in rows) {
      final operation = row.read<String>('operation_id');
      await _serialized(db, '$businessId:$operation', () => _cleanup(db, businessId,
          row.read<String>('job_id'), operation, mediaDirectoryProvider: mediaDirectoryProvider));
    }
  }

  static Future<Map<String, Set<String>>> _inventory(BriskersLocalDatabase db,
      String business, String operation) async {
    final result = <String, Set<String>>{};
    final rows = await db.customSelect('SELECT entity_kind,entity_id FROM local_job_deletion_v3_entities '
        'WHERE business_id=? AND operation_id=?',
        variables: [Variable<String>(business), Variable<String>(operation)]).get();
    for (final row in rows) {
      (result[row.read<String>('entity_kind')] ??= {}).add(row.read<String>('entity_id'));
    }
    return result;
  }

  static Set<String> _referenceIds(Map<String, Set<String>> inventory) => {
    ...inventory.values.expand((values) => values),
  };

  static bool _has(Map<String, Set<String>> inventory, String kind, Object? id) =>
      id is String && (inventory[kind]?.contains(id) ?? false);

  static const _outboxTargets = <String, Set<String>>{
    'job_admin': {'job'}, 'job_create': {'job'}, 'preinspection': {'job'},
    'work_summary': {'job'}, 'document_edit': {'invoice', 'estimate'},
    'document_draft_create': {'invoice', 'estimate'},
    'finding_create': {'finding'}, 'customer_finding_create': {'finding'},
    'finding_update': {'finding'}, 'finding_photo': {'finding_photo', 'attachment'},
    'preinspection_photo': {'pre_inspection_photo', 'attachment'},
    'financial_create': {'transaction'}, 'financial_update': {'transaction'},
    'financial_photo': {'attachment'},
  };

  static bool _approvedOperation(Map<String, dynamic> row, Map<String, Set<String>> inventory) {
    final payload = _decode(row['payload_json']);
    if (payload is! Map || payload['operation_id'] is! String) { return false; }
    final type = row['entity_type'];
    String? namespace;
    if (type == 'invoice_payment_received') { namespace = 'invoice_payment'; }
    if (const {'preinspection', 'preinspection_photo', 'finding_create',
        'finding_update', 'finding_photo', 'financial_create', 'financial_photo'}
        .contains(type)) { namespace = 'sync'; }
    if (type == 'document_draft_create' && row['operation'] == 'create_quick_invoice') { namespace = 'quick_invoice'; }
    if (type == 'document_draft_create' && row['operation'] == 'create_estimate' &&
        (payload['job_id'] == null || payload['job_id'] == '')) { namespace = 'standalone_estimate'; }
    return namespace != null && _has(inventory, 'operation', '$namespace/${payload['operation_id']}');
  }

  static bool _ownedOutbox(Map<String, dynamic> row, Map<String, Set<String>> inventory) {
    if (_approvedOperation(row, inventory)) { return true; }
    final type = row['entity_type']?.toString() ?? '';
    final payload = _decode(row['payload_json']);
    if (type == 'invoice_payment_received' && payload is Map &&
        _has(inventory, 'payment', payload['server_payment_id'])) { return true; }
    // Pending payloads may contain work newer than the confirmed graph. Exact
    // target IDs alone do not prove that those edits were included in consent.
    if (!const {'synced', 'done', 'completed'}.contains(row['state'])) { return false; }
    return (_outboxTargets[type] ?? const <String>{})
        .any((kind) => _has(inventory, kind, row['entity_id']));
  }

  static Future<void> _recordKnownAliases(BriskersLocalDatabase db, String business,
      String job, String operation, Map<String, Set<String>> inventory) async {
    Future<void> record(String kind, Object? id) async {
      if (id is! String || !id.startsWith('local-')) { return; }
      await db.customStatement('INSERT OR IGNORE INTO local_job_deletion_v3_aliases '
          '(business_id,job_id,operation_id,entity_kind,entity_id) VALUES (?,?,?,?,?)',
          [business, job, operation, kind, id]);
    }
    final rows = await db.customSelect('SELECT * FROM sync_outbox WHERE business_id=?',
        variables: [Variable<String>(business)]).get();
    for (final row in rows) {
      if (!_approvedOperation(row.data, inventory)) { continue; }
      final payload = _decode(row.data['payload_json']);
      if (payload is! Map) { continue; }
      final type = row.data['entity_type'];
      if (type == 'document_draft_create' && const {'invoice', 'estimate'}.contains(payload['kind'])) {
        await record(payload['kind'] as String, row.data['entity_id']);
        await record('job', payload['provisional_job_id']);
      } else if (type == 'financial_create') {
        await record('transaction', payload['local_transaction_id']);
      } else if (type == 'finding_create') {
        await record('finding', row.data['entity_id']);
      } else if (type == 'preinspection_photo' || type == 'finding_photo' || type == 'financial_photo') {
        await record('attachment', row.data['entity_id']);
      }
    }

  }

  static bool _hasUnconfirmedContent(Object? value) {
    if (value is Map) {
      if (const {'pending', 'conflict', 'inflight', 'failed', 'uploading', 'queued'}
          .contains(value['sync_state']) ||
          const {'pending', 'conflict', 'inflight', 'failed', 'uploading', 'queued'}
          .contains(value['upload_state']) || value['_local_pending'] == true ||
          value['_local_pending_payment'] == true || value['_payment_reconciliation_required'] == true) { return true; }
      return value.values.any(_hasUnconfirmedContent);
    }
    return value is List && value.any(_hasUnconfirmedContent);
  }

  static Future<void> assertNoUnconfirmedLocalChanges(BriskersLocalDatabase db,
      String businessId, List<Map<String, dynamic>> deletedEntities) async {
    await ensureSchema(db);
    final inventory = <String, Set<String>>{};
    for (final entity in deletedEntities) {
      if (!entityKinds.contains(entity['entity_kind']) || entity['entity_id'] is! String) {
        throw const FormatException('Unknown deletion identity');
      }
      (inventory[entity['entity_kind'] as String] ??= {}).add(entity['entity_id'] as String);
    }
    final ids = _referenceIds(inventory);
    for (final entry in _tables.entries) {
      final (table, key, predicate) = entry.value;
      for (final id in inventory[entry.key] ?? const <String>{}) {
        final rows = await db.customSelect('SELECT * FROM $table WHERE business_id=? AND $key=?$predicate',
            variables: [Variable<String>(businessId), Variable<String>(id)]).get();
        if (rows.any((row) => _hasUnconfirmedContent(row.data))) {
          throw StateError('Selected records have unconfirmed local changes. Synchronize or review them before deletion.');
        }
      }
    }
    for (final table in {..._tables.values.map((entry) => entry.$1), 'local_finding_photos'}) {
      final local = await db.customSelect('SELECT * FROM $table WHERE business_id=?',
          variables: [Variable<String>(businessId)]).get();
      if (local.any((row) => referencesAny(row.data, ids) && _hasUnconfirmedContent(row.data))) {
        throw StateError('Related records have unconfirmed local work that is absent from the server preview.');
      }
    }
    final rows = await db.customSelect('SELECT * FROM sync_outbox WHERE business_id=?',
        variables: [Variable<String>(businessId)]).get();
    for (final row in rows) {
      final payload = _decode(row.data['payload_json']);
      if (payload is! Map || ((ids.contains(row.data['entity_id']) || referencesAny(payload, ids)) &&
          !_approvedOperation(row.data, inventory))) {
        throw StateError('Unconfirmed or unreadable local work needs review before deletion.');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final prefix = 'briskers_document_detail_${businessId}_';
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      final value = _decode(prefs.getString(key));
      if ((ids.contains(key.substring(prefix.length)) || referencesAny(value, ids)) &&
          _hasUnconfirmedContent(value)) {
        throw StateError('Selected document has unconfirmed local changes.');
      }
    }
    final caches = await db.customSelect('SELECT payload_json FROM local_financial_cache WHERE business_id=?',
        variables: [Variable<String>(businessId)]).get();
    for (final row in caches) {
      final value = _decode(row.read<String>('payload_json'));
      if (referencesAny(value, ids) && _hasUnconfirmedContent(value)) {
        throw StateError('Selected financial records have unconfirmed local changes.');
      }
    }
  }

  static Object? _decode(Object? raw) {
    try { return raw is String ? jsonDecode(raw) : null; } catch (_) { return null; }
  }

  static Iterable<String> _mediaPaths(Object? value) sync* {
    if (value is Map) {
      final path = value['local_file_path'];
      if (path is String && path.isNotEmpty) { yield path; }
      for (final item in value.values) { yield* _mediaPaths(item); }
    } else if (value is List) {
      for (final item in value) { yield* _mediaPaths(item); }
    }
  }

  static Future<void> _queueMedia(BriskersLocalDatabase db, String business,
      String operation, Object? value) async {
    for (final path in _mediaPaths(value).toSet()) {
      await db.customStatement('INSERT OR IGNORE INTO local_job_deletion_v3_media '
          '(business_id,operation_id,local_path) VALUES (?,?,?)', [business, operation, path]);
    }
  }

  static Future<bool> _purgeRows(BriskersLocalDatabase db, String business,
      String job, String operation, Map<String, Set<String>> inventory) async {
    var unresolved = false;
    final dirtyScopeIds = await scopeDirtyIds(db, business);
    final dirtyCacheRows = await db.customSelect(
        'SELECT cache_key FROM local_job_deletion_v3_cache_scope WHERE business_id=? AND dirty=1',
        variables: [Variable<String>(business)]).get();
    final dirtyCacheKeys = dirtyCacheRows.map((row) => row.read<String>('cache_key')).toSet();
    final allIds = _referenceIds(inventory);
    final aliasRows = await db.customSelect('SELECT entity_id FROM local_job_deletion_v3_aliases WHERE business_id=? AND operation_id=?',
        variables: [Variable<String>(business), Variable<String>(operation)]).get();
    final aliasIds = aliasRows.map((row) => row.read<String>('entity_id')).toSet();
    for (final entry in _tables.entries) {
      final (table, key, predicate) = entry.value;
      for (final id in inventory[entry.key] ?? const <String>{}) {
        final rows = await db.customSelect('SELECT * FROM $table WHERE business_id=? AND $key=?$predicate',
            variables: [Variable<String>(business), Variable<String>(id)]).get();
        if (dirtyScopeIds.contains(id) || rows.any((row) => _hasUnconfirmedContent(row.data))) { unresolved = true; continue; }
        for (final row in rows) { await _queueMedia(db, business, operation, row.data); }
        await db.customStatement('DELETE FROM $table WHERE business_id=? AND $key=?$predicate', [business, id]);
      }
    }
    for (final id in inventory['attachment'] ?? const <String>{}) {
      for (final table in const ['local_pre_inspection_photos', 'local_finding_photos']) {
        final rows = await db.customSelect('SELECT * FROM $table WHERE business_id=? AND attachment_id=?',
            variables: [Variable<String>(business), Variable<String>(id)]).get();
        if (dirtyScopeIds.contains(id) || rows.any((row) => _hasUnconfirmedContent(row.data))) { unresolved = true; continue; }
        for (final row in rows) { await _queueMedia(db, business, operation, row.data); }
        await db.customStatement('DELETE FROM $table WHERE business_id=? AND attachment_id=?', [business, id]);
      }
    }
    final retainedOutbox = (await db.customSelect(
        'SELECT outbox_id FROM local_job_deletion_v3_scope_outbox WHERE business_id=?',
        variables: [Variable<String>(business)]).get()).map((row) => row.read<int>('outbox_id')).toSet();
    final removedOutbox = <int>{};
    final outbox = await db.customSelect('SELECT * FROM sync_outbox WHERE business_id=?',
        variables: [Variable<String>(business)]).get();
    for (final row in outbox) {
      final payload = _decode(row.data['payload_json']);
      if (_ownedOutbox(row.data, inventory)) {
        if (retainedOutbox.contains(row.read<int>('id'))) { unresolved = true; continue; }
        removedOutbox.add(row.read<int>('id'));
        await _queueMedia(db, business, operation, payload);
        await db.customStatement('DELETE FROM sync_outbox WHERE business_id=? AND id=?', [business, row.data['id']]);
      } else if (payload == null || allIds.contains(row.data['entity_id']) || referencesAny(payload, allIds)) {
        unresolved = true;
      }
    }
    // Aggregate projections can be invalidated wholesale. Outbox work above is
    // never erased because an aggregate cache happened to contain its ID.
    final financial = await db.customSelect('SELECT cache_key,payload_json FROM local_financial_cache WHERE business_id=?',
        variables: [Variable<String>(business)]).get();
    for (final row in financial) {
      final key = row.read<String>('cache_key');
      final value = _decode(row.read<String>('payload_json'));
      if (value == null || referencesAny(value, aliasIds)) { unresolved = true; continue; }
      if ((referencesAny(value, allIds) ||
          (key.startsWith('transaction_detail_') && _has(inventory, 'transaction', key.substring('transaction_detail_'.length)))) &&
          (_hasUnconfirmedContent(value) || dirtyCacheKeys.contains('financial:$key') || referencesAny(value, dirtyScopeIds))) { unresolved = true; continue; }
      if (key.startsWith('transaction_detail_') &&
          _has(inventory, 'transaction', key.substring('transaction_detail_'.length))) {
        await _queueMedia(db, business, operation, value);
        await db.customStatement('DELETE FROM local_financial_cache WHERE business_id=? AND cache_key=?', [business, key]);
      } else if (referencesAny(value, allIds)) {
        if (value is List) {
          for (final item in value.whereType<Map>()) {
            if (_has(inventory, 'transaction', item['id'])) { await _queueMedia(db, business, operation, item); }
          }
        }
        await db.customStatement('DELETE FROM local_financial_cache WHERE business_id=? AND cache_key=?', [business, key]);
      }
    }
    if (await _tableExists(db, 'local_job_retirement_requests')) {
      await db.customStatement("UPDATE local_job_retirement_requests SET snapshot_json='{}',receipt_json=NULL,last_error=NULL WHERE business_id=? AND job_id=? AND state='rejected'", [business, job]);
    }
    unresolved = await _purgeRecovery(db, business, operation, inventory, removedOutbox) || unresolved;
    // References omitted from the verified graph are never guessed into the
    // deletion set. Keep them hidden/read-fenced as applicable for review.
    for (final table in {..._tables.values.map((entry) => entry.$1), 'local_finding_photos'}) {
      final remaining = await db.customSelect('SELECT * FROM $table WHERE business_id=?',
          variables: [Variable<String>(business)]).get();
      if (remaining.any((row) => referencesAny(row.data, {...allIds, ...aliasIds}))) { unresolved = true; }
    }
    if (await _tableExists(db, 'local_job_deletion_v3_previews')) {
      await db.customStatement('DELETE FROM local_job_deletion_v3_previews WHERE business_id=? AND job_id=?', [business, job]);
    }
    if (await _tableExists(db, 'local_job_deletion_v3_intentions')) {
      await db.customStatement('DELETE FROM local_job_deletion_v3_intentions WHERE business_id=? AND job_id=?', [business, job]);
    }
    // v2 previews are replaceable cache snapshots. v2 consent/requests are not
    // upgraded or accepted here, and its immutable markers remain untouched.
    if (await _tableExists(db, 'local_job_retirement_previews')) {
      await db.customStatement('DELETE FROM local_job_retirement_previews WHERE business_id=? AND job_id=?', [business, job]);
    }
    return unresolved;
  }

  static Future<bool> _purgeRecovery(BriskersLocalDatabase db, String business,
      String operation, Map<String, Set<String>> inventory, Set<int> removedOutbox) async {
    var unresolved = false;
    final allIds = _referenceIds(inventory);
    if (await _tableExists(db, 'local_job_recovery_rows')) {
      final rows = await db.customSelect('SELECT * FROM local_job_recovery_rows WHERE business_id=?',
          variables: [Variable<String>(business)]).get();
      for (final row in rows) {
        final table = row.read<String>('table_name');
        final original = _decode(row.read<String>('row_json'));
        var owned = false;
        if (original is Map) {
          for (final entry in _tables.entries) {
            final (mapped, key, _) = entry.value;
            if (mapped == table && _has(inventory, entry.key, original[key]) &&
                (table != 'local_documents' || original['kind'] == entry.key)) { owned = true; }
          }
          if (table == 'sync_outbox') { owned = _ownedOutbox(Map<String, dynamic>.from(original), inventory); }
          if (const ['local_pre_inspection_photos', 'local_finding_photos'].contains(table) &&
              _has(inventory, 'attachment', original['attachment_id'])) { owned = true; }
        }
        if (owned && _hasUnconfirmedContent(original) && table != 'sync_outbox') { owned = false; }
        if (owned) {
          await _queueMedia(db, business, operation, table == 'sync_outbox' && original is Map
              ? _decode(original['payload_json']) : original);
          await db.customStatement('DELETE FROM local_job_recovery_rows WHERE business_id=? AND id=?', [business, row.data['id']]);
        } else if (original == null || referencesAny(original, allIds) ||
            (original is Map && (referencesAny(_decode(original['payload_json']), allIds) ||
              (table == 'sync_outbox' && _decode(original['payload_json']) is! Map))) ||
            allIds.contains(row.data['original_key'])) { unresolved = true; }
      }
    }
    if (await _tableExists(db, 'local_job_retirement_recovery')) {
      final rows = await db.customSelect('SELECT * FROM local_job_retirement_recovery WHERE business_id=?',
          variables: [Variable<String>(business)]).get();
      for (final row in rows) {
        final original = _decode(row.read<String>('original_json'));
        if (original is Map && _ownedOutbox(Map<String, dynamic>.from(original), inventory)) {
          await _queueMedia(db, business, operation, _decode(original['payload_json']));
          await db.customStatement('DELETE FROM local_job_retirement_recovery WHERE business_id=? AND job_id=? AND outbox_id=?',
              [business, row.data['job_id'], row.data['outbox_id']]);
        } else if (original == null || referencesAny(original, allIds) ||
            (original is Map && (_decode(original['payload_json']) is! Map || referencesAny(_decode(original['payload_json']), allIds)))) { unresolved = true; }
      }
    }
    if (await _tableExists(db, 'local_job_recovery_receipts')) {
      final rows = await db.customSelect('SELECT * FROM local_job_recovery_receipts WHERE business_id=?',
          variables: [Variable<String>(business)]).get();
      for (final row in rows) {
        final response = _decode(row.read<String>('response_json'));
        if (removedOutbox.contains(row.data['outbox_id']) ||
            (response is String && allIds.contains(response))) {
          await _queueMedia(db, business, operation, response);
          await db.customStatement('DELETE FROM local_job_recovery_receipts WHERE business_id=? AND id=?',
              [business, row.data['id']]);
        } else if (response == null || referencesAny(response, allIds)) { unresolved = true; }
      }
    }
    // Historical v2 request payloads are not v3 consent. They are not silently
    // rewritten; if they still contain selected contents, completion is blocked
    // until an exact migration/review can safely remove that legacy copy.
    if (await _tableExists(db, 'local_job_retirement_requests')) {
      final rows = await db.customSelect('SELECT snapshot_json,receipt_json FROM local_job_retirement_requests WHERE business_id=?',
          variables: [Variable<String>(business)]).get();
      for (final row in rows) {
        if (_decode(row.data['snapshot_json']) == null ||
            (row.data['receipt_json'] != null && _decode(row.data['receipt_json']) == null) ||
            referencesAny(_decode(row.data['snapshot_json']), allIds) ||
            referencesAny(_decode(row.data['receipt_json']), allIds)) { unresolved = true; }
      }
    }
    return unresolved;
  }

  static Future<bool> _purgePreferences(BriskersLocalDatabase db, String business,
      String operation, Map<String, Set<String>> inventory) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    var unresolved = false;
    final dirtyRows = await db.customSelect(
        'SELECT cache_key FROM local_job_deletion_v3_cache_scope WHERE business_id=? AND dirty=1',
        variables: [Variable<String>(business)]).get();
    final dirtyKeys = dirtyRows.map((row) => row.read<String>('cache_key')).toSet();
    final ids = {...?inventory['invoice'], ...?inventory['estimate']};
    final allIds = _referenceIds(inventory);
    final aliasRows = await db.customSelect("SELECT entity_id FROM local_job_deletion_v3_aliases WHERE business_id=? AND operation_id=? AND entity_kind IN ('invoice','estimate')",
        variables: [Variable<String>(business), Variable<String>(operation)]).get();
    final aliasIds = aliasRows.map((row) => row.read<String>('entity_id')).toSet();
    final prefix = 'briskers_document_detail_${business}_';
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      final detail = _decode(prefs.getString(key));
      if (aliasIds.contains(key.substring(prefix.length)) &&
          !(detail is Map && (ids.contains(detail['id']) || ids.contains(detail['_server_document_id'])))) {
        unresolved = true; continue;
      }
      if (ids.contains(key.substring(prefix.length)) && detail == null) {
        unresolved = true; continue;
      }
      final owned = ids.contains(key.substring(prefix.length)) || (detail is Map &&
          (ids.contains(detail['id']) || ids.contains(detail['_server_document_id'])));
      if ((owned || referencesAny(detail, allIds)) && (_hasUnconfirmedContent(detail) || dirtyKeys.contains(key))) {
        unresolved = true; continue;
      }
      if (owned) { await _queueMedia(db, business, operation, detail); }
      // A shared document snapshot may contain deleted payment or conversion
      // data. Invalidate only its replaceable cache, not its unsynced outbox.
      if (owned || referencesAny(detail, allIds)) {
        if (!await prefs.remove(key)) { throw StateError('preference_cleanup_failed'); }
      }
    }
    return unresolved;
  }

  static Future<bool> _pathStillReferenced(BriskersLocalDatabase db, String path) async {
    for (final table in const ['local_pre_inspection_photos', 'local_finding_photos']) {
      if ((await db.customSelect('SELECT 1 FROM $table WHERE local_file_path=? LIMIT 1',
          variables: [Variable<String>(path)]).get()).isNotEmpty) { return true; }
    }
    for (final entry in const {
      'sync_outbox': 'payload_json', 'local_financial_cache': 'payload_json',
      'local_job_recovery_rows': 'row_json', 'local_job_retirement_recovery': 'original_json',
      'local_job_recovery_receipts': 'response_json',
    }.entries) {
      if (!await _tableExists(db, entry.key)) { continue; }
      final rows = await db.customSelect('SELECT ${entry.value} AS payload FROM ${entry.key}').get();
      for (final row in rows) {
        final raw = row.read<String>('payload');
        // Embedded JSON strings in legacy recovery can also hold a locator.
        if (referencesAny(_decode(raw), {path}) || raw.contains(jsonEncode(path))) { return true; }
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    for (final key in prefs.getKeys().where((key) => key.startsWith('briskers_document_detail_'))) {
      if (referencesAny(_decode(prefs.getString(key)), {path})) { return true; }
    }
    return false;
  }

  /// Local-only purge callers must first prove exclusive local ownership and
  /// commit their minimal fences. This helper enforces app-owned bytes only.
  static Future<bool> cleanupProvenLocalMedia(BriskersLocalDatabase db,
      String business, String operation, {Future<Directory> Function()? mediaDirectoryProvider}) async {
    await ensureSchema(db);
    return db.transaction(() => _purgeMedia(db, business, operation,
        mediaDirectoryProvider ?? getApplicationSupportDirectory));
  }

  static void notifyLocalPurge(BriskersLocalDatabase db, String business, String job) =>
      _notify(db, business, job);

  static Future<bool> _purgeMedia(BriskersLocalDatabase db, String business,
      String operation, Future<Directory> Function() provider) async {
    final rows = await db.customSelect('SELECT local_path FROM local_job_deletion_v3_media '
        'WHERE business_id=? AND operation_id=?',
        variables: [Variable<String>(business), Variable<String>(operation)]).get();
    if (rows.isEmpty) { return true; }
    final support = await provider();
    final canonicalSupport = await support.resolveSymbolicLinks();
    // Directory.uri adds a trailing separator; resolveSymbolicLinks does not.
    final expectedRoot = Directory('$canonicalSupport/briskers_media/$business')
        .absolute.uri.normalizePath().toFilePath().replaceFirst(RegExp(r'[/\\]+$'), '');
    final root = Directory('${support.path}/briskers_media/$business');
    final rootExists = await root.exists();
    final canonicalRoot = rootExists ? await root.resolveSymbolicLinks() : expectedRoot;
    if (canonicalRoot != expectedRoot) { return false; }
    var complete = true;
    for (final row in rows) {
      final path = row.read<String>('local_path');
      final uri = Uri.tryParse(path);
      // SAF and other external originals are explicitly outside app ownership.
      if (uri == null || (uri.hasScheme && uri.scheme != 'file')) {
        complete = false;
        continue;
      }
      final file = File(uri.scheme == 'file' ? uri.toFilePath() : path);
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.file) {
        complete = false;
        continue;
      }
      final canonical = type == FileSystemEntityType.file
          ? await file.resolveSymbolicLinks() : file.absolute.uri.normalizePath().toFilePath();
      if (!canonical.startsWith('$canonicalRoot${Platform.pathSeparator}') ||
          await _pathStillReferenced(db, path)) {
        complete = false;
        continue;
      }
      if (type == FileSystemEntityType.file) { await file.delete(); }
      if (await FileSystemEntity.type(file.path, followLinks: false) != FileSystemEntityType.notFound) {
        complete = false;
        continue;
      }
      await db.customStatement('DELETE FROM local_job_deletion_v3_media WHERE business_id=? AND operation_id=? AND local_path=?',
          [business, operation, path]);
    }
    return complete;
  }

  static Future<LocalDeletionCleanupResult> _cleanup(BriskersLocalDatabase db,
      String business, String job, String operation,
      {Future<Directory> Function()? mediaDirectoryProvider}) async {
    var issue = 'database_cleanup_failed';
    try {
      var generation = -1;
      final unresolved = await db.transaction(() async {
        final current = await db.customSelect('SELECT inventory_generation FROM local_job_deletion_v3_cleanup WHERE business_id=? AND operation_id=?',
            variables: [Variable<String>(business), Variable<String>(operation)]).getSingle();
        generation = current.read<int>('inventory_generation');
        final inventory = await _inventory(db, business, operation);
        final result = await _purgeRows(db, business, job, operation, inventory);
        // Same SQLite lock ordering as LocalDocumentDetailCache.save. A late
        // writer must check the committed v3 markers before writing preferences.
        final preferencesUnresolved = await _purgePreferences(db, business, operation, inventory);
        return result || preferencesUnresolved;
      });
      issue = 'media_cleanup_pending';
      final mediaComplete = await db.transaction(() => _purgeMedia(db, business, operation,
          mediaDirectoryProvider ?? getApplicationSupportDirectory));
      var completed = !unresolved && mediaComplete;
      String? code = unresolved ? 'reconciliation_pending' : (mediaComplete ? null : issue);
      await db.transaction(() async {
        final current = await db.customSelect('SELECT inventory_generation FROM local_job_deletion_v3_cleanup WHERE business_id=? AND operation_id=?',
            variables: [Variable<String>(business), Variable<String>(operation)]).getSingle();
        if (current.read<int>('inventory_generation') != generation) {
          completed = false;
          code = 'inventory_changed';
        }
        await db.customStatement('UPDATE local_job_deletion_v3_cleanup SET state=?,issue_code=? '
            'WHERE business_id=? AND operation_id=?',
            [completed ? 'complete' : 'cleanup_pending', code, business, operation]);
      });
      _notify(db, business, job);
      return LocalDeletionCleanupResult(completed, issueCode: code);
    } catch (_) {
      // Never retain database exceptions that may embed the original contents.
      await db.customStatement('UPDATE local_job_deletion_v3_cleanup SET state=?,issue_code=? '
          'WHERE business_id=? AND operation_id=?', ['cleanup_pending', issue, business, operation]);
      _notify(db, business, job);
      return LocalDeletionCleanupResult(false, issueCode: issue);
    }
  }

  static void _notify(BriskersLocalDatabase db, String business, String job) {
    db.notifyUpdates({for (final entry in _tables.values) TableUpdate(entry.$1),
      const TableUpdate('local_financial_cache'), const TableUpdate('sync_outbox')});
    _events.add((businessId: business, jobIds: {job}));
  }
}
