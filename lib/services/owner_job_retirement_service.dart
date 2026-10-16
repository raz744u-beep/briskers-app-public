import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_cleanup_safety.dart';
import 'local_document_detail_cache.dart';
import 'local_job_retirement.dart';
import 'local_sync_status_repository.dart';
import 'test_job_cleanup_policy.dart';

const ownerRetirementProtocol = 'owner-retirement-2.1';
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
bool _validId(Object? value) => value is String && _uuid.hasMatch(value);
String _newId() {
  final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String _encode(Object? value) => jsonEncode(_canonical(value));

/// A local preflight rejected this specific attempt before any RPC was sent.
/// Never use this type for transport errors or a malformed server response.
class OwnerJobRetirementNotSent extends StateError {
  OwnerJobRetirementNotSent(super.message);
}

/// A missing server capability is an expected availability state, not a
/// technical error that the Owner should have to interpret.
class OwnerJobDeletionUnavailable extends StateError {
  OwnerJobDeletionUnavailable()
      : super('Job deletion is temporarily unavailable. Nothing has been deleted.');
}

String ownerJobDeletionFailureMessage(Object error) =>
    error is OwnerJobDeletionUnavailable
        ? error.message
        : 'Unable to delete Job: $error';

/// Thin, injectable gateway. There is deliberately no legacy delete fallback.
class OwnerJobRetirementGateway {
  const OwnerJobRetirementGateway();
  void assertActor(String expectedActorId) {
    if (Supabase.instance.client.auth.currentUser?.id != expectedActorId) {
      throw OwnerJobRetirementNotSent(
        'The signed-in user changed. Deletion is paused until the original Owner signs in.',
      );
    }
  }

  Future<Map<String, dynamic>> preview(String businessId, String jobId) async =>
      Map<String, dynamic>.from(
        await networkSupabase.rpc(
          'briskers_job_retirement_preview_v2',
          params: {'p_business_id': businessId, 'p_job_id': jobId},
        ) as Map,
      );
  Future<Map<String, dynamic>> execute(
    String businessId,
    String jobId,
    String operationId,
    Map<String, dynamic> snapshot,
  ) async {
    late SupabaseClient client;
    try {
      // Only wrap this synchronous getter. The RPC below can commit despite a
      // later error, so none of its failures are evidence of a no-send outcome.
      client = networkSupabase;
    } on StateError catch (error) {
      throw OwnerJobRetirementNotSent(error.message);
    }
    return Map<String, dynamic>.from(
      await client.rpc(
        'briskers_job_retirement_execute_v2',
        params: {
          'p_business_id': businessId,
          'p_job_id': jobId,
          'p_operation_id': operationId,
          'p_expected_snapshot': snapshot,
        },
      ) as Map,
    );
  }

  Future<Map<String, dynamic>> tombstones(
    String businessId, {
    required int afterCursor,
    int limit = 200,
  }) async => Map<String, dynamic>.from(
    await networkSupabase.rpc(
      'briskers_job_retirement_tombstones_v2',
      params: {
        'p_business_id': businessId,
        'p_after_cursor': afterCursor,
        'p_limit': limit,
      },
    ) as Map,
  );
}

enum OwnerJobRetirementStatus { pending, accepted, rejected, locallyCancelled }

class OwnerJobRetirementResult {
  const OwnerJobRetirementResult({
    required this.status,
    required this.operationId,
    required this.message,
  });
  final OwnerJobRetirementStatus status;
  final String operationId;
  final String message;
}

class OwnerJobRetirementPreview {
  OwnerJobRetirementPreview._(
    Map<String, dynamic> snapshot, {
    required this.actorId,
    required this.fromCache,
  }) : _snapshotJson = _encode(snapshot);
  final String _snapshotJson;
  final String actorId;
  final bool fromCache;
  // Defensive copies prevent edits to a displayed preview changing consent.
  Map<String, dynamic> get snapshot =>
      Map<String, dynamic>.from(jsonDecode(_snapshotJson) as Map);
  String get businessId => snapshot['business_id'] as String;
  String get jobId => snapshot['job_id'] as String;
  bool get canRetire => snapshot['can_retire'] == true;
  bool get localOnly => snapshot['local_only'] == true;
  List<String> get blockedReasons => (snapshot['blocked_reasons'] as List)
      .map((value) {
        if (value is! Map) {
          return 'The Job has protected or unverified linked records.';
        }
        final reason = value['reason']?.toString();
        final relation = value['relation']?.toString() ?? '';
        if (relation.contains('payment') || relation.contains('transaction')) {
          return 'Payments, receipts or pending payment activity must be preserved.';
        }
        if (relation.contains('expense')) {
          return 'Linked expenses must be preserved.';
        }
        if (relation.contains('assignment') ||
            relation.contains('labor') ||
            relation.contains('payroll') ||
            reason == 'protected_visit') {
          return 'Recorded work, staff assignments or payroll history must be preserved.';
        }
        return switch (reason) {
          'protected_document_state' || 'imported_line' => 'An issued, imported, closed or otherwise protected invoice cannot be deleted.',
          'protected_job_state' || 'protected_status_history' =>
            'This Job has protected status or authorization history.',
          'cross_business_reference' =>
            'A linked record belongs to another business and must be reviewed.',
          _ => 'Shared records or other protected dependencies need review before deletion.',
        };
      })
      .toSet()
      .toList();
  List<Map<String, dynamic>> get invoices => (snapshot['invoices'] as List)
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  List<Map<String, dynamic>> get estimatesPreserved =>
      (snapshot['estimates_preserved'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
}

/// Persist consent and stable operation UUID before the first network write.
/// A timeout/response loss always remains pending and retries the exact request.
class OwnerJobRetirementService {
  /// Mirrors the backend feed's active-staff role scope. Customer sessions do
  /// not gain staff tombstone access and must keep their existing sync route.
  static bool isStaffRole(String roleCode) => const {
    'owner',
    'manager',
    'office',
    'mechanic',
    'porter',
  }.contains(roleCode);

  static bool isTombstoneReaderRole(String roleCode) =>
      isStaffRole(roleCode) || roleCode == 'customer';

  OwnerJobRetirementService({
    BriskersLocalDatabase? database,
    OwnerJobRetirementGateway gateway = const OwnerJobRetirementGateway(),
    Duration timeout = const Duration(seconds: 25),
  }) : _database = database ?? localDatabase,
       _gateway = gateway,
       _timeout = timeout;
  final BriskersLocalDatabase _database;
  final OwnerJobRetirementGateway _gateway;
  final Duration _timeout;
  static final _statusEvents = StreamController<String>.broadcast(sync: true);
  static Stream<String> get statusEvents => _statusEvents.stream;

  static void _identity(
    String businessId,
    String jobId,
    String actorId,
    bool isOwner,
  ) {
    if (!isOwner) {
      throw StateError('Owner access is required to delete a Job.');
    }
    if (!_validId(businessId) || !_validId(jobId) || !_validId(actorId)) {
      throw StateError(
        'Job deletion requires verified business, Job and signed-in user UUIDs. Refresh this Job before trying again.',
      );
    }
  }

  static void validateSnapshot(
    Map<String, dynamic> value,
    String businessId,
    String jobId,
  ) {
    if (value['schema_version'] != 2 ||
        value['protocol_version'] != ownerRetirementProtocol ||
        value['business_id'] != businessId ||
        value['job_id'] != jobId ||
        !_validId(value['actor_id']) ||
        value['inventory_complete'] != true ||
        value['write_fences_verified'] != true ||
        value['can_retire'] is! bool ||
        value['blocked_reasons'] is! List ||
        value['invoices'] is! List ||
        value['estimates_preserved'] is! List) {
      throw StateError(
        'Safe Job deletion is not available: the server did not provide a complete verified deletion preview. Nothing was deleted.',
      );
    }
    final ids = <String>{};
    for (final invoice in value['invoices'] as List) {
      if (invoice is! Map ||
          !_validId(invoice['id']) ||
          !ids.add(invoice['id'] as String) ||
          invoice['business_id'] != businessId ||
          invoice['job_id'] != jobId ||
          invoice['kind'] != 'invoice') {
        throw StateError(
          'The deletion preview contains an unverified invoice identity. Nothing was deleted.',
        );
      }
      if (value['can_retire'] == true &&
          (invoice['origin'] != 'native' ||
              invoice['status'] != 'draft' ||
              invoice['has_financial_history'] != false ||
              invoice['has_pending_operations'] != false ||
              invoice['has_protected_history'] != false)) {
        throw StateError(
          'This invoice has protected or uncertain history. Deletion is blocked.',
        );
      }
    }
    for (final estimate in value['estimates_preserved'] as List) {
      if (estimate is! Map ||
          !_validId(estimate['id']) ||
          ids.contains(estimate['id'])) {
        throw StateError(
          'The preserved estimate inventory is invalid. Nothing was deleted.',
        );
      }
    }
    if (value['can_retire'] == true &&
        (value['blocked_reasons'] as List).isNotEmpty) {
      throw StateError(
        'The deletion preview contains unresolved blockers. Nothing was deleted.',
      );
    }
  }

  Future<void> _checkLocalWork(String businessId, String jobId) async {
    await LocalCleanupSafety.requireJobRemovable(_database, businessId, jobId);
    final rows = await _database
        .customSelect(
          'SELECT id FROM local_documents WHERE business_id=? AND job_id=?',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();
    final cache = LocalDocumentDetailCache(database: _database);
    for (final row in rows) {
      if (TestJobCleanupPolicy.hasPendingSnapshot(
        await cache.load(businessId, row.read<String>('id')),
      )) {
        throw StateError(
          'This Job has local document edits or payment history. Synchronize and review them before deletion.',
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _unsentCreation(
    String businessId,
    String jobId,
  ) async {
    final rows = await _database
        .customSelect(
          "SELECT o.*,j.row_version,j.server_updated_at,j.job_number FROM sync_outbox o "
          "JOIN local_jobs j ON j.business_id=o.business_id AND j.id=o.entity_id WHERE o.business_id=? AND o.entity_id=? "
          "AND o.entity_type='job_create' AND o.state='pending' AND o.attempt_count=0 AND j.row_version IS NULL AND j.server_updated_at IS NULL",
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();
    if (rows.length != 1 ||
        rows.single.readNullable<String>('job_number') != 'Pending sync') {
      return null;
    }
    final row = rows.single;
    final related = await _database
        .customSelect(
          "SELECT id,entity_id,payload_json FROM sync_outbox WHERE business_id=? AND id<>?",
          variables: [
            Variable<String>(businessId),
            Variable<int>(row.read<int>('id')),
          ],
        )
        .get();
    for (final other in related) {
      Object? payload;
      try {
        payload = jsonDecode(other.read<String>('payload_json'));
      } catch (_) {
        return null;
      }
      if (payload is! Map ||
          other.read<String>('entity_id') == jobId ||
          LocalCleanupSafety.referencesAny(payload, {jobId})) {
        return null;
      }
    }
    // A local-only cancellation may not hide visits, documents or photos.
    for (final table in [
      'local_documents',
      'local_job_visits',
      'local_pre_inspections',
      'local_job_assignments',
    ]) {
      if ((await _database
              .customSelect(
                'SELECT 1 FROM $table WHERE business_id=? AND job_id=? LIMIT 1',
                variables: [
                  Variable<String>(businessId),
                  Variable<String>(jobId),
                ],
              )
              .get())
          .isNotEmpty) {
        return null;
      }
    }
    return {
      'outbox_id': row.read<int>('id'),
      'payload_json': row.read<String>('payload_json'),
    };
  }

  Future<OwnerJobRetirementPreview> preview(
    String businessId,
    String jobId, {
    required String actorId,
    required bool isOwner,
    bool online = true,
  }) async {
    _identity(businessId, jobId, actorId, isOwner);
    _gateway.assertActor(actorId);
    await LocalJobRetirement.ensureSchema(_database);
    if (await LocalJobRetirement.isJobBlocked(_database, businessId, jobId)) {
      throw StateError(
        'This Job already has a pending or accepted deletion. Check synchronization status.',
      );
    }
    final localCreate = await _unsentCreation(businessId, jobId);
    if (localCreate != null) {
      return OwnerJobRetirementPreview._(
        {
          'schema_version': 2,
          'protocol_version': ownerRetirementProtocol,
          'business_id': businessId,
          'job_id': jobId,
          'can_retire': true,
          'local_only': true,
          'local_create': localCreate,
          'invoices': [],
          'estimates_preserved': [],
          'blocked_reasons': [],
        },
        actorId: actorId,
        fromCache: !online,
      );
    }
    await _checkLocalWork(businessId, jobId);
    Map<String, dynamic> value;
    if (online) {
      try {
        _gateway.assertActor(actorId);
        value = await _gateway.preview(businessId, jobId).timeout(_timeout);
      } on PostgrestException catch (error) {
        if ({'PGRST202', '42883'}.contains(error.code) &&
            error.message.contains('briskers_job_retirement_preview_v2')) {
          throw OwnerJobDeletionUnavailable();
        }
        rethrow;
      }
      validateSnapshot(value, businessId, jobId);
      if (value['actor_id'] != actorId) {
        throw StateError(
          'The signed-in Owner changed. Open a fresh deletion preview.',
        );
      }
      await _database.customStatement(
        'INSERT INTO local_job_retirement_previews (business_id,job_id,actor_id,snapshot_json) VALUES (?,?,?,?) '
        'ON CONFLICT(business_id,job_id) DO UPDATE SET actor_id=excluded.actor_id,snapshot_json=excluded.snapshot_json',
        [businessId, jobId, actorId, _encode(value)],
      );
    } else {
      final cached = await _database
          .customSelect(
            'SELECT snapshot_json FROM local_job_retirement_previews WHERE business_id=? AND job_id=? AND actor_id=?',
            variables: [
              Variable<String>(businessId),
              Variable<String>(jobId),
              Variable<String>(actorId),
            ],
          )
          .get();
      if (cached.isEmpty) {
        throw StateError(
          'Connect once to obtain a verified deletion preview. This Job cannot safely be deleted offline yet.',
        );
      }
      value = Map<String, dynamic>.from(
        jsonDecode(cached.single.read<String>('snapshot_json')) as Map,
      );
      validateSnapshot(value, businessId, jobId);
      if (value['actor_id'] != actorId) {
        throw StateError(
          'This cached deletion preview belongs to another Owner.',
        );
      }
    }
    return OwnerJobRetirementPreview._(
      value,
      actorId: actorId,
      fromCache: !online,
    );
  }

  Future<OwnerJobRetirementResult> queueConfirmed(
    OwnerJobRetirementPreview preview, {
    required String actorId,
    required bool isOwner,
    bool online = true,
  }) async {
    _identity(preview.businessId, preview.jobId, actorId, isOwner);
    _gateway.assertActor(actorId);
    if (preview.actorId != actorId) {
      throw StateError(
        'The signed-in user changed. Open a fresh deletion preview.',
      );
    }
    if (!preview.canRetire) throw StateError(preview.blockedReasons.join('\n'));
    await LocalJobRetirement.ensureSchema(_database);
    final businessId = preview.businessId, jobId = preview.jobId;
    await _database.transaction(() async {
      final current = await status(businessId, jobId);
      if (current != null &&
          current.status != OwnerJobRetirementStatus.rejected) {
        return;
      }
      if (preview.localOnly) {
        if (_encode(await _unsentCreation(businessId, jobId)) !=
            _encode(preview.snapshot['local_create'])) {
          throw StateError(
            'The Job creation started synchronizing. Refresh online before deleting; its outcome is not yet known.',
          );
        }
      } else {
        validateSnapshot(preview.snapshot, businessId, jobId);
        await _checkLocalWork(businessId, jobId);
        final cached = await _database
            .customSelect(
              'SELECT snapshot_json FROM local_job_retirement_previews WHERE business_id=? AND job_id=? AND actor_id=?',
              variables: [
                Variable<String>(businessId),
                Variable<String>(jobId),
                Variable<String>(actorId),
              ],
            )
            .get();
        if (cached.isEmpty ||
            cached.single.read<String>('snapshot_json') !=
                preview._snapshotJson) {
          throw StateError(
            'The deletion preview changed. Review it and confirm again.',
          );
        }
      }
      _gateway.assertActor(actorId);
      final operationId = _newId();
      final state = preview.localOnly ? 'locally_cancelled' : 'pending';
      await _database.customStatement(
        '''INSERT INTO local_job_retirement_requests
        (business_id,job_id,operation_id,actor_id,snapshot_json,state,created_at) VALUES (?,?,?,?,?,?,?)
        ON CONFLICT(business_id,job_id) DO UPDATE SET operation_id=excluded.operation_id,
        actor_id=excluded.actor_id,snapshot_json=excluded.snapshot_json,state=excluded.state,
        created_at=excluded.created_at,attempt_count=0,outcome_uncertain=0,last_error=NULL,receipt_json=NULL''',
        [
          businessId,
          jobId,
          operationId,
          actorId,
          preview._snapshotJson,
          state,
          DateTime.now().toUtc().millisecondsSinceEpoch,
        ],
      );
      await LocalJobRetirement.recordEntity(
        _database,
        businessId: businessId,
        jobId: jobId,
        entityKind: 'job',
        entityId: jobId,
        operationId: operationId,
        state: state,
      );
      for (final invoice in preview.invoices) {
        await LocalJobRetirement.recordEntity(
          _database,
          businessId: businessId,
          jobId: jobId,
          entityKind: 'invoice',
          entityId: invoice['id'] as String,
          operationId: operationId,
          state: state,
        );
      }
      await LocalJobRetirement.quarantineRelated(_database, businessId, jobId);
      if (preview.localOnly) {
        await _database.customStatement(
          "UPDATE sync_outbox SET state='cancelled',last_error='Unsent creation cancelled by Owner' WHERE business_id=? AND entity_id=? AND entity_type='job_create' AND state='retirement_quarantine'",
          [businessId, jobId],
        );
      }
    });
    _notify(businessId, {jobId});
    if (online && !preview.localOnly) {
      await flush(businessId, actorId: actorId, isOwner: isOwner);
    }
    return (await status(businessId, jobId))!;
  }

  Future<OwnerJobRetirementResult?> status(
    String businessId,
    String jobId,
  ) async {
    await LocalJobRetirement.ensureSchema(_database);
    final rows = await _database
        .customSelect(
          'SELECT operation_id,state,last_error FROM local_job_retirement_requests WHERE business_id=? AND job_id=?',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    final state = row.read<String>('state');
    final status = state == 'accepted'
        ? OwnerJobRetirementStatus.accepted
        : state == 'rejected'
        ? OwnerJobRetirementStatus.rejected
        : state == 'locally_cancelled'
        ? OwnerJobRetirementStatus.locallyCancelled
        : OwnerJobRetirementStatus.pending;
    final message = switch (status) {
      OwnerJobRetirementStatus.accepted => 'Job deleted. Estimates and all protected history are preserved. Its number will not be reused.',
      OwnerJobRetirementStatus.locallyCancelled => 'Unsent Job creation cancelled on this device. No server Job or number was created.',
      OwnerJobRetirementStatus.rejected =>
        row.readNullable<String>('last_error') ?? 'Deletion was rejected. The Job is visible again; refresh and review before trying again.',
      OwnerJobRetirementStatus.pending =>
        row.readNullable<String>('last_error') ?? 'Deletion queued on this device. Server confirmation is pending; it will retry with the same request.',
    };
    return OwnerJobRetirementResult(
      status: status,
      operationId: row.read<String>('operation_id'),
      message: message,
    );
  }

  static final _flushes = Expando<Map<String, Future<void>>>(
    'retirement_flushes',
  );
  Future<void> flush(
    String businessId, {
    required String actorId,
    required bool isOwner,
  }) async {
    final active = _flushes[_database] ??= <String, Future<void>>{};
    final before = active[businessId];
    if (before != null) return before;
    final future = _flush(businessId, actorId: actorId, isOwner: isOwner);
    active[businessId] = future;
    try {
      await future;
    } finally {
      if (identical(active[businessId], future)) active.remove(businessId);
    }
  }

  Future<void> _flush(
    String businessId, {
    required String actorId,
    required bool isOwner,
  }) async {
    await LocalJobRetirement.ensureSchema(_database);
    final rows = await _database
        .customSelect(
          "SELECT * FROM local_job_retirement_requests WHERE business_id=? AND state='pending' ORDER BY created_at",
          variables: [Variable<String>(businessId)],
        )
        .get();
    for (final row in rows) {
      final jobId = row.read<String>('job_id'),
          operationId = row.read<String>('operation_id');
      // Session/role changes never replay another actor's consent.
      if (!isOwner || row.read<String>('actor_id') != actorId) {
        await _database.customStatement(
          'UPDATE local_job_retirement_requests SET last_error=? WHERE business_id=? AND operation_id=?',
          [
            'Deletion is paused. Sign in as the Owner who confirmed it to check the outcome.',
            businessId,
            operationId,
          ],
        );
        _notify(businessId, {jobId});
        continue;
      }
      final snapshot = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('snapshot_json')) as Map,
      );
      validateSnapshot(snapshot, businessId, jobId);
      _identity(businessId, jobId, actorId, isOwner);
      final previouslyUncertain = row.read<int>('outcome_uncertain') != 0;
      await _database.customStatement(
        'UPDATE local_job_retirement_requests SET attempt_count=attempt_count+1,outcome_uncertain=1 WHERE business_id=? AND operation_id=?',
        [businessId, operationId],
      );
      try {
        _gateway.assertActor(actorId);
        if (snapshot['actor_id'] != actorId) {
          throw StateError(
            'Original Owner consent does not match the active session.',
          );
        }
        final receipt = await _gateway
            .execute(businessId, jobId, operationId, snapshot)
            .timeout(_timeout);
        _validateReceipt(receipt, businessId, jobId, operationId, snapshot);
        await _database.transaction(() async {
          await _database.customStatement(
            "UPDATE local_job_retirement_requests SET state='accepted',receipt_json=?,last_error=NULL,outcome_uncertain=0 WHERE business_id=? AND operation_id=?",
            [_encode(receipt), businessId, operationId],
          );
          await _database.customStatement(
            "UPDATE local_job_retirement_entities SET state='accepted' WHERE business_id=? AND job_id=?",
            [businessId, jobId],
          );
          await LocalJobRetirement.quarantineRelated(
            _database,
            businessId,
            jobId,
          );
        });
      } on OwnerJobRetirementNotSent catch (error) {
        await _database.customStatement(
          "UPDATE local_job_retirement_requests SET outcome_uncertain=?,last_error=? WHERE business_id=? AND operation_id=? AND state='pending'",
          [
            previouslyUncertain ? 1 : 0,
            previouslyUncertain
                ? 'This retry was not sent; an earlier result is still uncertain. ${error.message}'
                : 'Deletion is queued and this request was not sent. ${error.message}',
            businessId,
            operationId,
          ],
        );
      } on PostgrestException catch (error) {
        // Only a first-attempt SQL rejection proves this operation did not
        // commit. Any earlier response loss remains uncertain, even if Owner
        // access or deployment changes before this retry. Serialization and
        // deadlock responses are retryable, not a changed-consent decision.
        final retiredElsewhere =
            error.code == '55000' &&
            error.message.toLowerCase().contains('already retired');
        final rejected =
            !retiredElsewhere &&
            !previouslyUncertain &&
            ({
                  '42501',
                  '22023',
                  '55000',
                  'PGRST202',
                  '42883',
                }.contains(error.code) ||
                (error.code == 'P0001' &&
                    error.details == 'retirement_snapshot_changed'));
        await _database.transaction(() async {
          await _database.customStatement(
            'UPDATE local_job_retirement_requests SET state=?,last_error=?,outcome_uncertain=? WHERE business_id=? AND operation_id=? AND state<>\'accepted\'',
            [
              rejected ? 'rejected' : 'pending',
              rejected
                  ? _serverMessage(error)
                  : 'Deletion confirmation is uncertain. The same request will retry. ${error.message}',
              retiredElsewhere ||
                      previouslyUncertain ||
                      !{
                        '40P01',
                        '40001',
                        '42501',
                        '22023',
                        '55000',
                        'P0001',
                        'PGRST202',
                        '42883',
                      }.contains(error.code)
                  ? 1
                  : 0,
              businessId,
              operationId,
            ],
          );
          if (rejected) {
            await _database.customStatement(
              "UPDATE local_job_retirement_entities SET state='rejected' WHERE business_id=? AND job_id=? AND state<>'accepted'",
              [businessId, jobId],
            );
            await _database.customStatement(
              'DELETE FROM local_job_retirement_previews WHERE business_id=? AND job_id=?',
              [businessId, jobId],
            );
          }
        });
        if (retiredElsewhere) {
          // Another device's operation can satisfy the requested outcome, but
          // only its authoritative tombstone can remove this pending fence.
          try {
            await pullTombstones(businessId);
          } catch (_) {
            /* Keep pending and diagnostics. */
          }
        }
      } catch (_) {
        await _database.customStatement(
          "UPDATE local_job_retirement_requests SET last_error=? WHERE business_id=? AND operation_id=? AND state='pending'",
          [
            'Deletion confirmation is pending after a connection or response problem. It will retry the same request; do not create a replacement Job.',
            businessId,
            operationId,
          ],
        );
      }
      _notify(businessId, {jobId});
    }
  }

  static void _validateReceipt(
    Map<String, dynamic> value,
    String businessId,
    String jobId,
    String operationId,
    Map<String, dynamic> snapshot,
  ) {
    final expected = (snapshot['invoices'] as List)
        .map((v) => (v as Map)['id'])
        .toSet();
    final received = value['retired_invoice_ids'];
    if (value['schema_version'] != 2 ||
        value['protocol_version'] != ownerRetirementProtocol ||
        value['business_id'] != businessId ||
        value['job_id'] != jobId ||
        value['operation_id'] != operationId ||
        received is! List ||
        received.length != expected.length ||
        received.any((id) => !expected.contains(id)) ||
        received.toSet().length != received.length ||
        _encode(value['estimates_preserved']) !=
            _encode(snapshot['estimates_preserved'])) {
      throw StateError(
        'Unverified server deletion receipt. Keep the original request pending.',
      );
    }
  }

  static String _serverMessage(PostgrestException error) {
    if ({'PGRST202', '42883'}.contains(error.code) ||
        error.message.contains('not deployed')) {
      return 'Safe Job deletion is not deployed on this server yet. Nothing was deleted; the Job is visible again.';
    }
    if (error.code == '42501') {
      return 'Owner permission is unavailable or changed. Nothing was deleted; sign in again and refresh the Job.';
    }
    if (error.code == 'P0001' &&
        error.details == 'retirement_snapshot_changed') {
      return 'The Job or its linked records changed. Nothing was deleted; refresh the Job and review a new preview.';
    }
    return 'Deletion was rejected: ${error.message} The Job is visible again; refresh and review before retrying.';
  }

  void _notify(String businessId, Set<String> jobIds) {
    LocalJobRetirement.notify(_database, businessId, jobIds);
    _statusEvents.add(businessId);
    LocalSyncStatusRepository.notifyStateChanged(businessId);
  }

  static final _tombstonePulls = Expando<Map<String, Future<void>>>(
    'retirement_tombstone_pulls',
  );

  /// All sync services sharing this database must share one feed traversal.
  /// Otherwise a slower response can replace a newer cursor or reader scope.
  Future<void> pullTombstones(String businessId) async {
    final active = _tombstonePulls[_database] ??= <String, Future<void>>{};
    final before = active[businessId];
    if (before != null) return before;
    final future = _pullTombstonesWithDiagnostics(businessId);
    active[businessId] = future;
    try {
      await future;
    } finally {
      if (identical(active[businessId], future)) active.remove(businessId);
    }
  }

  /// Tombstones and their cursor commit together. Any invalid page or failed
  /// request leaves the last committed cursor intact and prevents stale pulls.
  Future<void> _pullTombstonesWithDiagnostics(String businessId) async {
    try {
      await _pullTombstones(businessId);
    } catch (error) {
      await _database.customStatement(
        "INSERT INTO local_sync_states (business_id,scope,last_error,bootstrapped) VALUES (?,'job_retirements_v2',?,0) "
        "ON CONFLICT(business_id,scope) DO UPDATE SET last_error=excluded.last_error",
        [businessId, 'Deletion synchronization paused: $error'],
      );
      LocalSyncStatusRepository.notifyStateChanged(businessId);
      rethrow;
    }
  }

  Future<void> _pullTombstones(String businessId) async {
    if (!_validId(businessId)) {
      throw StateError('Invalid business UUID for retirement synchronization.');
    }
    await LocalJobRetirement.ensureSchema(_database);
    final states = await _database
        .customSelect(
          "SELECT last_server_cursor FROM local_sync_states WHERE business_id=? AND scope='job_retirements_v2'",
          variables: [Variable<String>(businessId)],
        )
        .get();
    var cursor = states.isEmpty
        ? 0
        : states.single.readNullable<int>('last_server_cursor') ?? 0;
    final contexts = await _database
        .customSelect(
          'SELECT visibility_scope FROM local_job_retirement_feed_context WHERE business_id=?',
          variables: [Variable<String>(businessId)],
        )
        .get();
    String? expectedScope = contexts.isEmpty
        ? null
        : contexts.single.read<String>('visibility_scope');
    var scopeChanges = 0;
    var more = true;
    while (more) {
      Map<String, dynamic> page;
      try {
        page = await _gateway
            .tombstones(businessId, afterCursor: cursor)
            .timeout(_timeout);
      } on PostgrestException catch (error) {
        // Before deployment only: absence of the new read endpoint may not
        // break unrelated legacy sync. Once this device observes the protocol,
        // its disappearance is unsafe and must never be treated as empty.
        if ({'PGRST202', '42883'}.contains(error.code) &&
            error.message.contains('briskers_job_retirement_tombstones_v2')) {
          final evidence = await _database
              .customSelect(
                "SELECT (SELECT COUNT(*) FROM local_job_retirement_entities WHERE business_id=?) + "
                "(SELECT COUNT(*) FROM local_job_retirement_requests WHERE business_id=?) + "
                "(SELECT COUNT(*) FROM local_job_retirement_previews WHERE business_id=?) + "
                "(SELECT COUNT(*) FROM local_sync_states WHERE business_id=? AND scope='job_retirements_v2' AND bootstrapped=1) AS n",
                variables: List.generate(
                  4,
                  (_) => Variable<String>(businessId),
                ),
              )
              .getSingle();
          if (evidence.read<int>('n') == 0) return;
        }
        rethrow;
      }
      final visibilityScope = page['visibility_scope'];
      if (page['schema_version'] != 2 ||
          page['business_id'] != businessId ||
          !_validId(page['actor_id']) ||
          !{'staff', 'customer'}.contains(page['reader_scope']) ||
          visibilityScope is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(visibilityScope)) {
        throw StateError(
          'The deletion feed did not verify its signed-in reader scope. Synchronization is paused.',
        );
      }
      _gateway.assertActor(page['actor_id'] as String);
      if (visibilityScope != expectedScope &&
          (expectedScope != null || cursor != 0)) {
        if (++scopeChanges > 3) {
          throw StateError(
            'Account access changed repeatedly during deletion synchronization. Sign in again and retry.',
          );
        }
        // A former customer cursor can skip old staff-only invoices, and new
        // customer links can reveal older Jobs. Discard this page and replay
        // from zero without removing any accepted permanent local fences.
        expectedScope = visibilityScope;
        cursor = 0;
        continue;
      }
      expectedScope = visibilityScope;
      final values = page['tombstones'], next = page['cursor'];
      if (page['schema_version'] != 2 ||
          page['business_id'] != businessId ||
          values is! List ||
          values.length > 200 ||
          page['has_more'] is! bool ||
          next is! int ||
          next < cursor ||
          (page['has_more'] == true && (values.isEmpty || next == cursor))) {
        throw StateError(
          'Invalid deletion tombstone page. Synchronization stopped without advancing its cursor.',
        );
      }
      var prior = cursor;
      final jobs = <String>{};
      for (final value in values) {
        if (value is! Map ||
            value['business_id'] != businessId ||
            !{'job', 'invoice'}.contains(value['entity_kind']) ||
            !_validId(value['entity_id']) ||
            !_validId(value['job_id']) ||
            !_validId(value['operation_id']) ||
            (value['entity_kind'] == 'job' &&
                value['entity_id'] != value['job_id']) ||
            value['cursor'] is! int ||
            (value['cursor'] as int) <= prior ||
            (value['cursor'] as int) > next) {
          throw StateError(
            'Invalid deletion tombstone identity or order. Synchronization stopped.',
          );
        }
        prior = value['cursor'] as int;
        jobs.add(value['job_id'] as String);
      }
      if ((values.isNotEmpty && prior != next) ||
          (values.isEmpty && next != cursor)) {
        throw StateError('Unverified deletion cursor.');
      }
      await _database.transaction(() async {
        await _database.customStatement(
          'INSERT INTO local_job_retirement_feed_context (business_id,visibility_scope) VALUES (?,?) '
          'ON CONFLICT(business_id) DO UPDATE SET visibility_scope=excluded.visibility_scope',
          [businessId, visibilityScope],
        );
        for (final raw in values) {
          final value = raw as Map;
          await LocalJobRetirement.recordEntity(
            _database,
            businessId: businessId,
            jobId: value['job_id'] as String,
            entityKind: value['entity_kind'] as String,
            entityId: value['entity_id'] as String,
            operationId: value['operation_id'] as String,
            state: 'accepted',
          );
          // A page containing only invoice tombstones still fences its Job.
          await LocalJobRetirement.recordEntity(
            _database,
            businessId: businessId,
            jobId: value['job_id'] as String,
            entityKind: 'job',
            entityId: value['job_id'] as String,
            operationId: value['operation_id'] as String,
            state: 'accepted',
          );
        }
        for (final jobId in jobs) {
          await LocalJobRetirement.quarantineRelated(
            _database,
            businessId,
            jobId,
          );
          await _database.customStatement(
            "UPDATE local_job_retirement_requests SET state='accepted',last_error=NULL,outcome_uncertain=0 WHERE business_id=? AND job_id=?",
            [businessId, jobId],
          );
        }
        await _database.customStatement(
          "INSERT INTO local_sync_states (business_id,scope,last_server_cursor,last_pull_at,bootstrapped) VALUES (?,'job_retirements_v2',?,?,1) "
          "ON CONFLICT(business_id,scope) DO UPDATE SET last_server_cursor=excluded.last_server_cursor,last_pull_at=excluded.last_pull_at,bootstrapped=1,last_error=NULL",
          [
            businessId,
            next,
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          ],
        );
      });
      cursor = next;
      more = page['has_more'] == true;
      if (jobs.isNotEmpty) _notify(businessId, jobs);
    }
  }
}
