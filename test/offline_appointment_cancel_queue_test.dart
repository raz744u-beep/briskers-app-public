import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/appointment_sync_service.dart';

void main() {
  test('secretary cancellation stages locally without deleting appointment', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final service = AppointmentSyncService(database: db);
    try {
      await db.customStatement("""
        INSERT INTO local_appointments(id,business_id,customer_id,starts_at,
          ends_at,status,title,can_check_in,row_version,sync_state)
        VALUES('appointment-1','shop-1','customer-1',100,200,
          'confirmed','Existing',1,7,'synced')
      """);
      await service.queueCancel('shop-1','appointment-1',canManage:true);
      final record = await db.customSelect(
        "SELECT status,sync_state FROM local_appointments WHERE id='appointment-1'",
      ).getSingle();
      expect(record.read<String>('status'),'cancelled');
      expect(record.read<String>('sync_state'),'pending');
      final op = await db.customSelect(
        "SELECT entity_type,base_row_version FROM sync_outbox WHERE entity_id='appointment-1'",
      ).getSingle();
      expect(op.read<String>('entity_type'),'appointment_cancel');
      expect(op.read<int>('base_row_version'),7);
      await expectLater(
        service.queueCancel('shop-1','appointment-1',canManage:true),
        throwsStateError,
      );
    } finally {
      await db.close();
    }
  });

  test('staff without appointment management cannot cancel', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final service = AppointmentSyncService(database:db);
    try {
      await expectLater(service.queueCancel('shop','missing',canManage:false),
        throwsStateError);
    } finally {
      await db.close();
    }
  });
}
