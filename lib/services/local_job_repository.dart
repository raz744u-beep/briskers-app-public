import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

class LocalJobDetailSnapshot {
  const LocalJobDetailSnapshot({
    required this.job,
    required this.preInspection,
    required this.findings,
    required this.statuses,
  });

  final Map<String, dynamic> job;
  final Map<String, dynamic>? preInspection;
  final List<Map<String, dynamic>> findings;
  final List<Map<String, dynamic>> statuses;
}

class LocalJobRepository {
  LocalJobRepository({
    BriskersLocalDatabase? database,
  }) : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;

  Future<bool> hasJobBootstrap(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT bootstrapped
      FROM local_sync_states
      WHERE business_id = ? AND scope = 'jobs'
      LIMIT 1
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    return rows.isNotEmpty &&
        rows.first.read<int>('bootstrapped') == 1;
  }

  Future<List<Map<String, dynamic>>> listJobs(
    String businessId, {
    String? status,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final where = <String>['j.business_id = ?'];
    final variables = <Variable<Object>>[Variable<String>(businessId)];
    if (status != null && status.isNotEmpty) {
      where.add('j.status = ?');
      variables.add(Variable<String>(status));
    }
    final query = search?.trim().toLowerCase() ?? '';
    if (RegExp(r'^[0-9]+$').hasMatch(query)) {
      where.add(
        "(j.job_number = ? OR j.job_number = ? OR j.job_number = ?)",
      );
      variables.add(Variable<String>(query));
      variables.add(Variable<String>('J-$query'));
      variables.add(Variable<String>('MB-$query'));
    } else if (query.isNotEmpty) {
      where.add('''
        (lower(COALESCE(j.job_number, '')) LIKE ?
         OR lower(COALESCE(j.customer_name, '')) LIKE ?
         OR lower(COALESCE(j.vehicle_label, '')) LIKE ?
         OR lower(COALESCE(j.vehicle_vin, '')) LIKE ?
         OR lower(COALESCE(j.vehicle_plate, '')) LIKE ?
         OR lower(j.title) LIKE ?
         OR EXISTS (
           SELECT 1 FROM local_customers c
           WHERE c.business_id = j.business_id
             AND c.id = j.customer_id
             AND (
               lower(COALESCE(c.email, '')) LIKE ?
               OR lower(COALESCE(c.phone, '')) LIKE ?
               OR lower(COALESCE(c.list_email, '')) LIKE ?
               OR lower(COALESCE(c.list_phone, '')) LIKE ?
             )
         ))
      ''');
      final like = '%$query%';
      for (var i = 0; i < 10; i++) {
        variables.add(Variable<String>(like));
      }
    }
    variables.add(Variable<int>(limit));
    variables.add(Variable<int>(offset));

    final rows = await _database.customSelect(
      '''
      SELECT
        j.*,
        COALESCE(s.sort_order, 9999) AS status_sort_order,
        (
          SELECT COUNT(*)
          FROM local_findings f
          WHERE f.business_id = j.business_id
            AND f.vehicle_id = j.vehicle_id
            AND f.status = 'open'
        ) AS open_findings
      FROM local_jobs j
      LEFT JOIN local_job_statuses s
        ON s.business_id = j.business_id AND s.code = j.status
      WHERE ${where.join(' AND ')}
      ORDER BY
        CASE WHEN j.status IN ('completed','cancelled') THEN 1 ELSE 0 END,
        COALESCE(s.sort_order, 9999),
        -- Imported MobileBiz created_at records when the import ran, not
        -- when jobs were originally opened. Use the sequential job number.
        CASE
          WHEN substr(j.job_number, instr(j.job_number, '-') + 1)
               GLOB '[0-9]*'
          THEN CAST(
            substr(j.job_number, instr(j.job_number, '-') + 1) AS INTEGER
          )
          ELSE -1
        END DESC,
        j.created_at DESC, j.id
      LIMIT ? OFFSET ?
      ''',
      variables: variables,
    ).get();
    return rows.map(_jobListMap).toList();
  }

  Future<int> jobCount(
    String businessId, {
    String? status,
    String? search,
  }) async {
    final where = <String>['business_id = ?'];
    final variables = <Variable<Object>>[Variable<String>(businessId)];
    if (status != null && status.isNotEmpty) {
      where.add('status = ?');
      variables.add(Variable<String>(status));
    }
    final query = search?.trim().toLowerCase() ?? '';
    if (RegExp(r'^[0-9]+$').hasMatch(query)) {
      where.add(
        "(job_number = ? OR job_number = ? OR job_number = ?)",
      );
      variables.add(Variable<String>(query));
      variables.add(Variable<String>('J-$query'));
      variables.add(Variable<String>('MB-$query'));
    } else if (query.isNotEmpty) {
      where.add('''
        (lower(COALESCE(job_number, '')) LIKE ?
         OR lower(COALESCE(customer_name, '')) LIKE ?
         OR lower(COALESCE(vehicle_label, '')) LIKE ?
         OR lower(COALESCE(vehicle_vin, '')) LIKE ?
         OR lower(COALESCE(vehicle_plate, '')) LIKE ?
         OR lower(title) LIKE ?
         OR EXISTS (
           SELECT 1 FROM local_customers c
           WHERE c.business_id = local_jobs.business_id
             AND c.id = local_jobs.customer_id
             AND (
               lower(COALESCE(c.email, '')) LIKE ?
               OR lower(COALESCE(c.phone, '')) LIKE ?
               OR lower(COALESCE(c.list_email, '')) LIKE ?
               OR lower(COALESCE(c.list_phone, '')) LIKE ?
             )
         ))
      ''');
      final like = '%$query%';
      for (var i = 0; i < 10; i++) {
        variables.add(Variable<String>(like));
      }
    }
    final row = await _database.customSelect(
      'SELECT COUNT(*) AS count FROM local_jobs WHERE ${where.join(' AND ')}',
      variables: variables,
    ).getSingle();
    return row.read<int>('count');
  }

  Stream<int> watchJobCount(
    String businessId, {
    String? status,
  }) {
    final where = <String>['business_id = ?'];
    final variables = <Variable<Object>>[Variable<String>(businessId)];
    if (status != null && status.isNotEmpty) {
      where.add('status = ?');
      variables.add(Variable<String>(status));
    }

    return _database
        .customSelect(
          'SELECT COUNT(*) AS count FROM local_jobs WHERE ${where.join(' AND ')}',
          variables: variables,
          readsFrom: {_database.localJobs},
        )
        .watchSingle()
        .map((row) => row.read<int>('count'));
  }

  Future<List<Map<String, dynamic>>> unassignedOpenJobs(
    String businessId, {
    int limit = 25,
  }) async {
    final rows = await _database.customSelect(
      '''
      SELECT id, job_number, title, customer_name, vehicle_label, status
      FROM local_jobs
      WHERE business_id = ?
        AND is_unassigned = 1
        AND status NOT IN ('completed', 'cancelled')
      ORDER BY created_at DESC, id
      LIMIT ?
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<int>(limit),
      ],
    ).get();

    return rows
        .map(
          (row) => <String, dynamic>{
            'id': row.read<String>('id'),
            'job_number': row.readNullable<String>('job_number'),
            'title': row.read<String>('title'),
            'customer_name': row.readNullable<String>('customer_name'),
            'vehicle': row.readNullable<String>('vehicle_label'),
            'status': row.read<String>('status'),
            '_local_snapshot': true,
          },
        )
        .toList();
  }

  Future<int> unassignedOpenJobCount(String businessId) async {
    final row = await _database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM local_jobs
      WHERE business_id = ?
        AND is_unassigned = 1
        AND status NOT IN ('completed', 'cancelled')
      ''',
      variables: [Variable<String>(businessId)],
    ).getSingle();
    return row.read<int>('count');
  }

  Future<int> activeJobCount(String businessId) async {
    final row = await _database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM local_jobs
      WHERE business_id = ?
        AND status NOT IN ('completed', 'cancelled')
      ''',
      variables: [Variable<String>(businessId)],
    ).getSingle();
    return row.read<int>('count');
  }

  Stream<int> watchActiveJobCount(String businessId) {
    return _database
        .customSelect(
          '''
          SELECT COUNT(*) AS count
          FROM local_jobs
          WHERE business_id = ?
            AND status NOT IN ('completed', 'cancelled')
          ''',
          variables: [Variable<String>(businessId)],
          readsFrom: {_database.localJobs},
        )
        .watchSingle()
        .map((row) => row.read<int>('count'));
  }

  Future<Map<String, int>> jobStatusCounts(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT status, COUNT(*) AS count
      FROM local_jobs
      WHERE business_id = ?
      GROUP BY status
      ''',
      variables: [Variable<String>(businessId)],
    ).get();
    return {
      for (final row in rows)
        row.read<String>('status'): row.read<int>('count'),
    };
  }

  Future<List<Map<String, dynamic>>> jobStatuses(
    String businessId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT code, name, color_hex, icon_key, sort_order
      FROM local_job_statuses
      WHERE business_id = ?
      ORDER BY sort_order, name, code
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    return rows
        .map(
          (row) => <String, dynamic>{
            'code': row.read<String>('code'),
            'name': row.read<String>('name'),
            'color_hex': row.readNullable<String>('color_hex'),
            'icon_key': row.readNullable<String>('icon_key'),
            'sort_order': row.read<int>('sort_order'),
          },
        )
        .toList();
  }

  Future<void> replaceJobStatuses(
    String businessId,
    List<Map<String, dynamic>> statuses,
  ) async {
    await _database.transaction(() async {
      await _database.customStatement(
        'DELETE FROM local_job_statuses WHERE business_id = ?',
        [businessId],
      );

      for (final status in statuses) {
        final code = status['code']?.toString() ?? '';
        if (code.isEmpty) continue;
        await _database.customStatement(
          '''
          INSERT INTO local_job_statuses (
            business_id, code, name, color_hex, icon_key, sort_order
          ) VALUES (?, ?, ?, ?, ?, ?)
          ''',
          [
            businessId,
            code,
            status['name']?.toString() ?? code,
            _text(status['color_hex']),
            _text(status['icon_key']),
            _int(status['sort_order']) ?? 0,
          ],
        );
      }
    });
  }

  Future<void> applyServerListDecorations(
    String businessId,
    List<Map<String, dynamic>> jobs,
  ) async {
    await _database.transaction(() async {
      for (final job in jobs) {
        final id = job['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await _database.customStatement(
          '''
          UPDATE local_jobs
          SET pending_request_count = ?,
              payment_state = ?
          WHERE business_id = ? AND id = ?
          ''',
          [
            _int(job['pending_requests']) ?? 0,
            _text(job['payment_state']),
            businessId,
            id,
          ],
        );
      }
    });
  }

  Future<LocalJobDetailSnapshot?> jobDetail(
    String businessId,
    String jobId,
  ) async {
    final jobRows = await _database.customSelect(
      '''
      SELECT *
      FROM local_jobs
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();

    if (jobRows.isEmpty) return null;
    final row = jobRows.first;

    final assignmentRows = await _database.customSelect(
      '''
      SELECT *
      FROM local_job_assignments
      WHERE business_id = ? AND job_id = ? AND active = 1
      ORDER BY assigned_at, assignment_id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();

    final assignments = assignmentRows
        .map(
          (assignment) => <String, dynamic>{
            'assignment_id':
                assignment.read<String>('assignment_id'),
            'employee_id': assignment.read<String>('employee_id'),
            'employee_name':
                assignment.readNullable<String>('employee_name'),
            'position':
                assignment.readNullable<String>('position'),
            'assigned_at':
                _isoFromDb(assignment.data['assigned_at']),
            'released_at':
                _isoFromDb(assignment.data['released_at']),
            'source': assignment.readNullable<String>('source'),
          },
        )
        .toList();

    final visitRows = await _database.customSelect(
      '''
      SELECT *
      FROM local_job_visits
      WHERE business_id = ? AND job_id = ?
      ORDER BY visit_number DESC, opened_at DESC, id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();

    final visits = visitRows
        .map(
          (visit) => <String, dynamic>{
            'id': visit.read<String>('id'),
            'visit_number': visit.read<int>('visit_number'),
            'reason': visit.readNullable<String>('reason'),
            'planned_hours': visit.data['planned_hours'],
            'work_summary':
                visit.readNullable<String>('work_summary'),
            'opened_at': _isoFromDb(visit.data['opened_at']),
            'closed_at': _isoFromDb(visit.data['closed_at']),
            'updated_at':
                _isoFromDb(visit.data['server_updated_at']),
            'row_version':
                visit.readNullable<int>('row_version'),
            'sync_state': visit.read<String>('sync_state'),
            'mechanics': const <dynamic>[],
          },
        )
        .toList();

    final vehicleId = row.readNullable<String>('vehicle_id');
    final capabilities = _jsonMap(
      row.read<String>('capabilities_json'),
    );

    final job = <String, dynamic>{
      'id': row.read<String>('id'),
      'job_number': row.readNullable<String>('job_number'),
      'title': row.read<String>('title'),
      'requested_work':
          row.readNullable<String>('requested_work'),
      'status': row.read<String>('status'),
      'status_name': row.readNullable<String>('status_name'),
      'status_color': row.readNullable<String>('status_color'),
      'status_icon': row.readNullable<String>('status_icon'),
      'planned_hours': row.data['planned_hours'],
      'odometer_in': row.data['odometer_in'],
      'created_at': _isoFromDb(row.data['created_at']),
      'completed_at': _isoFromDb(row.data['completed_at']),
      'updated_at':
          _isoFromDb(row.data['server_updated_at']),
      'row_version': row.readNullable<int>('row_version'),
      'customer_id': row.readNullable<String>('customer_id'),
      'customer_name': row.readNullable<String>('customer_name'),
      'customer_problem_flag':
          row.read<int>('customer_problem_flag') == 1,
      'customer_problem_flag_note':
          row.readNullable<String>('customer_problem_flag_note'),
      'vehicle_id': vehicleId,
      'vehicle': row.readNullable<String>('vehicle_label'),
      'vehicle_vin': row.readNullable<String>('vehicle_vin'),
      'vehicle_plate': row.readNullable<String>('vehicle_plate'),
      'is_unassigned': row.read<int>('is_unassigned') == 1,
      'capabilities': capabilities,
      'assignments': assignments,
      'pending_requests': const <dynamic>[],
      'visits': visits,
      'status_history': const <dynamic>[],
      '_local_snapshot': true,
    };

    final preInspection =
        await _preInspection(businessId, jobId);
    final findings = vehicleId == null
        ? <Map<String, dynamic>>[]
        : await _findings(businessId, vehicleId);
    final statuses = await jobStatuses(businessId);

    return LocalJobDetailSnapshot(
      job: job,
      preInspection: preInspection,
      findings: findings,
      statuses: statuses,
    );
  }

  Map<String, dynamic> _jobListMap(QueryRow row) {
    final capabilities = _jsonMap(
      row.read<String>('capabilities_json'),
    );
    return <String, dynamic>{
      'id': row.read<String>('id'),
      'job_number': row.readNullable<String>('job_number'),
      'title': row.read<String>('title'),
      'requested_work':
          row.readNullable<String>('requested_work'),
      'status': row.read<String>('status'),
      'status_name': row.readNullable<String>('status_name'),
      'status_color': row.readNullable<String>('status_color'),
      'status_icon': row.readNullable<String>('status_icon'),
      'customer_name': row.readNullable<String>('customer_name'),
      'vehicle': row.readNullable<String>('vehicle_label'),
      'planned_hours': row.data['planned_hours'],
      'assigned_employee':
          row.readNullable<String>('assigned_employee_name'),
      'assigned_employee_id':
          row.readNullable<String>('assigned_employee_id'),
      'assigned_position':
          row.readNullable<String>('assigned_position'),
      'open_findings': row.read<int>('open_findings'),
      'pending_requests':
          row.read<int>('pending_request_count'),
      'can_request': capabilities['request_job'] == true,
      'created_at': _isoFromDb(row.data['created_at']),
      'completed_at': _isoFromDb(row.data['completed_at']),
      'payment_state': row.readNullable<String>('payment_state'),
      '_local_snapshot': true,
    };
  }

  Future<Map<String, dynamic>?> _preInspection(
    String businessId,
    String jobId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_pre_inspections
      WHERE business_id = ? AND job_id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();

    if (rows.isEmpty) return null;
    final row = rows.first;
    final inspectionId = row.read<String>('id');

    final photoRows = await _database.customSelect(
      '''
      SELECT *
      FROM local_pre_inspection_photos
      WHERE business_id = ? AND inspection_id = ?
      ORDER BY captured_at, id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(inspectionId),
      ],
    ).get();

    return <String, dynamic>{
      'id': inspectionId,
      'job_id': jobId,
      'vehicle_id': row.readNullable<String>('vehicle_id'),
      'inspected_at': _isoFromDb(row.data['inspected_at']),
      'odometer': row.data['odometer'],
      'notes': row.readNullable<String>('notes'),
      'created_by': row.readNullable<String>('created_by'),
      'updated_at':
          _isoFromDb(row.data['server_updated_at']),
      'row_version': row.readNullable<int>('row_version'),
      'sync_state': row.read<String>('sync_state'),
      'photos': photoRows
          .map(
            (photo) => <String, dynamic>{
              'id': photo.read<String>('id'),
              'attachment_id':
                  photo.read<String>('attachment_id'),
              'filename': photo.readNullable<String>('filename'),
              'bucket':
                  photo.readNullable<String>('storage_bucket'),
              'key': photo.readNullable<String>('storage_key'),
              'mime_type':
                  photo.readNullable<String>('mime_type'),
              'byte_size': photo.readNullable<int>('byte_size'),
              'captured_at':
                  _isoFromDb(photo.data['captured_at']),
              'note': photo.readNullable<String>('note'),
              'created_by':
                  photo.readNullable<String>('created_by'),
              'can_edit_note':
                  photo.read<int>('can_edit_note') == 1,
              'can_delete': false,
              'local_file_path':
                  photo.readNullable<String>('local_file_path'),
              'upload_state': photo.read<String>('upload_state'),
              'last_error':
                  photo.readNullable<String>('last_error'),
            },
          )
          .toList(),
    };
  }

  Future<List<Map<String, dynamic>>> _findings(
    String businessId,
    String vehicleId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_findings
      WHERE business_id = ? AND vehicle_id = ?
      ORDER BY
        CASE status
          WHEN 'open' THEN 0
          WHEN 'in_job' THEN 1
          ELSE 2
        END,
        created_at DESC,
        id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(vehicleId),
      ],
    ).get();

    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final findingId = row.read<String>('id');
      final photoRows = await _database.customSelect(
        '''
        SELECT *
        FROM local_finding_photos
        WHERE business_id = ? AND finding_id = ?
        ORDER BY captured_at, id
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(findingId),
        ],
      ).get();

      result.add(<String, dynamic>{
        'id': findingId,
        'body': row.read<String>('body'),
        'status': row.read<String>('status'),
        'include_on_invoice':
            row.read<int>('include_on_invoice') == 1,
        'created_at': _isoFromDb(row.data['created_at']),
        'resolved_at': _isoFromDb(row.data['resolved_at']),
        'updated_at':
            _isoFromDb(row.data['server_updated_at']),
        'row_version': row.readNullable<int>('row_version'),
        'created_by': row.readNullable<String>('created_by'),
        'vehicle_id': row.readNullable<String>('vehicle_id'),
        'found_job_id':
            row.readNullable<String>('found_job_id'),
        'repair_job_id':
            row.readNullable<String>('repair_job_id'),
        'can_edit': row.read<int>('can_edit') == 1,
        'can_delete': false,
        'sync_state': row.read<String>('sync_state'),
        'attachments': photoRows
            .map(
              (photo) => <String, dynamic>{
                'id': photo.read<String>('id'),
                'attachment_id':
                    photo.read<String>('attachment_id'),
                'bucket':
                    photo.readNullable<String>('storage_bucket'),
                'key': photo.readNullable<String>('storage_key'),
                'filename':
                    photo.readNullable<String>('filename'),
                'mime_type':
                    photo.readNullable<String>('mime_type'),
                'byte_size':
                    photo.readNullable<int>('byte_size'),
                'captured_at':
                    _isoFromDb(photo.data['captured_at']),
                'can_delete': false,
                'local_file_path':
                    photo.readNullable<String>('local_file_path'),
                'upload_state':
                    photo.read<String>('upload_state'),
                'last_error':
                    photo.readNullable<String>('last_error'),
              },
            )
            .toList(),
      });
    }

    return result;
  }

  Map<String, dynamic> _jsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  int? _int(Object? value) =>
      int.tryParse(value?.toString() ?? '');

  String? _text(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  String? _isoFromDb(Object? value) {
    if (value == null) return null;
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        value * 1000,
        isUtc: true,
      ).toIso8601String();
    }
    return DateTime.tryParse(value.toString())
        ?.toUtc()
        .toIso8601String();
  }
}
