import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_job_quarantine.dart';
import 'local_job_retirement.dart';
import 'owner_job_retirement_service.dart';
import 'test_job_cleanup_gateway.dart';
import 'test_job_cleanup_policy.dart';

class JobSyncService {
  JobSyncService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
    TestJobCleanupGateway cleanupGateway = const TestJobCleanupGateway(),
    OwnerJobRetirementGateway retirementGateway =
        const OwnerJobRetirementGateway(),
  }) : _api = api,
       _retirement = OwnerJobRetirementService(
         database: database,
         gateway: retirementGateway,
       ),
       _cleanupGateway = cleanupGateway,
       _database = database ?? localDatabase;

  static const _scope = 'jobs';
  static final StreamController<String> _syncEvents =
      StreamController<String>.broadcast();

  static Stream<String> get syncEvents => _syncEvents.stream;

  /// Refresh existing listeners after a verified, server-committed cleanup.
  static void notifyCleanup(String businessId) => _syncEvents.add(businessId);

  final BriskersApi _api;
  final OwnerJobRetirementService _retirement;
  final TestJobCleanupGateway _cleanupGateway;
  final BriskersLocalDatabase _database;

  /// Prune only jobs missing from a verified full server snapshot.
  /// Refuse cleanup when a stale job still owns locally cached photo files.
  Future<int> pruneObsoleteCache(
    String businessId,
    Set<String> serverJobIds,
  ) async {
    final rows = await _database
        .customSelect(
          'SELECT id, vehicle_id FROM local_jobs WHERE business_id = ?',
          variables: [Variable<String>(businessId)],
        )
        .get();
    final blocked = await LocalJobRetirement.blockedJobIds(
      _database,
      businessId,
    );
    final obsolete = rows
        .where(
          (row) =>
              !serverJobIds.contains(row.read<String>('id')) &&
              !blocked.contains(row.read<String>('id')),
        )
        .toList();

    // A full import must never silently delete device-only photo files.
    // Check every stale job before making any destructive changes.
    for (final row in obsolete) {
      final jobId = row.read<String>('id');
      final vehicleId = row.readNullable<String>('vehicle_id');
      final inspectionPhotos = await _database
          .customSelect(
            '''
        SELECT COUNT(*) AS count
        FROM local_pre_inspection_photos p
        JOIN local_pre_inspections i
          ON i.business_id = p.business_id
         AND i.id = p.inspection_id
        WHERE i.business_id = ? AND i.job_id = ?
          AND p.local_file_path IS NOT NULL AND p.local_file_path <> ''
        ''',
            variables: [Variable<String>(businessId), Variable<String>(jobId)],
          )
          .getSingle();
      if (inspectionPhotos.read<int>('count') > 0) {
        throw StateError(
          'Old job $jobId has locally stored photos. '
          'Import or back them up before repairing this device.',
        );
      }
      if (vehicleId != null && vehicleId.isNotEmpty) {
        final findingPhotos = await _database
            .customSelect(
              '''
          SELECT COUNT(*) AS count
          FROM local_finding_photos p
          JOIN local_findings f
            ON f.business_id = p.business_id
           AND f.id = p.finding_id
          WHERE f.business_id = ? AND f.vehicle_id = ?
            AND p.local_file_path IS NOT NULL AND p.local_file_path <> ''
          ''',
              variables: [
                Variable<String>(businessId),
                Variable<String>(vehicleId),
              ],
            )
            .getSingle();
        if (findingPhotos.read<int>('count') > 0) {
          throw StateError(
            'Old job $jobId has locally cached finding photos. '
            'Import or back them up before repairing this device.',
          );
        }
      }
    }

    await _database.transaction(() async {
      for (final row in obsolete) {
        await _removeJob(businessId, row.read<String>('id'));
      }
    });
    if (obsolete.isNotEmpty) _syncEvents.add(businessId);
    return obsolete.length;
  }

  Future<void> pull(String businessId) async {
    await _retirement.pullTombstones(businessId);
    int? cursor;
    var bootstrapped = false;

    final stateRows = await _database
        .customSelect(
          '''
      SELECT last_server_cursor, bootstrapped
      FROM local_sync_states
      WHERE business_id = ? AND scope = ?
      LIMIT 1
      ''',
          variables: [
            Variable<String>(businessId),
            const Variable<String>(_scope),
          ],
        )
        .get();

    if (stateRows.isNotEmpty) {
      final state = stateRows.first;
      cursor = state.readNullable<int>('last_server_cursor');
      bootstrapped = (state.read<int>('bootstrapped')) == 1;
    }

    if (!bootstrapped) {
      await _bootstrapPaged(businessId);
      _syncEvents.add(businessId);
      return;
    }

    try {
      var hasMore = true;
      var pageCursor = cursor;

      while (hasMore) {
        final beforeSnapshot = await _snapshotBaseline(businessId);
        final requestGeneration = await LocalJobQuarantine.captureGeneration(
          _database,
          businessId,
        );
        final response = await _api.syncPullJobs(
          businessId,
          afterCursor: pageCursor,
        );

        final retired = await LocalJobRetirement.blockedJobIds(
          _database,
          businessId,
        );
        final mode = response['mode']?.toString() ?? 'incremental';
        final bundles = List<dynamic>.from(
          response['bundles'] ?? const <dynamic>[],
        );
        final revokedIds = List<dynamic>.from(
          response['revoked_job_ids'] ?? const <dynamic>[],
        ).map((value) => value.toString()).toList();

        final nextCursor =
            int.tryParse(response['next_cursor']?.toString() ?? '') ??
            pageCursor ??
            0;
        hasMore = response['has_more'] == true;

        // Positive revocation evidence hides active records BEFORE attempting
        // the separately fallible cleanup classification request.
        final quarantined = revokedIds
            .where((id) => id.isNotEmpty && !retired.contains(id))
            .toSet();
        if (mode == 'bootstrap') {
          if (response['has_more'] != false) {
            throw StateError('Server Job reset is not a complete snapshot.');
          }
          quarantined.addAll(
            await _snapshotAbsentIds(
              businessId,
              _verifiedSnapshotIds(bundles, businessId),
              beforeSnapshot,
            ),
          );
        }
        await _quarantineRevoked(businessId, quarantined);
        await _retirement.pullTombstones(businessId);
        final classificationGeneration =
            await LocalJobQuarantine.captureGeneration(_database, businessId);
        final cleanup = TestJobCleanupTombstones.fromJson(
          await _cleanupGateway.tombstones(businessId),
          businessId,
        );
        await _quarantineRevoked(
          businessId,
          cleanup.jobIds
              .intersection(beforeSnapshot.keys.toSet())
              .difference(quarantined),
        );
        await LocalJobQuarantine.classifyJobs(
          _database,
          businessId,
          await LocalJobQuarantine.unclassifiedJobIds(_database, businessId),
          cleanupJobIds: cleanup.jobIds,
          observedGeneration: classificationGeneration,
        );

        await _database.transaction(() async {
          if (mode == 'bootstrap') {
            await _clearBusinessJobCache(businessId);
          }

          for (final raw in bundles) {
            if (raw is! Map) continue;
            final rawJob = raw['job'];
            if (rawJob is Map && cleanup.jobIds.contains(rawJob['id'])) {
              continue;
            }
            await _applyBundle(
              businessId,
              Map<String, dynamic>.from(raw),
              requestGeneration: requestGeneration,
            );
          }

          await _writeSyncState(
            businessId,
            cursor: nextCursor,
            bootstrapped: true,
            error: null,
          );
        });

        pageCursor = nextCursor;

        if (mode == 'bootstrap') {
          hasMore = false;
        }
      }
      _syncEvents.add(businessId);
    } catch (error) {
      await _writeSyncState(
        businessId,
        cursor: cursor,
        bootstrapped: bootstrapped,
        error: error.toString(),
      );
      rethrow;
    }
  }

  /// A transient 401/session-refresh or SQL timeout should not discard
  /// progress on a large first-device download after one failed page.
  Future<Map<String, dynamic>> _fetchBootstrapPage(
    String businessId,
    String? afterJobId,
  ) async {
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        return await _api.syncPullJobsBootstrap(
          businessId,
          afterJobId: afterJobId,
          limit: 25,
        );
      } catch (error) {
        final message = error.toString().toLowerCase();
        final retryable =
            message.contains('42501') ||
            message.contains('unauthorized') ||
            message.contains('57014') ||
            message.contains('timeout') ||
            message.contains('connection reset') ||
            message.contains('socketexception') ||
            message.contains('503');
        if (!retryable || attempt == 4) rethrow;
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }
    throw StateError('Job bootstrap retry limit reached.');
  }

  /// Initial bootstrap is intentionally separated from incremental pulls.
  /// The legacy v1 endpoint ignored its page size for initial downloads and
  /// timed out while assembling thousands of historical service jobs.
  Future<void> _bootstrapPaged(String businessId) async {
    String? afterJobId;
    int? initialCursor;
    final completeBundles = <Map<String, dynamic>>[];
    final completeIds = <String>{};
    var pageCount = 0;
    var hasMore = true;

    try {
      final beforeSnapshot = await _snapshotBaseline(businessId);
      final requestGeneration = await LocalJobQuarantine.captureGeneration(
        _database,
        businessId,
      );
      while (hasMore) {
        if (++pageCount > 10000) {
          throw StateError('Job bootstrap exceeded page safety limit.');
        }
        final response = await _fetchBootstrapPage(businessId, afterJobId);
        if (response['mode']?.toString() != 'bootstrap') {
          throw StateError('Invalid server job bootstrap response.');
        }
        final currentCursor = int.tryParse(
          response['bootstrap_cursor']?.toString() ?? '',
        );
        if (currentCursor == null) {
          throw StateError('Job bootstrap cursor is missing.');
        }
        // Use the *first* snapshot cursor. Changes made after that time
        // will be replayed by the next incremental download.
        initialCursor ??= currentCursor;

        final rawBundles = response['bundles'];
        if (rawBundles is! List ||
            rawBundles.length > 25 ||
            response['has_more'] is! bool) {
          throw StateError('Invalid job bootstrap batch size.');
        }
        final bundles = List<dynamic>.from(rawBundles);
        hasMore = response['has_more'] == true;
        final nextJobId = response['next_job_id']?.toString() ?? '';
        if (hasMore &&
            (nextJobId.isEmpty || nextJobId == afterJobId || bundles.isEmpty)) {
          throw StateError('Job bootstrap continuation is incomplete.');
        }

        final pageIds = _verifiedSnapshotIds(bundles, businessId);
        if (pageIds.any(completeIds.contains)) {
          throw StateError('Job bootstrap repeated a record.');
        }
        completeIds.addAll(pageIds);
        completeBundles.addAll(
          bundles.map((raw) => Map<String, dynamic>.from(raw as Map)),
        );
        afterJobId = nextJobId.isEmpty ? null : nextJobId;
      }

      // Only the final validated page proves absence. Never revoke a Job
      // merely because it is missing from page one of a keyset bootstrap.
      final quarantined = await _snapshotAbsentIds(
        businessId,
        completeIds,
        beforeSnapshot,
      );
      await _quarantineRevoked(businessId, quarantined);
      await _retirement.pullTombstones(businessId);
      final classificationGeneration =
          await LocalJobQuarantine.captureGeneration(_database, businessId);
      final cleanup = TestJobCleanupTombstones.fromJson(
        await _cleanupGateway.tombstones(businessId),
        businessId,
      );
      await _quarantineRevoked(
        businessId,
        cleanup.jobIds
            .intersection(beforeSnapshot.keys.toSet())
            .difference(quarantined),
      );
      await LocalJobQuarantine.classifyJobs(
        _database,
        businessId,
        await LocalJobQuarantine.unclassifiedJobIds(_database, businessId),
        cleanupJobIds: cleanup.jobIds,
        observedGeneration: classificationGeneration,
      );
      await _database.transaction(() async {
        await _clearBusinessJobCache(businessId);
        for (final bundle in completeBundles) {
          final job = bundle['job'] as Map;
          if (cleanup.jobIds.contains(job['id'])) continue;
          await _applyBundle(
            businessId,
            bundle,
            requestGeneration: requestGeneration,
          );
        }
      });
      await _writeSyncState(
        businessId,
        cursor: initialCursor ?? 0,
        bootstrapped: true,
        error: null,
      );

      // Sync concurrent edits from the first page's snapshot onward.
      // A normal subsequent Sync now call also replays these changes.
    } catch (error) {
      await _writeSyncState(
        businessId,
        cursor: null,
        bootstrapped: false,
        error: error.toString(),
      );
      rethrow;
    }
  }

  Set<String> _verifiedSnapshotIds(List<dynamic> bundles, String businessId) {
    final result = <String>{};
    for (final bundle in bundles) {
      if (bundle is! Map || bundle['job'] is! Map) {
        throw StateError('Incomplete Job snapshot cannot revoke local access.');
      }
      final job = bundle['job'] as Map;
      final id = job['id'];
      if (id is! String ||
          id.isEmpty ||
          !result.add(id) ||
          (job['business_id'] != null && job['business_id'] != businessId)) {
        throw StateError(
          'Job snapshot identity or business cannot be verified.',
        );
      }
    }
    return result;
  }

  Future<Map<String, String>> _snapshotBaseline(String businessId) async {
    final rows = await _database
        .customSelect(
          'SELECT id,row_version,server_updated_at FROM local_jobs WHERE business_id=?',
          variables: [Variable<String>(businessId)],
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('id'):
            '${row.data['row_version']}|${row.data['server_updated_at']}',
    };
  }

  Future<void> _quarantineRevoked(String businessId, Set<String> ids) async {
    if (ids.isEmpty) return;
    await LocalJobQuarantine.quarantineJobs(_database, businessId, ids);
    _syncEvents.add(businessId);
  }

  Future<Set<String>> _snapshotAbsentIds(
    String businessId,
    Set<String> serverIds,
    Map<String, String> beforeSnapshot,
  ) async {
    final absent = <String>{};
    final retired = await LocalJobRetirement.blockedJobIds(
      _database,
      businessId,
    );
    final rows = await _database
        .customSelect(
          """SELECT j.id,j.sync_state,j.row_version,j.server_updated_at,
             EXISTS(SELECT 1 FROM sync_outbox o WHERE o.business_id=j.business_id
               AND o.entity_id=j.id AND o.entity_type='job_create') AS local_create
           FROM local_jobs j WHERE j.business_id=?""",
          variables: [Variable<String>(businessId)],
        )
        .get();
    for (final row in rows) {
      final id = row.read<String>('id');
      if (serverIds.contains(id) || retired.contains(id)) continue;
      // Keyset pages are not one transaction. A newly synced identity may
      // sort before an already-read page; absence cannot revoke its work.
      final provenance =
          '${row.data['row_version']}|${row.data['server_updated_at']}';
      if (!beforeSnapshot.containsKey(id) || beforeSnapshot[id] != provenance) {
        continue;
      }
      // A never-uploaded creation cannot appear in a server snapshot yet.
      // Its stable ID and queued work must remain recoverable.
      if (row.read<int>('local_create') != 0 ||
          id.startsWith('local-') ||
          (row.read<String>('sync_state') != 'synced' &&
              row.data['row_version'] == null &&
              row.data['server_updated_at'] == null)) {
        continue;
      }
      absent.add(id);
    }
    return absent;
  }

  Future<void> _clearBusinessJobCache(String businessId) async {
    // The first-page bootstrap precheck alone is insufficient: pending work
    // can arrive while the network request runs, or be missing its queue row.
    // Check again inside the transaction for every full-cache reset path.
    final dirty = await _database.customSelect(
      """SELECT
        (SELECT COUNT(*) FROM sync_outbox WHERE business_id=? AND state<>'cancelled') +
        (SELECT COUNT(*) FROM local_jobs j WHERE business_id=? AND sync_state IS NOT 'synced'
          AND NOT EXISTS(SELECT 1 FROM local_job_retirement_entities e WHERE e.business_id=j.business_id
            AND e.entity_kind='job' AND e.entity_id=j.id AND e.state='locally_cancelled')) +
        (SELECT COUNT(*) FROM local_job_visits WHERE business_id=? AND sync_state IS NOT 'synced') +
        (SELECT COUNT(*) FROM local_pre_inspections WHERE business_id=? AND sync_state IS NOT 'synced') +
        (SELECT COUNT(*) FROM local_findings WHERE business_id=? AND sync_state IS NOT 'synced') +
        (SELECT COUNT(*) FROM local_pre_inspection_photos WHERE business_id=?
          AND (upload_state IS NOT 'synced' OR COALESCE(local_file_path,'')<>'')) +
        (SELECT COUNT(*) FROM local_finding_photos WHERE business_id=?
          AND (upload_state IS NOT 'synced' OR COALESCE(local_file_path,'')<>'')) AS n""",
      variables: List.generate(7, (_) => Variable<String>(businessId)),
    ).getSingle();
    if (dirty.read<int>('n') != 0) {
      throw StateError(
        'Job cache rebuild is blocked by local work or photos. '
        'They have been preserved for reconciliation.',
      );
    }
    for (final table in const [
      'local_pre_inspection_photos',
      'local_pre_inspections',
      'local_finding_photos',
      'local_job_visits',
      'local_job_assignments',
      'local_findings',
      'local_jobs',
    ]) {
      final retained = switch (table) {
        'local_jobs' => 'id',
        'local_job_visits' ||
        'local_job_assignments' ||
        'local_pre_inspections' => 'job_id',
        _ => null,
      };
      // Shared findings/photos are never erased as a consequence of retirement.
      if (retained == null &&
          (await LocalJobRetirement.blockedJobIds(
            _database,
            businessId,
          )).isNotEmpty) {
        continue;
      }
      await _database.customStatement(
        'DELETE FROM $table WHERE business_id = ?${retained == null ? '' : " AND NOT EXISTS(SELECT 1 FROM local_job_retirement_entities e WHERE e.business_id=$table.business_id "
                  "AND e.entity_kind='job' AND e.entity_id=$table.$retained AND e.state IN ${LocalJobRetirement.blockedStates})"}',
        [businessId],
      );
    }
  }

  Future<void> _applyBundle(
    String businessId,
    Map<String, dynamic> bundle, {
    required int requestGeneration,
  }) async {
    final rawJob = bundle['job'];
    if (rawJob is! Map) return;

    final job = Map<String, dynamic>.from(rawJob);
    final jobId = job['id']?.toString() ?? '';
    if (jobId.isEmpty) return;
    if (await LocalJobRetirement.isJobBlocked(_database, businessId, jobId)) {
      return;
    }
    if (!await LocalJobQuarantine.authorizeFreshJob(
      _database,
      businessId,
      jobId,
      requestGeneration: requestGeneration,
    )) {
      throw const LocalJobQuarantineException(
        'Job authorization changed during this download. Retry a fresh authorized pull.',
      );
    }

    // A pull may arrive before a queued status change can be uploaded. Keep
    // that local projection (including its actual completion time), while
    // still accepting server versions and unrelated authoritative fields.
    final pendingAdmin = await _database
        .customSelect(
          "SELECT payload_json FROM sync_outbox WHERE business_id = ? "
          "AND entity_id = ? AND entity_type = 'job_admin' AND state = 'pending'",
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();
    final preserveStatus = pendingAdmin.any((row) {
      try {
        final payload = jsonDecode(row.read<String>('payload_json'));
        return payload is Map && payload['status_changed'] == true;
      } catch (_) {
        return false;
      }
    });

    final vehicleId = _text(job['vehicle_id']);

    final preserveInspection = await _hasDirtyInspection(businessId, jobId);
    final preserveWork = await _hasDirtyWork(businessId, jobId);
    final preserveFindings = vehicleId == null
        ? false
        : await _hasDirtyFindings(businessId, vehicleId);

    await _removeJobChildren(
      businessId,
      jobId,
      keepJob: true,
      preserveInspection: preserveInspection,
      preserveWork: preserveWork,
    );

    final capabilities = job['capabilities'] is Map
        ? Map<String, dynamic>.from(job['capabilities'] as Map)
        : const <String, dynamic>{};
    final isUnassigned = job['is_unassigned'] == true;
    final accessScope = capabilities['manage_job'] == true
        ? 'full'
        : isUnassigned && capabilities['request_job'] == true
        ? 'available'
        : 'assigned';

    final assignments = List<dynamic>.from(
      job['assignments'] ?? const <dynamic>[],
    );
    Map<String, dynamic>? primaryAssignment;
    if (assignments.isNotEmpty && assignments.first is Map) {
      primaryAssignment = Map<String, dynamic>.from(assignments.first as Map);
    }

    await _database.customStatement(
      '''
      INSERT INTO local_jobs (
        id, business_id, access_scope, job_number, title, requested_work,
        status, status_name, status_color, status_icon,
        customer_id, customer_name, customer_problem_flag,
        customer_problem_flag_note, capabilities_json,
        pending_request_count, payment_state,
        vehicle_id, vehicle_label, vehicle_vin, vehicle_plate,
        planned_hours, odometer_in,
        assigned_employee_id, assigned_employee_name, assigned_position,
        is_unassigned, created_at, completed_at, server_updated_at,
        row_version, sync_state
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced'
      )
      ON CONFLICT(id) DO UPDATE SET
        business_id=excluded.business_id,
        access_scope=excluded.access_scope,
        job_number=excluded.job_number,
        title=excluded.title,
        requested_work=excluded.requested_work,
        status=${preserveStatus ? 'local_jobs.status' : 'excluded.status'},
        status_name=${preserveStatus ? 'local_jobs.status_name' : 'excluded.status_name'},
        status_color=${preserveStatus ? 'local_jobs.status_color' : 'excluded.status_color'},
        status_icon=${preserveStatus ? 'local_jobs.status_icon' : 'excluded.status_icon'},
        customer_id=excluded.customer_id,
        customer_name=excluded.customer_name,
        customer_problem_flag=excluded.customer_problem_flag,
        customer_problem_flag_note=excluded.customer_problem_flag_note,
        capabilities_json=excluded.capabilities_json,
        pending_request_count=excluded.pending_request_count,
        payment_state=coalesce(excluded.payment_state, local_jobs.payment_state),
        vehicle_id=excluded.vehicle_id,
        vehicle_label=excluded.vehicle_label,
        vehicle_vin=excluded.vehicle_vin,
        vehicle_plate=excluded.vehicle_plate,
        planned_hours=excluded.planned_hours,
        odometer_in=excluded.odometer_in,
        assigned_employee_id=excluded.assigned_employee_id,
        assigned_employee_name=excluded.assigned_employee_name,
        assigned_position=excluded.assigned_position,
        is_unassigned=excluded.is_unassigned,
        created_at=excluded.created_at,
        completed_at=${preserveStatus ? 'local_jobs.completed_at' : 'excluded.completed_at'},
        server_updated_at=excluded.server_updated_at,
        row_version=excluded.row_version,
        sync_state='${preserveStatus ? 'pending' : 'synced'}'
      ''',
      [
        jobId,
        businessId,
        accessScope,
        _text(job['job_number']),
        job['title']?.toString() ?? 'Job',
        _text(job['requested_work']),
        job['status']?.toString() ?? 'open',
        _text(job['status_name']),
        _text(job['status_color']),
        _text(job['status_icon']),
        _text(job['customer_id']),
        _text(job['customer_name']),
        job['customer_problem_flag'] == true ? 1 : 0,
        _text(job['customer_problem_flag_note']),
        jsonEncode(capabilities),
        List<dynamic>.from(job['pending_requests'] ?? const <dynamic>[]).length,
        _text(job['payment_state']),
        vehicleId,
        _text(job['vehicle']),
        _text(job['vehicle_vin']),
        _text(job['vehicle_plate']),
        _double(job['planned_hours']) ?? 0,
        _double(job['odometer_in']),
        _text(primaryAssignment?['employee_id']),
        _text(primaryAssignment?['employee_name']),
        _text(primaryAssignment?['position']),
        isUnassigned ? 1 : 0,
        _unix(_date(job['created_at'])),
        _unix(_date(job['completed_at'])),
        _unix(_date(job['updated_at'])),
        _int(job['row_version']),
      ],
    );

    for (final raw in assignments) {
      if (raw is! Map) continue;
      final assignment = Map<String, dynamic>.from(raw);
      final assignmentId = assignment['assignment_id']?.toString() ?? '';
      final employeeId = assignment['employee_id']?.toString() ?? '';
      if (assignmentId.isEmpty || employeeId.isEmpty) continue;

      await _database.customStatement(
        '''
        INSERT OR REPLACE INTO local_job_assignments (
          assignment_id, business_id, job_id, employee_id,
          employee_name, position, active, assigned_at,
          released_at, source
        ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
        ''',
        [
          assignmentId,
          businessId,
          jobId,
          employeeId,
          _text(assignment['employee_name']),
          _text(assignment['position']),
          _unix(_date(assignment['assigned_at'])),
          _unix(_date(assignment['released_at'])),
          _text(assignment['source']),
        ],
      );
    }

    final visits = List<dynamic>.from(job['visits'] ?? const <dynamic>[]);
    if (!preserveWork) {
      for (final raw in visits) {
        if (raw is! Map) continue;
        final visit = Map<String, dynamic>.from(raw);
        final visitId = visit['id']?.toString() ?? '';
        if (visitId.isEmpty) continue;

        await _database.customStatement(
          '''
        INSERT OR REPLACE INTO local_job_visits (
          id, business_id, job_id, visit_number, reason,
          planned_hours, work_summary, opened_at, closed_at,
          server_updated_at, row_version, sync_state
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
        ''',
          [
            visitId,
            businessId,
            jobId,
            _int(visit['visit_number']) ?? 0,
            _text(visit['reason']),
            _double(visit['planned_hours']) ?? 0,
            _text(visit['work_summary']),
            _unix(_date(visit['opened_at'])),
            _unix(_date(visit['closed_at'])),
            _unix(_date(visit['updated_at'])),
            _int(visit['row_version']),
          ],
        );
      }
    }

    final rawInspection = bundle['pre_inspection'];
    if (!preserveInspection && rawInspection is Map) {
      final inspection = Map<String, dynamic>.from(rawInspection);
      final inspectionId = inspection['id']?.toString() ?? '';
      if (inspectionId.isNotEmpty) {
        await _database.customStatement(
          '''
          INSERT OR REPLACE INTO local_pre_inspections (
            id, business_id, job_id, vehicle_id, inspected_at,
            odometer, notes, created_by, server_updated_at,
            row_version, sync_state
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
          ''',
          [
            inspectionId,
            businessId,
            jobId,
            _text(inspection['vehicle_id']),
            _unix(_date(inspection['inspected_at'])),
            _double(inspection['odometer']),
            _text(inspection['notes']),
            _text(inspection['created_by']),
            _unix(_date(inspection['updated_at'])),
            _int(inspection['row_version']),
          ],
        );

        final photos = List<dynamic>.from(
          inspection['photos'] ?? const <dynamic>[],
        );
        for (final raw in photos) {
          if (raw is! Map) continue;
          final photo = Map<String, dynamic>.from(raw);
          final photoId = photo['id']?.toString() ?? '';
          final attachmentId = photo['attachment_id']?.toString() ?? '';
          if (photoId.isEmpty || attachmentId.isEmpty) continue;

          await _database.customStatement(
            '''
            INSERT OR REPLACE INTO local_pre_inspection_photos (
              id, business_id, inspection_id, attachment_id,
              local_file_path, storage_bucket, storage_key, filename,
              mime_type, byte_size, captured_at, note, created_by,
              can_edit_note, can_delete, upload_state, last_error
            ) VALUES (
              ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?,
              ?, ?, 'synced', NULL
            )
            ''',
            [
              photoId,
              businessId,
              inspectionId,
              attachmentId,
              _text(photo['bucket']),
              _text(photo['key']),
              _text(photo['filename']),
              _text(photo['mime_type']),
              _int(photo['byte_size']),
              _unix(_date(photo['captured_at'])),
              _text(photo['note']),
              _text(photo['created_by']),
              photo['can_edit_note'] == true ? 1 : 0,
              photo['can_delete'] == true ? 1 : 0,
            ],
          );
        }
      }
    }

    if (vehicleId != null && !preserveFindings) {
      await _database.customStatement(
        '''
        DELETE FROM local_finding_photos
        WHERE business_id = ?
          AND finding_id IN (
            SELECT id
            FROM local_findings
            WHERE business_id = ? AND vehicle_id = ?
          )
        ''',
        [businessId, businessId, vehicleId],
      );
      await _database.customStatement(
        '''
        DELETE FROM local_findings
        WHERE business_id = ? AND vehicle_id = ?
        ''',
        [businessId, vehicleId],
      );

      final findings = List<dynamic>.from(
        bundle['findings'] ?? const <dynamic>[],
      );
      for (final raw in findings) {
        if (raw is! Map) continue;
        final finding = Map<String, dynamic>.from(raw);
        final findingId = finding['id']?.toString() ?? '';
        if (findingId.isEmpty) continue;
        // A vehicle-wide bundle can include a finding owned by another Job
        // whose access was revoked. Do not let that row abort unrelated sync.
        if (await LocalJobQuarantine.isEntityBlocked(_database, businessId, [
          findingId,
          _text(finding['found_job_id']),
          _text(finding['repair_job_id']),
        ])) {
          continue;
        }

        await _database.customStatement(
          '''
          INSERT OR REPLACE INTO local_findings (
            id, business_id, vehicle_id, found_job_id, repair_job_id,
            body, status, include_on_invoice, created_at, resolved_at,
            created_by, can_edit, can_delete, server_updated_at,
            row_version, sync_state
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
          ''',
          [
            findingId,
            businessId,
            vehicleId,
            _text(finding['found_job_id']),
            _text(finding['repair_job_id']),
            finding['body']?.toString() ?? '',
            finding['status']?.toString() ?? 'open',
            finding['include_on_invoice'] == true ? 1 : 0,
            _unix(_date(finding['created_at'])),
            _unix(_date(finding['resolved_at'])),
            _text(finding['created_by']),
            finding['can_edit'] == true ? 1 : 0,
            finding['can_delete'] == true ? 1 : 0,
            _unix(_date(finding['updated_at'])),
            _int(finding['row_version']),
          ],
        );

        final attachments = List<dynamic>.from(
          finding['attachments'] ?? const <dynamic>[],
        );
        for (final rawAttachment in attachments) {
          if (rawAttachment is! Map) continue;
          final attachment = Map<String, dynamic>.from(rawAttachment);
          final attachmentId = attachment['attachment_id']?.toString() ?? '';
          if (attachmentId.isEmpty) continue;

          await _database.customStatement(
            '''
            INSERT OR REPLACE INTO local_finding_photos (
              id, business_id, finding_id, attachment_id,
              local_file_path, storage_bucket, storage_key, filename,
              mime_type, byte_size, captured_at, can_delete,
              upload_state, last_error
            ) VALUES (
              ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, 'synced', NULL
            )
            ''',
            [
              attachmentId,
              businessId,
              findingId,
              attachmentId,
              _text(attachment['bucket']),
              _text(attachment['key']),
              _text(attachment['filename']),
              _text(attachment['mime_type']),
              _int(attachment['byte_size']),
              _unix(_date(attachment['captured_at'] ?? finding['created_at'])),
              attachment['can_delete'] == true ? 1 : 0,
            ],
          );
        }
      }
    }
  }

  Future<void> _removeJob(String businessId, String jobId) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT vehicle_id
      FROM local_jobs
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();

    final vehicleId = rows.isEmpty
        ? null
        : rows.first.readNullable<String>('vehicle_id');

    final photoRows = await _database
        .customSelect(
          '''
      SELECT p.local_file_path
      FROM local_pre_inspection_photos p
      JOIN local_pre_inspections i
        ON i.business_id = p.business_id
       AND i.id = p.inspection_id
      WHERE i.business_id = ?
        AND i.job_id = ?
        AND p.local_file_path IS NOT NULL
        AND p.local_file_path <> ''
      ''',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();

    final localFiles = photoRows
        .map((row) => row.readNullable<String>('local_file_path'))
        .whereType<String>()
        .toSet();

    final outboxRows = await _database
        .customSelect(
          '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
      ''',
          variables: [Variable<String>(businessId)],
        )
        .get();

    final revokedOutboxIds = <int>[];
    for (final row in outboxRows) {
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );
        if (payload['job_id']?.toString() == jobId) {
          revokedOutboxIds.add(row.read<int>('id'));
          final localPath = payload['local_file_path']?.toString() ?? '';
          if (localPath.isNotEmpty) localFiles.add(localPath);
        }
      } catch (_) {
        // Malformed unrelated queue entries are left for normal error handling.
      }
    }

    for (final id in revokedOutboxIds) {
      await _database.customStatement('DELETE FROM sync_outbox WHERE id = ?', [
        id,
      ]);
    }

    await _removeJobChildren(businessId, jobId, keepJob: false);

    // Cleanup owns this Job only. Vehicle findings can belong to other Jobs.
    if (vehicleId != null && vehicleId.isNotEmpty) {
      final remaining = await _database
          .customSelect(
            '''
        SELECT COUNT(*) AS count
        FROM local_jobs
        WHERE business_id = ? AND vehicle_id = ?
        ''',
            variables: [
              Variable<String>(businessId),
              Variable<String>(vehicleId),
            ],
          )
          .getSingle();

      if (remaining.read<int>('count') == 0) {
        final findingPhotoRows = await _database
            .customSelect(
              '''
          SELECT p.local_file_path
          FROM local_finding_photos p
          JOIN local_findings f
            ON f.business_id = p.business_id
           AND f.id = p.finding_id
          WHERE f.business_id = ?
            AND f.vehicle_id = ?
            AND p.local_file_path IS NOT NULL
            AND p.local_file_path <> ''
          ''',
              variables: [
                Variable<String>(businessId),
                Variable<String>(vehicleId),
              ],
            )
            .get();

        localFiles.addAll(
          findingPhotoRows
              .map((row) => row.readNullable<String>('local_file_path'))
              .whereType<String>(),
        );

        await _database.customStatement(
          '''
          DELETE FROM local_finding_photos
          WHERE business_id = ?
            AND finding_id IN (
              SELECT id
              FROM local_findings
              WHERE business_id = ? AND vehicle_id = ?
            )
          ''',
          [businessId, businessId, vehicleId],
        );
        await _database.customStatement(
          '''
          DELETE FROM local_findings
          WHERE business_id = ? AND vehicle_id = ?
          ''',
          [businessId, vehicleId],
        );
      }
    }

    for (final path in localFiles) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Database access is already revoked. File cleanup is best-effort.
      }
    }
  }

  Future<bool> _hasDirtyWork(String businessId, String jobId) async {
    final row = await _database
        .customSelect(
          '''
      SELECT EXISTS(
        SELECT 1
        FROM local_job_visits
        WHERE business_id = ?
          AND job_id = ?
          AND sync_state IN ('pending','conflict')
      ) AS dirty
      ''',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .getSingle();

    return row.read<int>('dirty') == 1;
  }

  Future<bool> _hasDirtyFindings(String businessId, String vehicleId) async {
    final row = await _database
        .customSelect(
          '''
      SELECT
        EXISTS(
          SELECT 1
          FROM local_findings
          WHERE business_id = ?
            AND vehicle_id = ?
            AND sync_state IN ('pending','conflict')
        )
        OR EXISTS(
          SELECT 1
          FROM local_finding_photos p
          JOIN local_findings f
            ON f.business_id = p.business_id
           AND f.id = p.finding_id
          WHERE f.business_id = ?
            AND f.vehicle_id = ?
            AND p.upload_state <> 'synced'
        ) AS dirty
      ''',
          variables: [
            Variable<String>(businessId),
            Variable<String>(vehicleId),
            Variable<String>(businessId),
            Variable<String>(vehicleId),
          ],
        )
        .getSingle();

    return row.read<int>('dirty') == 1;
  }

  Future<bool> _hasDirtyInspection(String businessId, String jobId) async {
    final row = await _database
        .customSelect(
          '''
      SELECT
        EXISTS(
          SELECT 1
          FROM local_pre_inspections
          WHERE business_id = ?
            AND job_id = ?
            AND sync_state IN ('pending','conflict')
        )
        OR EXISTS(
          SELECT 1
          FROM local_pre_inspection_photos p
          JOIN local_pre_inspections i
            ON i.id = p.inspection_id
           AND i.business_id = p.business_id
          WHERE i.business_id = ?
            AND i.job_id = ?
            AND p.upload_state <> 'synced'
        ) AS dirty
      ''',
          variables: [
            Variable<String>(businessId),
            Variable<String>(jobId),
            Variable<String>(businessId),
            Variable<String>(jobId),
          ],
        )
        .getSingle();

    return row.read<int>('dirty') == 1;
  }

  Future<void> _removeJobChildren(
    String businessId,
    String jobId, {
    required bool keepJob,
    bool preserveInspection = false,
    bool preserveWork = false,
  }) async {
    if (!preserveInspection) {
      await _database.customStatement(
        '''
        DELETE FROM local_pre_inspection_photos
        WHERE business_id = ?
          AND inspection_id IN (
            SELECT id FROM local_pre_inspections
            WHERE business_id = ? AND job_id = ?
          )
        ''',
        [businessId, businessId, jobId],
      );
      await _database.customStatement(
        'DELETE FROM local_pre_inspections WHERE business_id = ? AND job_id = ?',
        [businessId, jobId],
      );
    }
    if (!preserveWork) {
      await _database.customStatement(
        'DELETE FROM local_job_visits WHERE business_id = ? AND job_id = ?',
        [businessId, jobId],
      );
    }
    await _database.customStatement(
      'DELETE FROM local_job_assignments WHERE business_id = ? AND job_id = ?',
      [businessId, jobId],
    );
    if (!keepJob) {
      await _database.customStatement(
        'DELETE FROM local_jobs WHERE business_id = ? AND id = ?',
        [businessId, jobId],
      );
    }
  }

  Future<void> _writeSyncState(
    String businessId, {
    required int? cursor,
    required bool bootstrapped,
    required String? error,
  }) async {
    await _database.customStatement(
      '''
      INSERT INTO local_sync_states (
        business_id, scope, last_server_cursor, last_pull_at,
        last_push_at, last_error, bootstrapped
      ) VALUES (?, ?, ?, ?, NULL, ?, ?)
      ON CONFLICT(business_id, scope) DO UPDATE SET
        last_server_cursor=excluded.last_server_cursor,
        last_pull_at=excluded.last_pull_at,
        last_error=excluded.last_error,
        bootstrapped=excluded.bootstrapped
      ''',
      [
        businessId,
        _scope,
        cursor,
        _unix(DateTime.now().toUtc()),
        error,
        bootstrapped ? 1 : 0,
      ],
    );
  }

  String? _text(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  int? _int(Object? value) => int.tryParse(value?.toString() ?? '');

  double? _double(Object? value) => double.tryParse(value?.toString() ?? '');

  DateTime? _date(Object? value) => DateTime.tryParse(value?.toString() ?? '');

  int? _unix(DateTime? value) =>
      value == null ? null : value.toUtc().millisecondsSinceEpoch ~/ 1000;
}
