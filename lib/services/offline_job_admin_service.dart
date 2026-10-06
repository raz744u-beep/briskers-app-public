import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/local_database_provider.dart';
import 'briskers_api.dart';

class OfflineJobAdminService {
  OfflineJobAdminService({BriskersApi api = const BriskersApi()}) : _api = api;

  final BriskersApi _api;

  String _employeesKey(String businessId) => 'briskers_job_employees_$businessId';

  Future<List<Map<String, dynamic>>> refreshEmployees(String businessId) async {
    final rows = await _api.assignableEmployees(businessId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_employeesKey(businessId), jsonEncode(rows));
    return rows;
  }

  Future<List<Map<String, dynamic>>> cachedEmployees(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_employeesKey(businessId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      return List<dynamic>.from(jsonDecode(raw) as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> queueCore(
    String businessId,
    String jobId, {
    String? customerId,
    String? vehicleId,
    bool replaceVehicle = false,
    String? title,
    String? requestedWork,
    bool replaceRequestedWork = false,
    num? plannedHours,
  }) async {
    final rows = await localDatabase.customSelect(
      '''
      SELECT customer_id, vehicle_id, title, requested_work, planned_hours
      FROM local_jobs
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();
    if (rows.isEmpty) {
      throw StateError('The job is not available in the local database.');
    }

    final current = rows.first;
    final nextCustomerId =
        customerId ?? current.readNullable<String>('customer_id') ?? '';
    final nextVehicleId = replaceVehicle
        ? vehicleId
        : vehicleId ?? current.readNullable<String>('vehicle_id');
    final nextTitle = title ?? current.read<String>('title');
    final nextRequestedWork = replaceRequestedWork
        ? requestedWork
        : requestedWork ?? current.readNullable<String>('requested_work');
    final nextPlannedHours = plannedHours ??
        (num.tryParse(current.data['planned_hours']?.toString() ?? '') ?? 0);

    await localDatabase.transaction(() async {
      await localDatabase.customStatement(
        '''
        UPDATE local_jobs
        SET customer_id = ?,
            vehicle_id = ?,
            title = ?,
            requested_work = ?,
            planned_hours = ?,
            sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [
          nextCustomerId,
          nextVehicleId,
          nextTitle,
          nextRequestedWork,
          nextPlannedHours.toDouble(),
          businessId,
          jobId,
        ],
      );

      await _mergeOutbox(
        businessId,
        jobId,
        {
          'core_changed': true,
          'customer_id': nextCustomerId,
          'vehicle_id': nextVehicleId,
          'title': nextTitle,
          'requested_work': nextRequestedWork,
          'planned_hours': nextPlannedHours.toDouble(),
        },
      );
    });
  }

  Future<void> queuePlannedHours(
    String businessId,
    String jobId,
    num plannedHours,
  ) =>
      queueCore(
        businessId,
        jobId,
        plannedHours: plannedHours,
      );

  Future<void> queueStatus(
    String businessId,
    String jobId, {
    required String code,
    required String name,
    String? colorHex,
    String? iconKey,
    String? note,
  }) async {
    await localDatabase.transaction(() async {
      await localDatabase.customStatement(
        '''
        UPDATE local_jobs
        SET status = ?,
            status_name = ?,
            status_color = ?,
            status_icon = ?,
            sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [
          code,
          name,
          colorHex,
          iconKey,
          businessId,
          jobId,
        ],
      );
      await _mergeOutbox(
        businessId,
        jobId,
        {
          'status_changed': true,
          'status_code': code,
          'status_note': note,
        },
      );
    });
  }

  Future<void> queueAssignment(
    String businessId,
    String jobId, {
    required String? employeeId,
    String? employeeName,
    String? position,
  }) async {
    await localDatabase.transaction(() async {
      await localDatabase.customStatement(
        '''
        UPDATE local_jobs
        SET assigned_employee_id = ?,
            assigned_employee_name = ?,
            assigned_position = ?,
            is_unassigned = ?,
            sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [
          employeeId,
          employeeName,
          position,
          employeeId == null || employeeId.isEmpty ? 1 : 0,
          businessId,
          jobId,
        ],
      );

      await localDatabase.customStatement(
        'DELETE FROM local_job_assignments WHERE business_id = ? AND job_id = ?',
        [businessId, jobId],
      );

      if (employeeId != null && employeeId.isNotEmpty) {
        await localDatabase.customStatement(
          '''
          INSERT INTO local_job_assignments (
            assignment_id, business_id, job_id, employee_id,
            employee_name, position, active, assigned_at, source
          ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, 'offline_admin')
          ''',
          [
            'local-admin-$jobId',
            businessId,
            jobId,
            employeeId,
            employeeName,
            position,
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          ],
        );
      }

      await _mergeOutbox(
        businessId,
        jobId,
        {
          'assignment_changed': true,
          'employee_id': employeeId,
          'employee_name': employeeName,
          'position': position,
        },
      );
    });
  }

  Future<void> _mergeOutbox(
    String businessId,
    String jobId,
    Map<String, dynamic> changes,
  ) async {
    final existing = await localDatabase.customSelect(
      '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'job_admin'
        AND entity_id = ?
        AND state = 'pending'
      ORDER BY id DESC
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();

    final payload = <String, dynamic>{};
    if (existing.isNotEmpty) {
      try {
        payload.addAll(
          Map<String, dynamic>.from(
            jsonDecode(existing.first.read<String>('payload_json')) as Map,
          ),
        );
      } catch (_) {}
    }
    payload.addAll(changes);

    if (existing.isNotEmpty) {
      await localDatabase.customStatement(
        '''
        UPDATE sync_outbox
        SET payload_json = ?, last_error = NULL
        WHERE id = ?
        ''',
        [jsonEncode(payload), existing.first.read<int>('id')],
      );
    } else {
      await localDatabase.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation,
          payload_json, state, attempt_count, created_at
        ) VALUES (?, 'job_admin', ?, 'update', ?, 'pending', 0, ?)
        ''',
        [
          businessId,
          jobId,
          jsonEncode(payload),
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        ],
      );
    }
  }

  Future<void> flush(String businessId) async {
    final rows = await localDatabase.customSelect(
      '''
      SELECT id, entity_id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'job_admin'
        AND state = 'pending'
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    for (final row in rows) {
      final outboxId = row.read<int>('id');
      final jobId = row.read<String>('entity_id');
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );

        if (payload['core_changed'] == true ||
            payload.containsKey('planned_hours')) {
          final jobRows = await localDatabase.customSelect(
            '''
            SELECT customer_id, vehicle_id, title, requested_work, planned_hours
            FROM local_jobs
            WHERE business_id = ? AND id = ?
            LIMIT 1
            ''',
            variables: [
              Variable<String>(businessId),
              Variable<String>(jobId),
            ],
          ).get();
          if (jobRows.isNotEmpty) {
            final job = jobRows.first;
            await _api.updateJob(
              businessId,
              jobId,
              customerId:
                  payload['customer_id']?.toString() ??
                  job.readNullable<String>('customer_id') ??
                  '',
              vehicleId: payload.containsKey('vehicle_id')
                  ? payload['vehicle_id']?.toString()
                  : job.readNullable<String>('vehicle_id'),
              title:
                  payload['title']?.toString() ?? job.read<String>('title'),
              requestedWork: payload.containsKey('requested_work')
                  ? payload['requested_work']?.toString()
                  : job.readNullable<String>('requested_work'),
              plannedHours: num.tryParse(
                    payload['planned_hours']?.toString() ??
                        job.data['planned_hours']?.toString() ??
                        '',
                  ) ??
                  0,
            );
          }
        }

        if (payload['status_changed'] == true) {
          final statusCode = payload['status_code']?.toString() ?? '';
          if (statusCode.isNotEmpty) {
            await _api.changeJobStatus(
              businessId,
              jobId,
              statusCode,
              note: payload['status_note']?.toString(),
            );
          }
        }

        if (payload['assignment_changed'] == true) {
          final employeeId = payload['employee_id']?.toString();
          if (employeeId == null || employeeId.isEmpty) {
            await _api.clearJobAssignments(businessId, jobId);
          } else {
            await _api.setPrimaryJobEmployee(businessId, jobId, employeeId);
          }
        }

        await localDatabase.customStatement(
          'DELETE FROM sync_outbox WHERE id = ?',
          [outboxId],
        );
        await localDatabase.customStatement(
          '''
          UPDATE local_jobs
          SET sync_state = 'synced'
          WHERE business_id = ? AND id = ?
          ''',
          [businessId, jobId],
        );
      } catch (error) {
        await localDatabase.customStatement(
          '''
          UPDATE sync_outbox
          SET attempt_count = attempt_count + 1,
              last_attempt_at = ?,
              last_error = ?
          WHERE id = ?
          ''',
          [
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
            error.toString(),
            outboxId,
          ],
        );
        rethrow;
      }
    }
  }
}
