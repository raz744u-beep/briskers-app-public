import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/appointment_sync_service.dart';

void main() {
  test('offline appointment edit is durable and blocks duplicate edits', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final service = AppointmentSyncService(database: db);
    try {
      await db.customStatement(
        """INSERT INTO local_appointments(
          id,business_id,customer_id,starts_at,ends_at,status,title,
          can_check_in,row_version,sync_state
        ) VALUES('appt-1','shop-1','customer-1',100,200,'confirmed',
                 'Old title',0,3,'synced')""",
      );
      final start = DateTime.utc(2026, 10, 11, 10);
      final end = DateTime.utc(2026, 10, 11, 11);
      await service.queueEdit('shop-1','appt-1',title:'New title',
          startsAt:start,endsAt:end,isOwner:true);
      final edited = await db.customSelect(
        "SELECT title,sync_state FROM local_appointments WHERE id='appt-1'",
      ).getSingle();
      expect(edited.read<String>('title'), 'New title');
      expect(edited.read<String>('sync_state'), 'pending');
      final outbox = await db.customSelect(
        "SELECT base_row_version,payload_json FROM sync_outbox WHERE entity_id='appt-1'",
      ).getSingle();
      expect(outbox.read<int>('base_row_version'), 3);
      expect(outbox.read<String>('payload_json'), contains('New title'));
      await expectLater(
        service.queueEdit('shop-1','appt-1',title:'Second edit',
            startsAt:start,endsAt:end,isOwner:true),
        throwsStateError,
      );
      final count = await db.customSelect(
        "SELECT count(*) AS n FROM sync_outbox WHERE entity_id='appt-1'",
      ).getSingle();
      expect(count.read<int>('n'), 1);
    } finally {
      await db.close();
    }
  });
}
