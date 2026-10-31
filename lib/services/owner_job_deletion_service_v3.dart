import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_job_deletion_v3.dart';
import 'local_deletion_origins_contract.dart';
import 'local_job_retirement.dart';
import 'local_sync_status_repository.dart';
import 'owner_job_deletion_v3_contract.dart';

class JobDeletionV3Gateway {
  const JobDeletionV3Gateway();
  void assertActor(String actorId) {
    if (Supabase.instance.client.auth.currentUser?.id != actorId) {
      throw StateError('Your signed-in account changed. Review deletion again.');
    }
  }
  Future<Map<String, dynamic>> preview(String business, String job) async =>
      Map<String, dynamic>.from(await networkSupabase.rpc(
        'briskers_job_delete_preview_v3',
        params: {'p_business_id': business, 'p_job_id': job},
      ) as Map);
  Future<Map<String, dynamic>> execute(String business, String job,
      String operation, Map<String, dynamic> confirmation) async =>
      Map<String, dynamic>.from(await networkSupabase.rpc(
        'briskers_job_delete_execute_v3', params: {
          'p_business_id': business, 'p_job_id': job,
          'p_operation_id': operation, 'p_confirmation': confirmation,
        },
      ) as Map);
  Future<Map<String, dynamic>> status(String business, String operation) async =>
      Map<String, dynamic>.from(await networkSupabase.rpc(
        'briskers_job_delete_status_v3', params: {
          'p_business_id': business, 'p_operation_id': operation,
        },
      ) as Map);
  Future<Map<String, dynamic>> localOrigins(String business, List<String> operations) async =>
      Map<String, dynamic>.from(await networkSupabase.rpc(
        'briskers_job_delete_local_origins_v3', params: {
          'p_business_id': business, 'p_operation_ids': operations,
        },
      ) as Map);
  Future<Map<String, dynamic>> tombstones(String business, int cursor) async =>
      Map<String, dynamic>.from(await networkSupabase.rpc(
        'briskers_job_delete_tombstones_v3', params: {
          'p_business_id': business, 'p_after_cursor': cursor, 'p_limit': 200,
        },
      ) as Map);
}

class JobDeletionV3Result {
  const JobDeletionV3Result(this.state, this.message);
  final String state;
  final String message;
}

class OwnerJobDeletionServiceV3 {
  OwnerJobDeletionServiceV3({BriskersLocalDatabase? database,
    JobDeletionV3Gateway gateway = const JobDeletionV3Gateway(),
    DateTime Function()? clock, Duration timeout = const Duration(seconds: 25),
  }) : _db = database ?? localDatabase, _gateway = gateway,
       _clock = clock ?? DateTime.now, _timeout = timeout;
  final BriskersLocalDatabase _db;
  final JobDeletionV3Gateway _gateway;
  final DateTime Function() _clock;
  final Duration _timeout;
  static final _flights = Expando<Map<String, Future<void>>>('job_delete_v3_flush');

  Future<void> ensureSchema() async {
    await _db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_intentions (
      business_id TEXT NOT NULL, job_id TEXT NOT NULL, actor_id TEXT NOT NULL,
      PRIMARY KEY(business_id,job_id))''');
    await _db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_previews (
      business_id TEXT NOT NULL, job_id TEXT NOT NULL, actor_id TEXT NOT NULL,
      preview_json TEXT NOT NULL, verified_at INTEGER NOT NULL,
      PRIMARY KEY(business_id,job_id))''');
    await _db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_requests (
      business_id TEXT NOT NULL, job_id TEXT NOT NULL, operation_id TEXT NOT NULL,
      actor_id TEXT NOT NULL, confirmation_json TEXT NOT NULL, state TEXT NOT NULL,
      last_error TEXT, receipt_json TEXT, attempted INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(business_id,operation_id), UNIQUE(business_id,job_id))''');
  }

  bool _expired(Map<String, dynamic> confirmation) =>
      !_clock().toUtc().isBefore(DateTime.parse(confirmation['expires_at'] as String));

  Future<JobDeletionV3Preview> preview(String business, String job,
      {required String actorId, required bool isOwner, bool online = true}) async {
    if (!isOwner) throw StateError('Only the Owner can delete a Job.');
    if (!isDeletionV3Id(business) || !isDeletionV3Id(actorId) || !isDeletionV3Id(job)) {
      throw StateError('Sync this Job and sign in before reviewing permanent deletion.');
    }
    _gateway.assertActor(actorId);
    await ensureSchema();
    if (await LocalJobRetirement.isJobBlocked(_db, business, job)) {
      throw StateError('This Job already has a pending or completed deletion. Check sync status.');
    }
    Map<String, dynamic> value;
    if (online) {
      try {
        value = await _gateway.preview(business, job).timeout(_timeout);
      } on PostgrestException catch (error) {
        if (const ['PGRST202', '42883'].contains(error.code) &&
            error.message.contains('briskers_job_delete_preview_v3')) {
          throw const JobDeletionV3Unavailable();
        }
        rethrow;
      }
      _gateway.assertActor(actorId);
      validateDeletionV3Preview(value, business, job, actorId);
      if (value['can_delete'] == true && _expired(Map<String, dynamic>.from(value['confirmation'] as Map))) {
        throw const JobDeletionV3ReviewRequired();
      }
      await _db.customStatement('''INSERT INTO local_job_deletion_v3_previews
        (business_id,job_id,actor_id,preview_json,verified_at) VALUES (?,?,?,?,?)
        ON CONFLICT(business_id,job_id) DO UPDATE SET actor_id=excluded.actor_id,
        preview_json=excluded.preview_json,verified_at=excluded.verified_at''',
        [business, job, actorId, deletionV3Canonical(value), _clock().millisecondsSinceEpoch]);
    } else {
      final rows = await _db.customSelect('''SELECT preview_json FROM local_job_deletion_v3_previews
        WHERE business_id=? AND job_id=? AND actor_id=?''', variables: [
          Variable<String>(business), Variable<String>(job), Variable<String>(actorId),
        ]).get();
      if (rows.isEmpty) {
        await _db.customStatement('INSERT OR REPLACE INTO local_job_deletion_v3_intentions (business_id,job_id,actor_id) VALUES (?,?,?)', [business, job, actorId]);
        throw StateError('Deletion review requested. Connect and reopen Delete Job to review the exact records before confirming. Nothing has been deleted.');
      }
      value = Map<String, dynamic>.from(jsonDecode(rows.single.read<String>('preview_json')) as Map);
      validateDeletionV3Preview(value, business, job, actorId);
      if (value['can_delete'] == true && _expired(Map<String, dynamic>.from(value['confirmation'] as Map))) {
        throw StateError('Connect to refresh this deletion preview before confirming. Nothing has been deleted.');
      }
    }
    return JobDeletionV3Preview(value, fromCache: !online);
  }

  Future<JobDeletionV3Result> queueConfirmed(JobDeletionV3Preview preview,
      {required String actorId, required bool isOwner, bool online = true,
      bool noRealMoneyConfirmed = false}) async {
    if (!isOwner || !preview.canDelete) throw StateError('Deletion is not available.');
    _gateway.assertActor(actorId);
    final value = preview.snapshot;
    final business = value['business_id'] as String;
    final job = value['job_id'] as String;
    validateDeletionV3Preview(value, business, job, actorId);
    final requiresFinancialConsent = value['requires_synthetic_consent'] == true;
    if (requiresFinancialConsent && !noRealMoneyConfirmed) {
      throw StateError('You must separately confirm these are verified test-only financial records. Nothing has been deleted.');
    }
    // The corrected backend requires the extra flag ONLY after a human
    // explicitly consents; never infer it from a preview or silently default true.
    final confirmation = preview.confirmation;
    if (requiresFinancialConsent) {
      confirmation['no_real_money_confirmed'] = true;
    }
    if (_expired(confirmation)) throw const JobDeletionV3ReviewRequired();
    await ensureSchema();
    final operation = _newOperation();
    // Persist the immutable exact consent before the first network operation.
    // No old v2 request or snapshot is read or upgraded here.
    await _db.transaction(() async {
      if (await LocalJobRetirement.isJobBlocked(_db, business, job)) {
        throw StateError('This Job already has a pending or completed deletion.');
      }
      final existing = await _db.customSelect('''SELECT state FROM local_job_deletion_v3_requests
        WHERE business_id=? AND job_id=?''', variables: [Variable<String>(business), Variable<String>(job)]).get();
      if (existing.isNotEmpty && existing.single.read<String>('state') != 'rejected') {
        throw StateError('A deletion request already exists. Check sync status.');
      }
      await LocalJobDeletionV3.assertNoUnconfirmedLocalChanges(_db, business,
        (confirmation['deleted_entities'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      await _db.customStatement('''INSERT INTO local_job_deletion_v3_requests
        (business_id,job_id,operation_id,actor_id,confirmation_json,state,attempted)
        VALUES (?,?,?,?,?,'queued',0) ON CONFLICT(business_id,job_id) DO UPDATE SET
        operation_id=excluded.operation_id,actor_id=excluded.actor_id,
        confirmation_json=excluded.confirmation_json,state='queued',attempted=0,
        last_error=NULL,receipt_json=NULL''',
        [business, job, operation, actorId, deletionV3Canonical(confirmation)]);
      await _db.customStatement('DELETE FROM local_job_deletion_v3_intentions WHERE business_id=? AND job_id=?', [business, job]);
      await LocalJobDeletionV3.setPendingIntent(_db, businessId: business,
        jobId: job, operationId: operation, deletedEntities: (confirmation['deleted_entities'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map)).toList());
    });
    LocalSyncStatusRepository.notifyStateChanged(business);
    if (online) await flush(business);
    return status(business, job);
  }

  Future<JobDeletionV3Result> status(String business, String job) async {
    await ensureSchema();
    final rows = await _db.customSelect('''SELECT state,last_error FROM local_job_deletion_v3_requests
      WHERE business_id=? AND job_id=?''', variables: [Variable<String>(business), Variable<String>(job)]).get();
    if (rows.isEmpty) return const JobDeletionV3Result('none', 'No deletion request.');
    final row = rows.single;
    final state = row.read<String>('state');
    return JobDeletionV3Result(state, switch (state) {
      'deleted' => 'The Job and confirmed linked records were deleted.',
      'purging' => 'Deletion was accepted. Attachment and device cleanup is still pending.',
      'superseded' => 'This Job was deleted on another device. This request will not run again.',
      'rejected' => row.readNullable<String>('last_error') ?? 'Review deletion again. Nothing was deleted.',
      _ => 'Deletion is pending. The exact confirmed selection will be checked again when connected.',
    });
  }

  Future<void> flush(String business) {
    final flights = _flights[_db] ??= {};
    return flights[business] ??= _flush(business).whenComplete(() { flights.remove(business); });
  }

  Future<void> _flush(String business) async {
    await ensureSchema();
    final rows = await _db.customSelect('''SELECT * FROM local_job_deletion_v3_requests
      WHERE business_id=? AND state IN ('queued','pending','purging')''',
      variables: [Variable<String>(business)]).get();
    for (final row in rows) {
      final op = row.read<String>('operation_id');
      final job = row.read<String>('job_id');
      final actor = row.read<String>('actor_id');
      final confirmation = Map<String, dynamic>.from(jsonDecode(row.read<String>('confirmation_json')) as Map);
      try {
        _gateway.assertActor(actor);
        validateDeletionV3Confirmation(confirmation, business, job, actor);
        // A possibly committed operation always retries the SAME ID even after
        // consent expires; the server retrieves its receipt before expiry checks.
        if (row.read<int>('attempted') == 0 && _expired(confirmation)) {
          await _setState(business, op, 'rejected', 'This preview expired. Review a fresh preview before deleting.');
          continue;
        }
        if (row.read<int>('attempted') == 0) {
          try {
            await LocalJobDeletionV3.assertNoUnconfirmedLocalChanges(_db, business,
              (confirmation['deleted_entities'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
          } on StateError catch (error) {
            await _setState(business, op, 'rejected', error.message);
            continue;
          }
        }
        await _db.customStatement("UPDATE local_job_deletion_v3_requests SET state=CASE WHEN state='queued' THEN 'pending' ELSE state END,attempted=1 WHERE business_id=? AND operation_id=?", [business, op]);
        final receipt = await (row.readNullable<String>('receipt_json') == null
            ? _gateway.execute(business, job, op, confirmation)
            : _gateway.status(business, op)).timeout(_timeout);
        _gateway.assertActor(actor);
        validateDeletionV3Receipt(receipt, confirmation, op);
        final accepted = await _db.transaction(() async {
          final current = await _db.customSelect('SELECT state,receipt_json FROM local_job_deletion_v3_requests WHERE business_id=? AND operation_id=?',
            variables: [Variable<String>(business), Variable<String>(op)]).getSingle();
          if (current.read<String>('state') == 'deleted') return false;
          final priorRaw = current.readNullable<String>('receipt_json');
          if (priorRaw != null) {
            final prior = jsonDecode(priorRaw) as Map;
            if (prior['status_version'] > receipt['status_version']) return false;
            if ((prior['status'] == 'deleted' && receipt['status'] != 'deleted') ||
                prior['committed_at'] != receipt['committed_at'] ||
                (prior['status_version'] == receipt['status_version'] &&
                    deletionV3Canonical(prior) != deletionV3Canonical(receipt))) {
              throw const FormatException('Deletion receipt changed identity or status.');
            }
          }
          await _db.customStatement('''UPDATE local_job_deletion_v3_requests
            SET state='purging',receipt_json=?,last_error=NULL WHERE business_id=? AND operation_id=?''',
            [deletionV3Canonical(receipt), business, op]);
          return true;
        });
        if (!accepted) continue;
        await _db.customStatement('DELETE FROM local_job_deletion_v3_previews WHERE business_id=? AND job_id=?', [business, job]);
        final cleanup = await LocalJobDeletionV3.applyVerifiedReceipt(_db, receipt: receipt);
        // Local completion is required in addition to the server's status.
        if (receipt['status'] == 'deleted' && cleanup.complete) {
          await _setState(business, op, 'deleted', null);
        }
      } on PostgrestException catch (error) {
        if (row.readNullable<String>('receipt_json') != null || row.read<int>('attempted') != 0) {
          // A prior response may have been lost after commit. A later refusal
          // cannot prove nonexecution and must never permit a new operation.
          continue;
        }
        if (const ['42501', 'P0001', 'PGRST202', '42883'].contains(error.code)) {
          await _setState(business, op, 'rejected',
            const ['PGRST202', '42883'].contains(error.code)
              ? const JobDeletionV3Unavailable().toString()
              : 'Deletion was refused. Reconnect and review the current records before confirming again.');
        }
        // Transport/unknown outcome stays pending; never mint a new operation.
      } catch (_) {
        // A timeout, changed actor, invalid receipt or local cleanup failure
        // cannot be interpreted as proof that the server did not commit.
      }
    }
  }

  static final _pulls = Expando<Map<String, Future<void>>>('job_delete_v3_pull');
  Future<void> pullTombstones(String business) {
    final flights = _pulls[_db] ??= {};
    return flights[business] ??= _pullWithDiagnostics(business).whenComplete(() { flights.remove(business); });
  }

  Future<void> _pullWithDiagnostics(String business) async {
    try {
      await _pull(business);
    } catch (_) {
      await _db.customStatement('''INSERT INTO local_sync_states (business_id,scope,last_error,bootstrapped)
        VALUES (?,'job_deletions_v3','Deletion sync needs attention',0)
        ON CONFLICT(business_id,scope) DO UPDATE SET last_error=excluded.last_error''', [business]);
      LocalSyncStatusRepository.notifyStateChanged(business);
      rethrow;
    }
  }

  Future<void> _pull(String business) async {
    await ensureSchema();
    await _db.customStatement('''CREATE TABLE IF NOT EXISTS local_job_deletion_v3_feed (
      business_id TEXT PRIMARY KEY, visibility_scope TEXT NOT NULL,
      cursor INTEGER NOT NULL, observed INTEGER NOT NULL DEFAULT 0)''');
    final saved = await _db.customSelect('SELECT * FROM local_job_deletion_v3_feed WHERE business_id=?',
      variables: [Variable<String>(business)]).get();
    await _db.customStatement('CREATE TABLE IF NOT EXISTS local_job_deletion_origins_feed_version (business_id TEXT PRIMARY KEY)');
    final originsVersion = await _db.customSelect('SELECT business_id FROM local_job_deletion_origins_feed_version WHERE business_id=?',
      variables: [Variable<String>(business)]).get();
    // Older draft clients advanced UUID-only feeds. Replay once to learn
    // authoritative aliases too; existing UUID fences make this idempotent.
    var cursor = saved.isEmpty || originsVersion.isEmpty ? 0 : saved.single.read<int>('cursor');
    String? scope = saved.isEmpty ? null : saved.single.read<String>('visibility_scope');
    var scopeChanges = 0;
    while (true) {
      Map<String, dynamic> page;
      try {
        page = await _gateway.tombstones(business, cursor).timeout(_timeout);
      } on PostgrestException catch (error) {
        if (const ['PGRST202', '42883'].contains(error.code) &&
            error.message.contains('briskers_job_delete_tombstones_v3') && saved.isEmpty) {
          final evidence = await _db.customSelect('''SELECT
            (SELECT COUNT(*) FROM local_job_deletion_v3_requests WHERE business_id=?) +
            (SELECT COUNT(*) FROM local_job_deletion_v3_previews WHERE business_id=?) AS n''',
            variables: [Variable<String>(business), Variable<String>(business)]).getSingle();
          if (evidence.read<int>('n') == 0) return;
        }
        rethrow;
      }
      final nextScope = page['visibility_scope'];
      if (page['schema_version'] != 3 || page['protocol_version'] != ownerDeletionV3Protocol ||
          page['business_id'] != business || !isDeletionV3Id(page['actor_id']) ||
          !const ['staff', 'customer'].contains(page['reader_scope']) ||
          nextScope is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(nextScope)) {
        throw const FormatException('Unverified deletion reader scope.');
      }
      _gateway.assertActor(page['actor_id'] as String);
      final invalidated = await LocalJobDeletionV3.invalidateVisibilityScope(_db,
        businessId: business, actorId: page['actor_id'] as String,
        visibilityScope: nextScope, readerScope: page['reader_scope'] as String);
      if (invalidated) {
        await _db.customStatement(
          'DELETE FROM local_job_deletion_v3_previews WHERE business_id=?', [business]);
      }
      if (scope != nextScope && (scope != null || cursor != 0)) {
        if (++scopeChanges > 3) throw StateError('Access changed during deletion sync.');
        scope = nextScope; cursor = 0; continue;
      }
      scope = nextScope;
      final entries = page['tombstones'];
      final next = page['cursor'];
      if (entries is! List || entries.length > 200 || next is! int || next < cursor ||
          page['has_more'] is! bool ||
          (page['has_more'] == true && (entries.isEmpty || next == cursor))) {
        throw const FormatException('Invalid deletion feed page.');
      }
      var prior = cursor;
      for (final raw in entries) {
        if (raw is! Map || raw['business_id'] != business ||
            !isDeletionV3Id(raw['job_id']) || !isDeletionV3Id(raw['operation_id']) ||
            raw['scope_complete'] != true || raw['deleted_entities'] is! List ||
            raw['status_version'] is! int || (raw['status_version'] as int) < 1 || raw['cursor'] is! int ||
            (raw['cursor'] as int) <= prior || (raw['cursor'] as int) > next ||
            !const ['deleted', 'purging'].contains(raw['status']) ||
            (raw['status'] == 'deleted' && !const ['not_required', 'completed'].contains(raw['storage_cleanup'])) ||
            (raw['status'] == 'purging' && !const ['pending', 'failed'].contains(raw['storage_cleanup']))) {
          throw const FormatException('Incomplete deletion operation.');
        }
        final entities = raw['deleted_entities'] as List;
        final seen = <String>{};
        if (entities.isEmpty || entities.length > 1000) {
          throw const FormatException('Invalid operation inventory size.');
        }
        for (final entity in entities) {
          if (entity is! Map || entity.length != 2 ||
              !validDeletionV3Entity(entity['entity_kind'], entity['entity_id'], business) ||
              !seen.add('${entity['entity_kind']}:${entity['entity_id']}')) {
            throw const FormatException('Unverified feed identity.');
          }
        }
        prior = raw['cursor'] as int;
      }
      if ((entries.isNotEmpty && prior != next) || (entries.isEmpty && next != cursor)) {
        throw const FormatException('Unverified deletion cursor.');
      }
      final origins = entries.isEmpty ? <String,Map<String,dynamic>>{} : validateLocalDeletionOrigins(
        await _gateway.localOrigins(business, entries.map((e) => (e as Map)['operation_id'] as String).toList()).timeout(_timeout),
        businessId: business, actorId: page['actor_id'] as String, visibilityScope: nextScope,
        operations: entries.map((e) => Map<String,dynamic>.from(e as Map)).toList());
      _gateway.assertActor(page['actor_id'] as String);
      // Each operation commits its permanent fences before filesystem cleanup.
      // Do not wrap that cleanup in an outer transaction that could roll back
      // the markers after irreversible file removal.
      for (final raw in entries) {
        _gateway.assertActor(page['actor_id'] as String);
        await LocalJobDeletionV3.applyVerifiedTombstone(_db, Map<String, dynamic>.from(raw as Map));
        await LocalJobDeletionV3.applyVerifiedLocalOrigin(_db, businessId: business,
          origin: origins[raw['operation_id']]!);
        await _db.customStatement('''UPDATE local_job_deletion_v3_requests SET state='superseded',last_error=NULL
          WHERE business_id=? AND job_id=? AND operation_id<>? AND state IN ('queued','pending')''',
          [business, raw['job_id'], raw['operation_id']]);
      }
      await _db.transaction(() async {
        _gateway.assertActor(page['actor_id'] as String);
        await _db.customStatement('''INSERT INTO local_job_deletion_v3_feed
          (business_id,visibility_scope,cursor,observed) VALUES (?,?,?,1)
          ON CONFLICT(business_id) DO UPDATE SET visibility_scope=excluded.visibility_scope,
          cursor=excluded.cursor,observed=1''', [business, nextScope, next]);
      });
      await _db.customStatement('''INSERT INTO local_sync_states
        (business_id,scope,last_server_cursor,last_pull_at,bootstrapped)
        VALUES (?,'job_deletions_v3',?,?,1) ON CONFLICT(business_id,scope) DO UPDATE SET
        last_server_cursor=excluded.last_server_cursor,last_pull_at=excluded.last_pull_at,
        bootstrapped=1,last_error=NULL''', [business, next, _clock().toUtc().millisecondsSinceEpoch ~/ 1000]);
      LocalSyncStatusRepository.notifyStateChanged(business);
      cursor = next;
      if (page['has_more'] != true) {
        await _db.customStatement('INSERT OR IGNORE INTO local_job_deletion_origins_feed_version(business_id) VALUES (?)',[business]);
        break;
      }
    }
    await LocalJobDeletionV3.resumePendingCleanup(_db, business);
  }

  Future<void> _setState(String business, String op, String state, String? error) async {
    await _db.transaction(() async {
      final current = await _db.customSelect('SELECT state,receipt_json,job_id FROM local_job_deletion_v3_requests WHERE business_id=? AND operation_id=?',
        variables: [Variable<String>(business), Variable<String>(op)]).get();
      if (current.isEmpty) return;
      final priorState = current.single.read<String>('state');
      if (state == 'rejected' && await LocalJobDeletionV3.isEntityDeleted(
          _db, business, 'job', current.single.read<String>('job_id'))) {
        return;
      }

      if (priorState == 'deleted' || priorState == 'superseded' ||
          (state == 'rejected' && (priorState == 'purging' || current.single.readNullable<String>('receipt_json') != null))) {
        return;
      }
      await _db.customStatement('UPDATE local_job_deletion_v3_requests SET state=?,last_error=? WHERE business_id=? AND operation_id=?', [state, error, business, op]);
      if (state == 'rejected') {
        await LocalJobDeletionV3.releasePendingIntent(_db, business, op);
      }
    });
    LocalSyncStatusRepository.notifyStateChanged(business);
  }
}

String _newOperation() {
  final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
}
