import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/appointment_sync_service.dart';
import 'package:briskers_app/services/local_appointment_repository.dart';

void main() {
  test('owner deletion tombstone hides synced appointment while preserving retry', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final service=AppointmentSyncService(database:db);
    final repository=LocalAppointmentRepository(database:db);
    try {
      await db.customStatement("""
        INSERT INTO local_appointments(id,business_id,customer_id,starts_at,
          ends_at,status,title,can_check_in,row_version,sync_state)
        VALUES('appt-1','shop-1','customer-1',100,200,'confirmed',
          'Old appointment',1,4,'synced')
      """);
      await expectLater(service.queueDeleteSynced('shop-1','appt-1',isOwner:false),
        throwsStateError);
      await service.queueDeleteSynced('shop-1','appt-1',isOwner:true);
      expect(await repository.appointments('shop-1'),isEmpty);
      final q=await db.customSelect(
        "SELECT entity_type,base_row_version FROM sync_outbox WHERE entity_id='appt-1'",
      ).getSingle();
      expect(q.read<String>('entity_type'),'appointment_delete');
      expect(q.read<int>('base_row_version'),4);
      final local=await db.customSelect(
        "SELECT sync_state FROM local_appointments WHERE id='appt-1'",
      ).getSingle();
      expect(local.read<String>('sync_state'),'pending_delete');
    } finally {
      await db.close();
    }
  });
}
