import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'employee_roster_cache.dart';
import 'local_job_quarantine.dart';

class OfflineJobAdminService {
  OfflineJobAdminService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
  }) : _api = api,
       _database = database ?? localDatabase;

  final BriskersApi _api;
  final BriskersLocalDatabase _database;

  final EmployeeRosterCache _roster = EmployeeRosterCache();

  Future<List<Map<String, dynamic>>> refreshEmployees(String businessId) =>
      _roster.refreshAssignable(businessId);

  Future<List<Map<String, dynamic>>> cachedEmployees(String businessId) async =>
      (await _roster.cachedAssignable(businessId))?.rows ?? const [];

  static String _newJobId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Save a new Job before contacting the network. The stable UUID is also
  /// sent to the server so uncertain retries cannot create a second job.
  Future<String> queueJobCreate(
    String businessId, {
    required String customerId,
    required String customerName,
    String? vehicleId,
    String? vehicleLabel,
    required String title,
    String? requestedWork,
    num plannedHours = 0,
    String? employeeId,
    String? employeeName,
  }) async {
    if (title.trim().isEmpty) throw StateError('Job title is required.');
    final id = _newJobId();
    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      await _database.customStatement(
        """INSERT INTO local_jobs
          (id,business_id,access_scope,job_number,title,requested_work,
           status,status_name,customer_id,customer_name,vehicle_id,vehicle_label,
           planned_hours,assigned_employee_id,assigned_employee_name,
           is_unassigned,created_at,sync_state)
          VALUES (?,?,'full','Pending sync',?,?,'open','Open',?,?,?,?,?,?,?,?,?,'pending')""",
        [
          id,
          businessId,
          title.trim(),
          requestedWork,
          customerId,
          customerName,
          vehicleId,
          vehicleLabel,
          plannedHours.toDouble(),
          employeeId,
          employeeName,
          employeeId == null ? 1 : 0,
          now.millisecondsSinceEpoch ~/ 1000,
        ],
      );
      await _database.customStatement(
        """INSERT INTO sync_outbox
          (business_id,entity_type,entity_id,operation,payload_json,
           state,attempt_count,created_at)
          VALUES (?,'job_create',?,'create',?,'pending',0,?)""",
        [
          businessId,
          id,
          jsonEncode({
            'operation_id': 'job-create-$id',
            'job_id': id,
            'customer_id': customerId,
            'vehicle_id': vehicleId,
            'title': title.trim(),
            'requested_work': requestedWork,
            'planned_hours': plannedHours.toDouble(),
            'employee_id': employeeId,
            'employee_name': employeeName,
          }),
          now.millisecondsSinceEpoch ~/ 1000,
        ],
      );
    });
    return id;
  }

  Future<void> flushCreates(String businessId) async {
    final rows = await _database
        .customSelect(
          """SELECT id,entity_id,payload_json FROM sync_outbox
         WHERE business_id=? AND entity_type='job_create' AND state='pending'
         ORDER BY id""",
          variables: [Variable<String>(businessId)],
        )
        .get();
    for (final row in rows) {
      final outboxId = row.read<int>('id');
      final id = row.read<String>('entity_id');
      final data = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
      try {
        await LocalJobQuarantine.assertReplayAllowed(
          _database,
          businessId,
          outboxId: outboxId,
        );
        final customerId = data['customer_id']?.toString() ?? '';
        final vehicleId = data['vehicle_id']?.toString();
        if (customerId.startsWith('local-') ||
            (vehicleId != null && vehicleId.startsWith('local-'))) {
          continue;
        }
        // Durably mark the attempt before any network send. Cancellation can
        // prove never-sent only while this counter remains zero.
        await _database.transaction(() async {
          await LocalJobQuarantine.assertReplayAllowed(
            _database,
            businessId,
            outboxId: outboxId,
          );
          await _database.customStatement(
            'UPDATE sync_outbox SET attempt_count=attempt_count+1,last_attempt_at=? WHERE business_id=? AND id=?',
            [
              DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
              businessId,
              outboxId,
            ],
          );
        });
        try {
          await LocalJobQuarantine.guardReplay(
            _database,
            businessId,
            () => _api.createJob(
              businessId,
              id: id,
              customerId: customerId,
              vehicleId: data['vehicle_id']?.toString(),
              title: data['title']?.toString() ?? 'New Job',
              description: data['requested_work']?.toString(),
            ),
            outboxId: outboxId,
          );
        } catch (error) {
          if (error is LocalJobQuarantineException) rethrow;
          // A prior request may have committed even if its response was lost.
          // Verify the same UUID and customer before treating it as replayed.
          final existing = await _api.jobDetail(businessId, id);
          if (existing['id']?.toString() != id ||
              existing['customer_id']?.toString() != customerId) {
            rethrow;
          }
        }
        await LocalJobQuarantine.guardReplay(
          _database,
          businessId,
          () => _api.updateJob(
            businessId,
            id,
            customerId: customerId,
            vehicleId: data['vehicle_id']?.toString(),
            title: data['title']?.toString() ?? 'New Job',
            requestedWork: data['requested_work']?.toString(),
            plannedHours:
                num.tryParse(data['planned_hours']?.toString() ?? '') ?? 0,
          ),
          outboxId: outboxId,
        );
        final employeeId = data['employee_id']?.toString();
        if (employeeId != null && employeeId.isNotEmpty) {
          await LocalJobQuarantine.guardReplay(
            _database,
            businessId,
            () => _api.setPrimaryJobEmployee(businessId, id, employeeId),
            outboxId: outboxId,
          );
        }
        await _database.transaction(() async {
          await LocalJobQuarantine.assertReplayAllowed(
            _database,
            businessId,
            outboxId: outboxId,
          );
          await _database.customStatement(
            "DELETE FROM sync_outbox WHERE id=? AND entity_type='job_create'",
            [outboxId],
          );
          await _database.customStatement(
            "UPDATE local_jobs SET sync_state='synced' WHERE business_id=? AND id=?",
            [businessId, id],
          );
        });
      } catch (error) {
        if (error is LocalJobQuarantineException) rethrow;
        // Keep the identical operation ID and payload for a safe later retry.
      }
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
    final rows = await _database
        .customSelect(
          '''
      SELECT customer_id, vehicle_id, title, requested_work, planned_hours
      FROM local_jobs
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();
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
    final nextPlannedHours =
        plannedHours ??
        (num.tryParse(current.data['planned_hours']?.toString() ?? '') ?? 0);

    await _database.transaction(() async {
      await _database.customStatement(
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

      await _mergeOutbox(businessId, jobId, {
        'core_changed': true,
        'customer_id': nextCustomerId,
        'vehicle_id': nextVehicleId,
        'title': nextTitle,
        'requested_work': nextRequestedWork,
        'planned_hours': nextPlannedHours.toDouble(),
      });
    });
  }

  Future<void> queuePlannedHours(
    String businessId,
    String jobId,
    num plannedHours,
  ) => queueCore(businessId, jobId, plannedHours: plannedHours);

  Future<void> queueStatus(
    String businessId,
    String jobId, {
    required String code,
    required String name,
    String? colorHex,
    String? iconKey,
    String? note,
  }) async {
    await _database.transaction(() async {
      await _database.customStatement(
        '''
        UPDATE local_jobs
        SET status = ?,
            status_name = ?,
            status_color = ?,
            status_icon = ?,
            completed_at = CASE
              WHEN lower(?) = 'completed' THEN
                CASE WHEN lower(status) = 'completed' THEN completed_at ELSE ? END
              WHEN lower(?) NOT IN ('completed', 'cancelled', 'closed') THEN NULL
              ELSE completed_at
            END,
            sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [
          code,
          name,
          colorHex,
          iconKey,
          code,
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          code,
          businessId,
          jobId,
        ],
      );
      await _mergeOutbox(businessId, jobId, {
        'status_changed': true,
        'status_code': code,
        'status_note': note,
      });
    });
  }

  Future<void> queueAssignment(
    String businessId,
    String jobId, {
    required String? employeeId,
    String? employeeName,
    String? position,
  }) async {
    await _database.transaction(() async {
      await _database.customStatement(
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

      await _database.customStatement(
        'DELETE FROM local_job_assignments WHERE business_id = ? AND job_id = ?',
        [businessId, jobId],
      );

      if (employeeId != null && employeeId.isNotEmpty) {
        await _database.customStatement(
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

      await _mergeOutbox(businessId, jobId, {
        'assignment_changed': true,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'position': position,
      });
    });
  }

  Future<void> _mergeOutbox(
    String businessId,
    String jobId,
    Map<String, dynamic> changes,
  ) async {
    final existing = await _database
        .customSelect(
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
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();

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
    // Keep the queue's original identity/time, but order Jobs by the latest edit.
    payload['_activity_at'] =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    if (existing.isNotEmpty) {
      await _database.customStatement(
        '''
        UPDATE sync_outbox
        SET payload_json = ?, last_error = NULL
        WHERE id = ?
        ''',
        [jsonEncode(payload), existing.first.read<int>('id')],
      );
    } else {
      await _database.customStatement(
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
    await flushCreates(businessId);
    final rows = await _database
        .customSelect(
          '''
      SELECT id, entity_id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'job_admin'
        AND state = 'pending'
      ORDER BY id
      ''',
          variables: [Variable<String>(businessId)],
        )
        .get();

    for (final row in rows) {
      final outboxId = row.read<int>('id');
      final jobId = row.read<String>('entity_id');
      // Conversion-created jobs have provisional local identities until the
      // associated document upload returns its authoritative server Job ID.
      if (jobId.startsWith('local-')) {
        await _database.customStatement(
          "UPDATE sync_outbox SET last_error='Waiting for Job ID reconciliation' WHERE id=?",
          [outboxId],
        );
        continue;
      }
      try {
        await LocalJobQuarantine.assertReplayAllowed(
          _database,
          businessId,
          outboxId: outboxId,
        );
        final payload = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );

        if (payload['core_changed'] == true ||
            payload.containsKey('planned_hours')) {
          final jobRows = await _database
              .customSelect(
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
              )
              .get();
          if (jobRows.isNotEmpty) {
            final job = jobRows.first;
            await LocalJobQuarantine.guardReplay(
              _database,
              businessId,
              () => _api.updateJob(
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
                plannedHours:
                    num.tryParse(
                      payload['planned_hours']?.toString() ??
                          job.data['planned_hours']?.toString() ??
                          '',
                    ) ??
                    0,
              ),
              outboxId: outboxId,
            );
          }
        }

        if (payload['status_changed'] == true) {
          final statusCode = payload['status_code']?.toString() ?? '';
          if (statusCode.isNotEmpty) {
            await LocalJobQuarantine.guardReplay(
              _database,
              businessId,
              () => _api.changeJobStatus(
                businessId,
                jobId,
                statusCode,
                note: payload['status_note']?.toString(),
              ),
              outboxId: outboxId,
            );
          }
        }

        if (payload['assignment_changed'] == true) {
          final employeeId = payload['employee_id']?.toString();
          if (employeeId == null || employeeId.isEmpty) {
            await LocalJobQuarantine.guardReplay(
              _database,
              businessId,
              () => _api.clearJobAssignments(businessId, jobId),
              outboxId: outboxId,
            );
          } else {
            await LocalJobQuarantine.guardReplay(
              _database,
              businessId,
              () => _api.setPrimaryJobEmployee(businessId, jobId, employeeId),
              outboxId: outboxId,
            );
          }
        }

        await _database.transaction(() async {
          await LocalJobQuarantine.assertReplayAllowed(
            _database,
            businessId,
            outboxId: outboxId,
          );
          await _database.customStatement(
            'DELETE FROM sync_outbox WHERE id = ?',
            [outboxId],
          );
          await _database.customStatement(
            '''
            UPDATE local_jobs
            SET sync_state = 'synced'
            WHERE business_id = ? AND id = ?
            ''',
            [businessId, jobId],
          );
        });
      } catch (error) {
        if (error is LocalJobQuarantineException) rethrow;
        await _database.customStatement(
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
