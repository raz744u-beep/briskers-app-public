import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_appointment_repository.dart';

void main() {
  test('local appointment repository rebuilds schedule row', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final repository = LocalAppointmentRepository(database: database);
    final start = DateTime.utc(2026, 10, 1, 14);
    final end = DateTime.utc(2026, 10, 1, 15);

    await database.customStatement(
      '''
      INSERT INTO local_appointments (
        id, business_id, customer_id, vehicle_id, employee_id,
        job_id, request_id, starts_at, ends_at, status,
        title, description, customer_name, customer_phone_norm,
        vehicle_year, vehicle_make, vehicle_model, vehicle_label,
        mechanic_name, can_check_in, row_version, sync_state
      ) VALUES (
        ?, ?, ?, ?, ?, NULL, NULL, ?, ?, 'confirmed',
        ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 3, 'pending'
      )
      ''',
      [
        'appt-1',
        'business-1',
        'customer-1',
        'vehicle-1',
        'employee-1',
        start.millisecondsSinceEpoch ~/ 1000,
        end.millisecondsSinceEpoch ~/ 1000,
        'Brake inspection',
        'Brake noise',
        'Jane Customer',
        '5045551234',
        2020,
        'BMW',
        'X5',
        '2020 BMW X5',
        'Mike Mechanic',
      ],
    );

    final rows = await repository.appointments('business-1');
    expect(rows, hasLength(1));
    expect(rows.single['customer'], 'Jane Customer');
    expect(rows.single['vehicle_make'], 'BMW');
    expect(rows.single['can_check_in'], true);
    expect(rows.single['sync_state'], 'pending');

    final one = await repository.appointment(
      'business-1',
      'appt-1',
    );
    expect(one, isNotNull);
    expect(one!['title'], 'Brake inspection');

    final matches = await repository.appointmentsForPhone(
      'business-1',
      '504-555-1234',
    );
    expect(matches, hasLength(1));
    expect(matches.single['id'], 'appt-1');

    final noMatches = await repository.appointmentsForPhone(
      'business-1',
      '5045559999',
    );
    expect(noMatches, isEmpty);

    await database.close();
  });
}
