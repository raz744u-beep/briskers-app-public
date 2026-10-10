import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

class AppointmentSyncService {
  AppointmentSyncService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
  })  : _api = api,
        _database = database ?? localDatabase;

  static const _scope = 'appointments';
  static final StreamController<String> _syncEvents =
      StreamController<String>.broadcast();

  static Stream<String> get syncEvents => _syncEvents.stream;

  final BriskersApi _api;
  final BriskersLocalDatabase _database;
  final Random _random = Random.secure();

  Future<void> pull(String businessId) async {
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

    int? cursor;
    var bootstrapped = false;
    if (stateRows.isNotEmpty) {
      cursor = stateRows.first.readNullable<int>('last_server_cursor');
      bootstrapped =
          stateRows.first.read<int>('bootstrapped') == 1;
    }

    if (!bootstrapped) {
      await _bootstrap(businessId);
      _syncEvents.add(businessId);
      return;
    }

    try {
      var pageCursor = cursor ?? 0;
      var hasMore = true;

      while (hasMore) {
        final response = await _api.syncPullAppointments(
          businessId,
          afterCursor: pageCursor,
        );

        if (response['revoke_all'] == true) {
          await _database.transaction(() async {
            await _clearCacheAndQueue(businessId);
            await _writeSyncState(
              businessId,
              cursor: null,
              bootstrapped: false,
              error: null,
            );
          });
          _syncEvents.add(businessId);
          return;
        }

        final bundles = List<dynamic>.from(
          response['bundles'] ?? const <dynamic>[],
        );
        final revoked = List<dynamic>.from(
          response['revoked_appointment_ids'] ??
              const <dynamic>[],
        ).map((value) => value.toString()).toList();

        final nextCursor =
            int.tryParse(response['next_cursor']?.toString() ?? '') ??
                pageCursor;
        hasMore = response['has_more'] == true;

        await _database.transaction(() async {
          for (final raw in bundles) {
            if (raw is! Map) continue;
            await _applyBundle(
              businessId,
              Map<String, dynamic>.from(raw),
            );
          }

          for (final appointmentId in revoked) {
            if (appointmentId.isEmpty) continue;
            await _removeAppointment(
              businessId,
              appointmentId,
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

  Future<void> _bootstrap(String businessId) async {
    String? afterAppointmentId;
    int? bootstrapCursor;
    var firstPage = true;
    var hasMore = true;

    try {
      while (hasMore) {
        final response = await _api.syncPullAppointments(
          businessId,
          afterAppointmentId: afterAppointmentId,
        );

        if (response['revoke_all'] == true) {
          await _database.transaction(() async {
            await _clearCacheAndQueue(businessId);
            await _writeSyncState(
              businessId,
              cursor: null,
              bootstrapped: false,
              error: null,
            );
          });
          return;
        }

        bootstrapCursor ??= int.tryParse(
          response['bootstrap_cursor']?.toString() ?? '',
        );

        final bundles = List<dynamic>.from(
          response['bundles'] ?? const <dynamic>[],
        );
        hasMore = response['has_more'] == true;
        final nextId =
            response['next_appointment_id']?.toString();

        await _database.transaction(() async {
          if (firstPage) {
            await _clearCacheOnly(businessId);
          }

          for (final raw in bundles) {
            if (raw is! Map) continue;
            await _applyBundle(
              businessId,
              Map<String, dynamic>.from(raw),
            );
          }
        });

        firstPage = false;
        afterAppointmentId =
            (nextId == null || nextId.isEmpty) ? null : nextId;

        if (hasMore && afterAppointmentId == null) {
          throw StateError(
            'Appointment bootstrap did not return a continuation ID.',
          );
        }
      }

      await _writeSyncState(
        businessId,
        cursor: bootstrapCursor ?? 0,
        bootstrapped: true,
        error: null,
      );
    } catch (error) {
      await _database.transaction(() async {
        await _clearCacheOnly(businessId);
        await _writeSyncState(
          businessId,
          cursor: null,
          bootstrapped: false,
          error: error.toString(),
        );
      });
      rethrow;
    }
  }

  /// A never-synchronized appointment starts as one local create operation.
  /// The server must allocate its permanent identity through an idempotent
  /// create endpoint before this queue is enabled for release.
  Future<String> queueCreate(
    String businessId, {
    required String customerId,
    String? vehicleId,
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    String? employeeId,
  }) async {
    if (customerId.isEmpty || title.trim().isEmpty ||
        !endsAt.isAfter(startsAt)) {
      throw ArgumentError('Valid customer, title, and appointment times required.');
    }
    final operationId = _operationId('appointment-create');
    final localId = 'local-appointment-$operationId';
    final payload = <String, dynamic>{
      'operation_id': operationId,
      'local_id': localId,
      'customer_id': customerId,
      'vehicle_id': vehicleId,
      'title': title.trim(),
      'description': description,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'employee_id': employeeId,
    };
    await _database.transaction(() async {
      await _database.customStatement(
        """INSERT INTO local_appointments (
          id,business_id,customer_id,vehicle_id,employee_id,
          starts_at,ends_at,status,title,description,
          can_check_in,sync_state
        ) VALUES (?,?,?,?,?,?,?,?,?,?,0,'pending')""",
        [localId,businessId,customerId,vehicleId,employeeId,
         _unix(startsAt),_unix(endsAt),'confirmed',title.trim(),description],
      );
      await _database.customStatement(
        """INSERT INTO sync_outbox (
          business_id,entity_type,entity_id,operation,payload_json,
          base_row_version,state,attempt_count,created_at,last_attempt_at,last_error
        ) VALUES (?,'appointment_create',?,'create',?,NULL,'pending',0,?,NULL,NULL)""",
        [businessId,localId,jsonEncode(payload),_unix(DateTime.now().toUtc())],
      );
    });
    _syncEvents.add(businessId);
    return localId;
  }

  /// Reassign an appointment that has never been uploaded. Both its cached
  /// record and original create payload change in the same transaction.
  Future<void> reassignPendingCreate(
    String businessId, String appointmentId, {
    required String customerId,
    String? vehicleId,
  }) async {
    if (!appointmentId.startsWith('local-appointment-') ||
        customerId.trim().isEmpty) {
      throw ArgumentError('A pending appointment and customer are required.');
    }
    await _database.transaction(() async {
      final records = await _database.customSelect(
        """SELECT job_id FROM local_appointments
           WHERE business_id=? AND id=? LIMIT 1""",
        variables: [Variable<String>(businessId),
                    Variable<String>(appointmentId)],
      ).get();
      if (records.length != 1 ||
          records.single.readNullable<String>('job_id') != null) {
        throw StateError('Appointment is missing or linked to a Job.');
      }
      final queue = await _database.customSelect(
        """SELECT id,payload_json,attempt_count,last_attempt_at
           FROM sync_outbox WHERE business_id=? AND entity_id=?
           AND entity_type='appointment_create' AND state='pending' LIMIT 1""",
        variables: [Variable<String>(businessId),
                    Variable<String>(appointmentId)],
      ).get();
      if (queue.length != 1 ||
          queue.single.read<int>('attempt_count') != 0 ||
          queue.single.readNullable<int>('last_attempt_at') != null) {
        throw StateError('Appointment creation has started synchronizing.');
      }
      final data = Map<String,dynamic>.from(
        jsonDecode(queue.single.read<String>('payload_json')) as Map);
      data['customer_id'] = customerId;
      data['vehicle_id'] = vehicleId;
      await _database.customStatement(
        'UPDATE sync_outbox SET payload_json=? WHERE id=?',
        [jsonEncode(data),queue.single.read<int>('id')],
      );
      await _database.customStatement(
        """UPDATE local_appointments SET customer_id=?,vehicle_id=?,
           customer_name=NULL,vehicle_label=NULL,
           vehicle_year=NULL,vehicle_make=NULL,vehicle_model=NULL
           WHERE business_id=? AND id=?""",
        [customerId,vehicleId,businessId,appointmentId],
      );
    });
    _syncEvents.add(businessId);
  }

  /// First stage of offline appointment editing. This records the complete
  /// requested edit atomically with its base revision. It does not attempt
  /// network writes; a server conflict-aware replay is required before this
  /// can be exposed as a completed UI workflow.
  Future<void> queueEdit(
    String businessId,
    String appointmentId, {
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    String? employeeId,
    required bool isOwner,
  }) async {
    if (!endsAt.isAfter(startsAt)) {
      throw ArgumentError('Appointment end must follow start.');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError('Appointment title is required.');
    }
    await _database.transaction(() async {
      final rows = await _database.customSelect(
        'SELECT * FROM local_appointments WHERE business_id=? AND id=? LIMIT 1',
        variables: [Variable<String>(businessId), Variable<String>(appointmentId)],
      ).get();
      if (rows.isEmpty) {
        throw StateError('Appointment is not cached on this device.');
      }
      final row = rows.single;
      if (appointmentId.startsWith('local-appointment-')) {
        final creates = await _database.customSelect(
          """SELECT id,payload_json,attempt_count,last_attempt_at
             FROM sync_outbox WHERE business_id=? AND entity_id=?
             AND entity_type='appointment_create' AND state='pending'
             LIMIT 1""",
          variables: [Variable<String>(businessId),
                      Variable<String>(appointmentId)],
        ).get();
        if (creates.length != 1 ||
            creates.single.read<int>('attempt_count') > 0 ||
            creates.single.readNullable<int>('last_attempt_at') != null) {
          throw StateError('Appointment creation is already synchronizing.');
        }
        final pendingCreate = Map<String,dynamic>.from(
          jsonDecode(creates.single.read<String>('payload_json')) as Map);
        pendingCreate['title'] = title.trim();
        pendingCreate['description'] = description;
        pendingCreate['starts_at'] = startsAt.toUtc().toIso8601String();
        pendingCreate['ends_at'] = endsAt.toUtc().toIso8601String();
        pendingCreate['employee_id'] = employeeId;
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json=? WHERE id=?',
          [jsonEncode(pendingCreate),creates.single.read<int>('id')],
        );
        await _database.customStatement(
          """UPDATE local_appointments SET title=?,description=?,starts_at=?,
             ends_at=?,employee_id=? WHERE business_id=? AND id=?""",
          [title.trim(),description,_unix(startsAt),_unix(endsAt),
           employeeId,businessId,appointmentId],
        );
        return;
      }
      final syncState = row.read<String>('sync_state');
      if (syncState == 'conflict') {
        throw StateError('Resolve the synchronization conflict first.');
      }
      final queued = await _database.customSelect(
        """SELECT id, payload_json, attempt_count, last_attempt_at
           FROM sync_outbox WHERE business_id=? AND entity_id=?
           AND entity_type='appointment_edit' AND state='pending'
           ORDER BY id LIMIT 1""",
        variables: [Variable<String>(businessId),
                    Variable<String>(appointmentId)],
      ).get();
      if (syncState != 'synced' && queued.isEmpty) {
        throw StateError('An unfinished appointment operation needs review.');
      }
      if (queued.isNotEmpty &&
          (queued.single.read<int>('attempt_count') > 0 ||
           queued.single.readNullable<int>('last_attempt_at') != null)) {
        throw StateError(
          'This edit may already have reached the server. Sync before editing again.',
        );
      }
      if (!isOwner &&
          (row.read<String>('status') != 'confirmed' ||
           row.readNullable<String>('job_id') != null)) {
        throw StateError('Owner access required for this appointment.');
      }
      final existingPayload = queued.isEmpty
          ? null
          : Map<String, dynamic>.from(
              jsonDecode(queued.single.read<String>('payload_json')) as Map);
      final op = existingPayload?['operation_id']?.toString() ??
          _operationId('appointment-edit');
      final payload = jsonEncode({
        'operation_id': op,
        'appointment_id': appointmentId,
        'title': title.trim(),
        'description': description,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(),
        'employee_id': employeeId,
      });
      if (queued.isEmpty) {
        await _database.customStatement(
          """INSERT INTO sync_outbox (
            business_id,entity_type,entity_id,operation,payload_json,
            base_row_version,state,attempt_count,created_at,last_attempt_at,last_error
          ) VALUES (?, 'appointment_edit', ?, 'update', ?, ?, 'pending', 0, ?, NULL, NULL)""",
          [businessId, appointmentId, payload,
           row.readNullable<int>('row_version'), _unix(DateTime.now().toUtc())],
        );
      } else {
        // This UUID has not been attempted, so replacing its payload cannot
        // cause a mismatched retry of an already accepted server operation.
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json=? WHERE id=?',
          [payload, queued.single.read<int>('id')],
        );
      }
      await _database.customStatement(
        """UPDATE local_appointments SET title=?,description=?,starts_at=?,
          ends_at=?,employee_id=?,sync_state='pending'
          WHERE business_id=? AND id=?""",
        [
          title.trim(), description, _unix(startsAt), _unix(endsAt),
          employeeId, businessId, appointmentId,
        ],
      );
    });
  }

  Future<void> queueCheckIn(
    String businessId,
    String appointmentId,
  ) async {
    await _database.transaction(() async {
      final rows = await _database.customSelect(
        '''
        SELECT *
        FROM local_appointments
        WHERE business_id = ? AND id = ?
        LIMIT 1
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(appointmentId),
        ],
      ).get();

      if (rows.isEmpty) {
        throw StateError('Appointment is not available on this device.');
      }

      final appointment = rows.first;
      final syncState = appointment.read<String>('sync_state');
      if (syncState == 'conflict') {
        throw StateError(
          'This appointment has a sync conflict and cannot be checked in '
          'until it is resolved.',
        );
      }

      final jobId = appointment.readNullable<String>('job_id');
      if (jobId != null && jobId.isNotEmpty) {
        throw StateError('This appointment is already linked to a job.');
      }

      final status = appointment.read<String>('status');
      if (status == 'cancelled' || status == 'no_show') {
        throw StateError('This appointment cannot be checked in.');
      }

      if (appointment.read<int>('can_check_in') != 1) {
        throw StateError(
          'This account does not have permission to check in the appointment.',
        );
      }

      final existing = await _database.customSelect(
        '''
        SELECT id, payload_json
        FROM sync_outbox
        WHERE business_id = ?
          AND entity_type = 'appointment_checkin'
          AND entity_id = ?
          AND state = 'pending'
        ORDER BY id
        LIMIT 1
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(appointmentId),
        ],
      ).get();

      if (existing.isEmpty) {
        final operationId = _operationId('checkin');
        await _database.customStatement(
          '''
          INSERT INTO sync_outbox (
            business_id, entity_type, entity_id, operation,
            payload_json, base_row_version, state, attempt_count,
            created_at, last_attempt_at, last_error
          ) VALUES (
            ?, 'appointment_checkin', ?, 'checkin', ?, ?,
            'pending', 0, ?, NULL, NULL
          )
          ''',
          [
            businessId,
            appointmentId,
            jsonEncode({
              'operation_id': operationId,
              'appointment_id': appointmentId,
            }),
            appointment.readNullable<int>('row_version'),
            _unix(DateTime.now().toUtc()),
          ],
        );
      }

      await _database.customStatement(
        '''
        UPDATE local_appointments
        SET sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [businessId, appointmentId],
      );
    });
  }

  /// Atomically retain the acknowledged appointment in the local list.
  /// Kept separate so diagnostics can exercise the real SQLite transition.
  Future<void> acknowledgeCreatedAppointment(
    String businessId, String localId, String serverId, int queueId,
  ) async {
    if (serverId.isEmpty || serverId.startsWith('local-')) {
      throw StateError('A permanent appointment ID is required.');
    }
    await _database.transaction(() async {
      final existing = await _database.customSelect(
        'SELECT id FROM local_appointments WHERE business_id=? AND id=?',
        variables: [Variable<String>(businessId), Variable<String>(serverId)],
      ).get();
      if (existing.isNotEmpty) {
        await _database.customStatement(
          'DELETE FROM local_appointments WHERE business_id=? AND id=?',
          [businessId,localId],
        );
      } else {
        await _database.customStatement(
          """UPDATE local_appointments SET id=?,sync_state='synced',
             row_version=1 WHERE business_id=? AND id=?""",
          [serverId,businessId,localId],
        );
      }
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id=? AND business_id=?',
        [queueId,businessId],
      );
    });
  }

  /// Send never-synchronized creations before queued edits/check-ins.
  /// A retry retains the original operation ID until the server confirms it.
  Future<void> flushCreates(String businessId) async {
    final rows = await _database.customSelect(
      """SELECT * FROM sync_outbox WHERE business_id=?
         AND entity_type='appointment_create'
         AND state IN ('pending','inflight') ORDER BY id""",
      variables: [Variable<String>(businessId)],
    ).get();
    for (final row in rows) {
      final queueId = row.read<int>('id');
      final localId = row.read<String>('entity_id');
      final data = Map<String,dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map);
      try {
        final serverId = await _api.syncOfflineAppointmentCreate(
          businessId,
          operationId: data['operation_id'].toString(),
          customerId: data['customer_id'].toString(),
          vehicleId: data['vehicle_id']?.toString(),
          title: data['title'].toString(),
          description: data['description']?.toString(),
          startsAt: DateTime.parse(data['starts_at'].toString()),
          endsAt: DateTime.parse(data['ends_at'].toString()),
          employeeId: data['employee_id']?.toString(),
        );
        if (serverId.isEmpty) {
          throw StateError('Server did not return appointment identity.');
        }
        await acknowledgeCreatedAppointment(
          businessId, localId, serverId, queueId,
        );
        // Ensure the new record is fetched on the normal sync pull.
        _syncEvents.add(businessId);
      } catch (error) {
        await _database.customStatement(
          """UPDATE sync_outbox SET attempt_count=attempt_count+1,
            last_attempt_at=?,last_error=? WHERE id=?""",
          [_unix(DateTime.now().toUtc()),error.toString(),queueId],
        );
        break;
      }
    }
  }

  /// Replays offline appointment edits using the authenticated revision-guarded
  /// RPC. A conflict is retained for owner review rather than overwritten.
  Future<void> flushEdits(String businessId) async {
    final rows = await _database.customSelect(
      """SELECT * FROM sync_outbox WHERE business_id=?
         AND entity_type='appointment_edit' AND state='pending' ORDER BY id""",
      variables: [Variable<String>(businessId)],
    ).get();
    for (final row in rows) {
      final outboxId = row.read<int>('id');
      final appointmentId = row.read<String>('entity_id');
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
      try {
        final version = await _api.syncOfflineAppointmentEdit(
          businessId, appointmentId,
          operationId: payload['operation_id'].toString(),
          baseVersion: row.read<int>('base_row_version'),
          title: payload['title'].toString(),
          description: payload['description']?.toString(),
          startsAt: DateTime.parse(payload['starts_at'].toString()),
          endsAt: DateTime.parse(payload['ends_at'].toString()),
          employeeId: payload['employee_id']?.toString(),
        );
        await _database.transaction(() async {
          await _database.customStatement(
            """UPDATE local_appointments SET row_version=?,
               sync_state='synced' WHERE business_id=? AND id=?
               AND sync_state='pending'""",
            [version,businessId,appointmentId],
          );
          await _database.customStatement(
            'DELETE FROM sync_outbox WHERE id=?',
            [outboxId],
          );
        });
        _syncEvents.add(businessId);
      } catch (error) {
        final message = error.toString();
        final conflict = message.contains('40001') ||
            message.contains('Appointment changed on another device');
        await _database.transaction(() async {
          await _database.customStatement(
            """UPDATE sync_outbox SET state=?,attempt_count=attempt_count+1,
               last_attempt_at=?,last_error=? WHERE id=?""",
            [conflict ? 'conflict' : 'pending',
             _unix(DateTime.now().toUtc()),message,outboxId],
          );
          if (conflict) {
            await _database.customStatement(
              """UPDATE local_appointments SET sync_state='conflict'
                 WHERE business_id=? AND id=?""",
              [businessId,appointmentId],
            );
          }
        });
        break;
      }
    }
  }

  Future<Map<String, String>> flush(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'appointment_checkin'
        AND state = 'pending'
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    final appliedJobs = <String, String>{};

    for (final queued in rows) {
      final fresh = await _database.customSelect(
        '''
        SELECT *
        FROM sync_outbox
        WHERE id = ? AND state = 'pending'
        LIMIT 1
        ''',
        variables: [
          Variable<int>(queued.read<int>('id')),
        ],
      ).get();

      if (fresh.isEmpty) continue;
      final row = fresh.first;

      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );
        final appointmentId =
            payload['appointment_id']?.toString() ?? '';
        final response = await _api.syncCheckInAppointment(
          businessId,
          appointmentId,
          operationId:
              payload['operation_id']?.toString() ?? '',
          expectedRowVersion:
              row.readNullable<int>('base_row_version'),
        );

        if (response['status']?.toString() == 'conflict') {
          await _database.transaction(() async {
            await _database.customStatement(
              '''
              UPDATE local_appointments
              SET sync_state = 'conflict'
              WHERE business_id = ? AND id = ?
              ''',
              [businessId, appointmentId],
            );
            await _database.customStatement(
              '''
              UPDATE sync_outbox
              SET state = 'conflict',
                  attempt_count = attempt_count + 1,
                  last_attempt_at = ?,
                  last_error = ?
              WHERE id = ?
              ''',
              [
                _unix(DateTime.now().toUtc()),
                jsonEncode(response),
                row.read<int>('id'),
              ],
            );
          });
          break;
        }

        final rawAppointment = response['appointment'];
        if (rawAppointment is! Map) {
          throw StateError(
            'Server did not return the checked-in appointment.',
          );
        }

        final jobId = response['job_id']?.toString() ?? '';
        await _database.transaction(() async {
          await _applyBundle(
            businessId,
            Map<String, dynamic>.from(rawAppointment),
            force: true,
          );
          await _database.customStatement(
            'DELETE FROM sync_outbox WHERE id = ?',
            [row.read<int>('id')],
          );
        });

        if (jobId.isNotEmpty) {
          appliedJobs[appointmentId] = jobId;
        }
      } catch (error) {
        await _database.customStatement(
          '''
          UPDATE sync_outbox
          SET attempt_count = attempt_count + 1,
              last_attempt_at = ?,
              last_error = ?
          WHERE id = ?
          ''',
          [
            _unix(DateTime.now().toUtc()),
            error.toString(),
            row.read<int>('id'),
          ],
        );
        break;
      }
    }

    return appliedJobs;
  }

  Future<void> _applyBundle(
    String businessId,
    Map<String, dynamic> appointment, {
    bool force = false,
  }) async {
    final id = appointment['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final existing = await _database.customSelect(
      '''
      SELECT sync_state
      FROM local_appointments
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(id),
      ],
    ).get();

    if (!force && existing.isNotEmpty) {
      final state = existing.first.read<String>('sync_state');
      if (state == 'pending' || state == 'conflict') {
        return;
      }
    }

    await _database.customStatement(
      '''
      INSERT INTO local_appointments (
        id, business_id, customer_id, vehicle_id, employee_id,
        job_id, request_id, starts_at, ends_at, status,
        title, description, customer_name, customer_phone_norm,
        vehicle_year, vehicle_make, vehicle_model, vehicle_label,
        mechanic_name, can_check_in, server_updated_at,
        row_version, sync_state
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced'
      )
      ON CONFLICT(id) DO UPDATE SET
        customer_id=excluded.customer_id,
        vehicle_id=excluded.vehicle_id,
        employee_id=excluded.employee_id,
        job_id=excluded.job_id,
        request_id=excluded.request_id,
        starts_at=excluded.starts_at,
        ends_at=excluded.ends_at,
        status=excluded.status,
        title=excluded.title,
        description=excluded.description,
        customer_name=excluded.customer_name,
        customer_phone_norm=excluded.customer_phone_norm,
        vehicle_year=excluded.vehicle_year,
        vehicle_make=excluded.vehicle_make,
        vehicle_model=excluded.vehicle_model,
        vehicle_label=excluded.vehicle_label,
        mechanic_name=excluded.mechanic_name,
        can_check_in=excluded.can_check_in,
        server_updated_at=excluded.server_updated_at,
        row_version=excluded.row_version,
        sync_state='synced'
      ''',
      [
        id,
        businessId,
        appointment['customer_id']?.toString() ?? '',
        _text(appointment['vehicle_id']),
        _text(appointment['employee_id']),
        _text(appointment['job_id']),
        _text(appointment['request_id']),
        _unix(_date(appointment['starts_at'])),
        _unix(_date(appointment['ends_at'])),
        appointment['status']?.toString() ?? 'confirmed',
        appointment['title']?.toString() ?? 'Appointment',
        _text(appointment['description']),
        _text(appointment['customer']),
        _text(appointment['customer_phone_norm']),
        _int(appointment['vehicle_year']),
        _text(appointment['vehicle_make']),
        _text(appointment['vehicle_model']),
        _text(appointment['vehicle']),
        _text(appointment['mechanic']),
        appointment['can_check_in'] == true ? 1 : 0,
        _unix(_date(appointment['updated_at'])),
        _int(appointment['row_version']),
      ],
    );
  }

  Future<void> _removeAppointment(
    String businessId,
    String appointmentId,
  ) async {
    await _database.customStatement(
      '''
      DELETE FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'appointment_checkin'
        AND entity_id = ?
      ''',
      [businessId, appointmentId],
    );
    await _database.customStatement(
      '''
      DELETE FROM local_appointments
      WHERE business_id = ? AND id = ?
      ''',
      [businessId, appointmentId],
    );
  }

  Future<void> _clearCacheOnly(String businessId) async {
    await _database.customStatement(
      'DELETE FROM local_appointments WHERE business_id = ?',
      [businessId],
    );
  }

  Future<void> _clearCacheAndQueue(String businessId) async {
    await _database.customStatement(
      '''
      DELETE FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'appointment_checkin'
      ''',
      [businessId],
    );
    await _clearCacheOnly(businessId);
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

  String _operationId(String prefix) {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    final a = _random.nextInt(0x7fffffff).toRadixString(16);
    final b = _random.nextInt(0x7fffffff).toRadixString(16);
    return '$prefix-$micros-$a-$b';
  }

  String? _text(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  int? _int(Object? value) =>
      int.tryParse(value?.toString() ?? '');

  DateTime? _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');

  int? _unix(DateTime? value) =>
      value == null
          ? null
          : value.toUtc().millisecondsSinceEpoch ~/ 1000;
}
