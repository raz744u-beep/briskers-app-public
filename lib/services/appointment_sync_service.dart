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
