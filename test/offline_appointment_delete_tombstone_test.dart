import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/appointment_sync_service.dart';
import 'package:briskers_app/services/local_appointment_repository.dart';

void main() {
  test('Owner can hide an appointment whose create was already attempted', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = AppointmentSyncService(database: db);
    const localId = 'local-appointment-attempted';
    await db.customStatement("""
      INSERT INTO local_appointments(id,business_id,customer_id,starts_at,
        ends_at,status,title,can_check_in,sync_state)
      VALUES(?,'shop','customer',100,200,'confirmed','Attempted',1,'pending')
    """, [localId]);
    await db.customStatement("""
      INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,
        payload_json,last_attempt_at,attempt_count)
      VALUES('shop','appointment_create',?,'create',
        '{"operation_id":"00000000-0000-0000-0000-000000000010"}',1,2)
    """, [localId]);
    await service.queueOwnerDeletion('shop', localId, isOwner: true);
    await service.queueOwnerDeletion('shop', localId, isOwner: true);
    expect(await LocalAppointmentRepository(database: db).appointments('shop'), isEmpty);
    final queued = await db.customSelect(
      'SELECT entity_type,payload_json FROM sync_outbox',
    ).getSingle();
    expect(queued.read<String>('entity_type'), 'appointment_delete');
    expect(queued.read<String>('payload_json'), contains('"identity_delete":true'));
  });

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
      // A conflicting server response is recorded on the outbox rather than
      // changing the tombstone into a visible appointment.
      await db.customStatement(
        "UPDATE sync_outbox SET state='conflict',last_error='40001' WHERE entity_id='appt-1'",
      );
      expect(await repository.appointments('shop-1'),isEmpty);
      final pending=await db.customSelect(
        "SELECT sync_state FROM local_appointments WHERE id='appt-1'",
      ).getSingle();
      expect(pending.read<String>('sync_state'),'pending_delete');
      await expectLater(
        service.deletionConflicts('shop-1',isOwner:false),throwsStateError,
      );
      final conflicts=await service.deletionConflicts('shop-1',isOwner:true);
      expect(conflicts.length,1);
      expect(conflicts.single['appointment_id'],'appt-1');
      expect(conflicts.single['error'],'40001');


    } finally {
      await db.close();
    }
  });
}
