import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/appointment_sync_service.dart';
import 'package:briskers_app/services/briskers_api.dart';

class _FakeAppointmentApi extends BriskersApi {
  _FakeAppointmentApi({
    this.conflict = false,
    this.revokeAll = false,
  });

  final bool conflict;
  final bool revokeAll;
  var pullCalls = 0;

  @override
  Future<Map<String, dynamic>> syncPullAppointments(
    String businessId, {
    int? afterCursor,
    String? afterAppointmentId,
    int limit = 250,
  }) async {
    pullCalls++;

    if (revokeAll) {
      return {
        'mode': 'permission_revoked',
        'revoke_all': true,
        'next_cursor': 20,
        'has_more': false,
        'bundles': <dynamic>[],
        'revoked_appointment_ids': <dynamic>[],
      };
    }

    if (pullCalls == 1) {
      return {
        'mode': 'bootstrap',
        'revoke_all': false,
        'bootstrap_cursor': 10,
        'next_appointment_id': 'appt-1',
        'has_more': false,
        'revoked_appointment_ids': <dynamic>[],
        'bundles': [
          {
            'id': 'appt-1',
            'customer_id': 'customer-1',
            'vehicle_id': 'vehicle-1',
            'employee_id': 'employee-1',
            'job_id': null,
            'request_id': null,
            'starts_at': '2026-10-01T14:00:00Z',
            'ends_at': '2026-10-01T15:00:00Z',
            'status': 'confirmed',
            'title': 'Brake inspection',
            'description': 'Brake noise',
            'customer': 'Jane Customer',
            'vehicle_year': 2020,
            'vehicle_make': 'BMW',
            'vehicle_model': 'X5',
            'vehicle': '2020 BMW X5',
            'mechanic': 'Mike Mechanic',
            'updated_at': '2026-09-30T20:00:00Z',
            'row_version': 3,
            'can_check_in': true,
          },
        ],
      };
    }

    return {
      'mode': 'incremental',
      'revoke_all': false,
      'next_cursor': 11,
      'has_more': false,
      'bundles': <dynamic>[],
      'revoked_appointment_ids': <dynamic>[],
    };
  }

  @override
  Future<Map<String, dynamic>> syncCheckInAppointment(
    String businessId,
    String appointmentId, {
    required String operationId,
    required int? expectedRowVersion,
  }) async {
    if (conflict) {
      return {
        'status': 'conflict',
        'reason': 'row_version_mismatch',
        'server': {
          'id': appointmentId,
          'customer_id': 'customer-1',
          'vehicle_id': 'vehicle-1',
          'employee_id': 'employee-1',
          'job_id': null,
          'request_id': null,
          'starts_at': '2026-10-01T14:00:00Z',
          'ends_at': '2026-10-01T15:00:00Z',
          'status': 'confirmed',
          'title': 'Brake inspection',
          'description': 'Brake noise',
          'customer': 'Jane Customer',
          'vehicle_year': 2020,
          'vehicle_make': 'BMW',
          'vehicle_model': 'X5',
          'vehicle': '2020 BMW X5',
          'mechanic': 'Mike Mechanic',
          'updated_at': '2026-09-30T20:30:00Z',
          'row_version': 4,
          'can_check_in': true,
        },
      };
    }

    expect(expectedRowVersion, 3);
    return {
      'status': 'applied',
      'job_id': 'job-1',
      'appointment': {
        'id': appointmentId,
        'customer_id': 'customer-1',
        'vehicle_id': 'vehicle-1',
        'employee_id': 'employee-1',
        'job_id': 'job-1',
        'request_id': null,
        'starts_at': '2026-10-01T14:00:00Z',
        'ends_at': '2026-10-01T15:00:00Z',
        'status': 'arrived',
        'title': 'Brake inspection',
        'description': 'Brake noise',
        'customer': 'Jane Customer',
        'vehicle_year': 2020,
        'vehicle_make': 'BMW',
        'vehicle_model': 'X5',
        'vehicle': '2020 BMW X5',
        'mechanic': 'Mike Mechanic',
        'updated_at': '2026-09-30T20:31:00Z',
        'row_version': 4,
        'can_check_in': true,
      },
    };
  }
}

void main() {
  test('appointment sync bootstraps local schedule', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final sync = AppointmentSyncService(
      api: _FakeAppointmentApi(),
      database: database,
    );

    await sync.pull('business-1');

    final appt = await database.customSelect(
      '''
      SELECT status, customer_name, vehicle_make,
             row_version, can_check_in, sync_state
      FROM local_appointments
      WHERE business_id = ? AND id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        const Variable<String>('appt-1'),
      ],
    ).getSingle();

    expect(appt.read<String>('status'), 'confirmed');
    expect(appt.read<String>('customer_name'), 'Jane Customer');
    expect(appt.read<String>('vehicle_make'), 'BMW');
    expect(appt.read<int>('row_version'), 3);
    expect(appt.read<int>('can_check_in'), 1);
    expect(appt.read<String>('sync_state'), 'synced');

    await database.close();
  });

  test('queued offline check-in reconciles to arrived appointment', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeAppointmentApi();
    final sync = AppointmentSyncService(
      api: api,
      database: database,
    );

    await sync.pull('business-1');
    await sync.queueCheckIn('business-1', 'appt-1');

    final pending = await database.customSelect(
      '''
      SELECT sync_state
      FROM local_appointments
      WHERE id = 'appt-1'
      ''',
    ).getSingle();
    expect(pending.read<String>('sync_state'), 'pending');

    final jobs = await sync.flush('business-1');
    expect(jobs['appt-1'], 'job-1');

    final applied = await database.customSelect(
      '''
      SELECT status, job_id, row_version, sync_state
      FROM local_appointments
      WHERE id = 'appt-1'
      ''',
    ).getSingle();

    expect(applied.read<String>('status'), 'arrived');
    expect(applied.read<String>('job_id'), 'job-1');
    expect(applied.read<int>('row_version'), 4);
    expect(applied.read<String>('sync_state'), 'synced');

    final outbox = await database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM sync_outbox
      WHERE entity_type = 'appointment_checkin'
      ''',
    ).getSingle();
    expect(outbox.read<int>('count'), 0);

    await database.close();
  });

  test('check-in conflict preserves queued local intent', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final sync = AppointmentSyncService(
      api: _FakeAppointmentApi(conflict: true),
      database: database,
    );

    await sync.pull('business-1');
    await sync.queueCheckIn('business-1', 'appt-1');
    final jobs = await sync.flush('business-1');
    expect(jobs, isEmpty);

    final local = await database.customSelect(
      '''
      SELECT status, row_version, sync_state
      FROM local_appointments
      WHERE id = 'appt-1'
      ''',
    ).getSingle();
    expect(local.read<String>('status'), 'confirmed');
    expect(local.read<int>('row_version'), 3);
    expect(local.read<String>('sync_state'), 'conflict');

    final outbox = await database.customSelect(
      '''
      SELECT state, last_error
      FROM sync_outbox
      WHERE entity_type = 'appointment_checkin'
      ''',
    ).getSingle();
    expect(outbox.read<String>('state'), 'conflict');
    expect(outbox.read<String>('last_error'), contains('row_version_mismatch'));

    await database.close();
  });

  test('permission revoke-all removes appointment cache and queue', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());

    await database.customStatement(
      '''
      INSERT INTO local_appointments (
        id, business_id, customer_id, starts_at, ends_at,
        status, title, can_check_in, row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, 'confirmed', ?, 1, 3, 'pending')
      ''',
      [
        'appt-1',
        'business-1',
        'customer-1',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        DateTime.now().toUtc().add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'Brake inspection',
      ],
    );
    await database.customStatement(
      '''
      INSERT INTO sync_outbox (
        business_id, entity_type, entity_id, operation,
        payload_json, base_row_version, state,
        attempt_count, created_at
      ) VALUES (?, 'appointment_checkin', ?, 'checkin', ?, 3, 'pending', 0, ?)
      ''',
      [
        'business-1',
        'appt-1',
        '{"operation_id":"checkin-test","appointment_id":"appt-1"}',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );
    await database.customStatement(
      '''
      INSERT INTO local_sync_states (
        business_id, scope, last_server_cursor, bootstrapped
      ) VALUES (?, 'appointments', 10, 1)
      ''',
      ['business-1'],
    );

    final sync = AppointmentSyncService(
      api: _FakeAppointmentApi(revokeAll: true),
      database: database,
    );

    await sync.pull('business-1');

    final appts = await database.customSelect(
      'SELECT COUNT(*) AS count FROM local_appointments',
    ).getSingle();
    final outbox = await database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM sync_outbox
      WHERE entity_type = 'appointment_checkin'
      ''',
    ).getSingle();

    expect(appts.read<int>('count'), 0);
    expect(outbox.read<int>('count'), 0);

    await database.close();
  });
}
