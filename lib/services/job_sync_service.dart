import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

class JobSyncService {
  JobSyncService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
  })  : _api = api,
        _database = database ?? localDatabase;

  static const _scope = 'jobs';

  final BriskersApi _api;
  final BriskersLocalDatabase _database;

  Future<void> pull(String businessId) async {
    int? cursor;
    var bootstrapped = false;

    final stateRows = await _database.customSelect(
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
    ).get();

    if (stateRows.isNotEmpty) {
      final state = stateRows.first;
      cursor = state.readNullable<int>('last_server_cursor');
      bootstrapped = (state.read<int>('bootstrapped')) == 1;
    }

    if (!bootstrapped) cursor = null;

    try {
      var hasMore = true;
      var pageCursor = cursor;

      while (hasMore) {
        final response = await _api.syncPullJobs(
          businessId,
          afterCursor: pageCursor,
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

        await _database.transaction(() async {
          if (mode == 'bootstrap') {
            await _clearBusinessJobCache(businessId);
          }

          for (final raw in bundles) {
            if (raw is! Map) continue;
            await _applyBundle(
              businessId,
              Map<String, dynamic>.from(raw),
            );
          }

          for (final jobId in revokedIds) {
            if (jobId.isEmpty) continue;
            await _removeJob(businessId, jobId);
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

  Future<void> _clearBusinessJobCache(String businessId) async {
    for (final table in const [
      'local_pre_inspection_photos',
      'local_pre_inspections',
      'local_job_visits',
      'local_job_assignments',
      'local_findings',
      'local_jobs',
    ]) {
      await _database.customStatement(
        'DELETE FROM $table WHERE business_id = ?',
        [businessId],
      );
    }
  }

  Future<void> _applyBundle(
    String businessId,
    Map<String, dynamic> bundle,
  ) async {
    final rawJob = bundle['job'];
    if (rawJob is! Map) return;

    final job = Map<String, dynamic>.from(rawJob);
    final jobId = job['id']?.toString() ?? '';
    if (jobId.isEmpty) return;

    final vehicleId = _text(job['vehicle_id']);

    final preserveInspection =
        await _hasDirtyInspection(businessId, jobId);

    await _removeJobChildren(
      businessId,
      jobId,
      keepJob: true,
      preserveInspection: preserveInspection,
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
      primaryAssignment =
          Map<String, dynamic>.from(assignments.first as Map);
    }

    await _database.customStatement(
      '''
      INSERT INTO local_jobs (
        id, business_id, access_scope, job_number, title, requested_work,
        status, status_name, status_color, status_icon,
        customer_id, customer_name, vehicle_id, vehicle_label,
        vehicle_vin, vehicle_plate, planned_hours, odometer_in,
        assigned_employee_id, assigned_employee_name, assigned_position,
        is_unassigned, created_at, completed_at, server_updated_at,
        row_version, sync_state
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?, 'synced'
      )
      ON CONFLICT(id) DO UPDATE SET
        business_id=excluded.business_id,
        access_scope=excluded.access_scope,
        job_number=excluded.job_number,
        title=excluded.title,
        requested_work=excluded.requested_work,
        status=excluded.status,
        status_name=excluded.status_name,
        status_color=excluded.status_color,
        status_icon=excluded.status_icon,
        customer_id=excluded.customer_id,
        customer_name=excluded.customer_name,
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
        completed_at=excluded.completed_at,
        server_updated_at=excluded.server_updated_at,
        row_version=excluded.row_version,
        sync_state='synced'
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

    final visits = List<dynamic>.from(
      job['visits'] ?? const <dynamic>[],
    );
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
          final attachmentId =
              photo['attachment_id']?.toString() ?? '';
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

    if (vehicleId != null) {
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
      }
    }
  }

  Future<void> _removeJob(
    String businessId,
    String jobId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT vehicle_id
      FROM local_jobs
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();

    final vehicleId = rows.isEmpty
        ? null
        : rows.first.readNullable<String>('vehicle_id');

    await _removeJobChildren(
      businessId,
      jobId,
      keepJob: false,
    );

    if (vehicleId != null && vehicleId.isNotEmpty) {
      final remaining = await _database.customSelect(
        '''
        SELECT COUNT(*) AS count
        FROM local_jobs
        WHERE business_id = ? AND vehicle_id = ?
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(vehicleId),
        ],
      ).getSingle();

      if (remaining.read<int>('count') == 0) {
        await _database.customStatement(
          '''
          DELETE FROM local_findings
          WHERE business_id = ? AND vehicle_id = ?
          ''',
          [businessId, vehicleId],
        );
      }
    }
  }

  Future<bool> _hasDirtyInspection(
    String businessId,
    String jobId,
  ) async {
    final row = await _database.customSelect(
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
    ).getSingle();

    return row.read<int>('dirty') == 1;
  }

  Future<void> _removeJobChildren(
    String businessId,
    String jobId, {
    required bool keepJob,
    bool preserveInspection = false,
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
    await _database.customStatement(
      'DELETE FROM local_job_visits WHERE business_id = ? AND job_id = ?',
      [businessId, jobId],
    );
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

  double? _double(Object? value) =>
      double.tryParse(value?.toString() ?? '');

  DateTime? _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');

  int? _unix(DateTime? value) =>
      value == null ? null : value.toUtc().millisecondsSinceEpoch ~/ 1000;
}
