import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/appointment_sync_service.dart';

void main() {
  test('unsynced appointment edits update one create operation', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final service = AppointmentSyncService(database: db);
    try {
      final start = DateTime.utc(2026, 10, 12, 9);
      final id = await service.queueCreate('shop-test',
        customerId: 'customer-test',
        title: 'Initial',
        startsAt: start,
        endsAt: start.add(const Duration(hours: 1)),
      );
      expect(id, startsWith('local-appointment-'));
      await service.queueEdit('shop-test', id,
        title: 'Updated',
        startsAt: start.add(const Duration(hours: 2)),
        endsAt: start.add(const Duration(hours: 3)),
        isOwner: false,
      );
      final outbox = await db.customSelect(
        "SELECT entity_type,payload_json FROM sync_outbox WHERE business_id='shop-test'",
      ).get();
      expect(outbox.length, 1);
      expect(outbox.single.read<String>('entity_type'), 'appointment_create');
      final payload = jsonDecode(outbox.single.read<String>('payload_json')) as Map;
      expect(payload['title'], 'Updated');
      expect(payload['customer_id'], 'customer-test');
      final local = await db.customSelect(
        "SELECT title FROM local_appointments WHERE business_id='shop-test'",
      ).getSingle();
      expect(local.read<String>('title'), 'Updated');
    } finally {
      await db.close();
    }
  });
}
