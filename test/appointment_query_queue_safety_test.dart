import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_appointment_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appointment filters and email search preserve pending work and tombstones', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = LocalAppointmentRepository(database: db);
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day, 12);
    final tomorrow = today.add(const Duration(days: 1));
    final yesterday = today.subtract(const Duration(days: 1));
    await db.customStatement(
      'INSERT INTO local_customers(id,business_id,display_name,email) '
      "VALUES ('customer','shop','Customer','customer@example.com')",
    );
    for (final item in [
      ('pending-checkin', today, 'pending'),
      ('pending-delete', today, 'pending_delete'),
      ('future', tomorrow, 'synced'),
      ('past', yesterday, 'synced'),
    ]) {
      await db.customStatement(
        'INSERT INTO local_appointments('
        'id,business_id,customer_id,starts_at,ends_at,status,title,sync_state) '
        "VALUES (?,'shop','customer',?,?,'confirmed','Inspection',?)",
        [
          item.$1,
          item.$2.millisecondsSinceEpoch ~/ 1000,
          item.$2.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          item.$3,
        ],
      );
    }
    for (final item in [
      ('pending-checkin', 'check_in'),
      ('pending-delete', 'delete'),
    ]) {
      await db.customStatement(
        'INSERT INTO sync_outbox('
        'business_id,entity_type,entity_id,operation,payload_json) '
        "VALUES ('shop','appointment',?,?,'{}')",
        [item.$1, item.$2],
      );
    }
    final queueBefore =
        (await db.customSelect('SELECT * FROM sync_outbox ORDER BY id').get())
            .map((row) => row.data)
            .toList();
    final appointmentsBefore =
        (await db
                .customSelect('SELECT * FROM local_appointments ORDER BY id')
                .get())
            .map((row) => row.data)
            .toList();

    for (var repeat = 0; repeat < 3; repeat++) {
      for (final filter in [
        'confirmed_today',
        'today',
        'upcoming',
        'past',
        'all',
      ]) {
        final rows = await repository.appointments('shop', filter: filter);
        expect(rows.any((row) => row['id'] == 'pending-delete'), isFalse);
        if (filter == 'today' || filter == 'confirmed_today') {
          expect(rows.single['id'], 'pending-checkin');
          expect(rows.single['sync_state'], 'pending');
        }
        final emailMatches = await repository.appointments(
          'shop',
          filter: filter,
          search: 'CUSTOMER@EXAMPLE.COM',
        );
        expect(
          emailMatches.map((row) => row['id']),
          rows.map((row) => row['id']),
        );
      }
    }
    expect(
      (await db.customSelect('SELECT * FROM sync_outbox ORDER BY id').get())
          .map((row) => row.data)
          .toList(),
      queueBefore,
    );
    expect(
      (await db
              .customSelect('SELECT * FROM local_appointments ORDER BY id')
              .get())
          .map((row) => row.data)
          .toList(),
      appointmentsBefore,
    );
  });
}
