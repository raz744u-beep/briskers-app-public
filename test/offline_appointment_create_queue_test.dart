import 'dart:convert';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
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
      await db.customStatement(
        "INSERT INTO local_customer_vehicles(business_id,customer_id,vehicle_id) VALUES('shop-test','customer-replacement','vehicle-replacement')",
      );
      await service.reassignPendingCreate(
        'shop-test',id,customerId:'customer-replacement',
        vehicleId:'vehicle-replacement',
      );
      final outbox = await db.customSelect(
        "SELECT entity_type,payload_json FROM sync_outbox WHERE business_id='shop-test'",
      ).get();
      expect(outbox.length, 1);
      expect(outbox.single.read<String>('entity_type'), 'appointment_create');
      final payload = jsonDecode(outbox.single.read<String>('payload_json')) as Map;
      expect(payload['title'], 'Updated');
      expect(payload['customer_id'], 'customer-replacement');
      expect(payload['vehicle_id'], 'vehicle-replacement');
      final reassigned = await db.customSelect(
        "SELECT customer_id,vehicle_id FROM local_appointments WHERE business_id='shop-test'",
      ).getSingle();
      expect(reassigned.read<String>('customer_id'),'customer-replacement');
      expect(reassigned.read<String>('vehicle_id'),'vehicle-replacement');
      // After a network attempt, the original create operation identity
      // must remain immutable until the server response is reconciled.
      await db.customStatement(
        "UPDATE sync_outbox SET attempt_count=1 WHERE entity_type='appointment_create'",
      );
      await expectLater(
        service.reassignPendingCreate('shop-test',id,
          customerId:'unsafe-reassignment'),
        throwsStateError,
      );
      await expectLater(
        service.queueEdit('shop-test',id,
          title:'Unsafe new payload',startsAt:start,
          endsAt:start.add(const Duration(hours:1)),isOwner:true),
        throwsStateError,
      );
      final queueIdRow = await db.customSelect(
        "SELECT id FROM sync_outbox WHERE entity_type='appointment_create'",
      ).getSingle();
      await service.acknowledgeCreatedAppointment(
        'shop-test', id, 'server-appointment-123',
        queueIdRow.read<int>('id'),
      );
      final accepted = await db.customSelect(
        "SELECT id,sync_state FROM local_appointments WHERE business_id='shop-test'",
      ).getSingle();
      expect(accepted.read<String>('id'), 'server-appointment-123');
      expect(accepted.read<String>('sync_state'), 'synced');
      final remaining = await db.customSelect(
        "SELECT count(*) AS n FROM sync_outbox WHERE business_id='shop-test'",
      ).getSingle();
      expect(remaining.read<int>('n'), 0);
      final local = await db.customSelect(
        "SELECT title FROM local_appointments WHERE business_id='shop-test'",
      ).getSingle();
      expect(local.read<String>('title'), 'Updated');
    } finally {
      await db.close();
    }
  });
  test('owner deletes unsent appointment but secretary cannot', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final service = AppointmentSyncService(database: db);
    try {
      final starts = DateTime.utc(2026,10,12,14);
      final id = await service.queueCreate('shop-test',
        customerId:'customer-1',title:'Not yet uploaded',
        startsAt:starts,endsAt:starts.add(const Duration(hours:1)));
      await expectLater(
        service.deletePendingCreate('shop-test',id,isOwner:false),
        throwsStateError);
      await service.deletePendingCreate('shop-test',id,isOwner:true);
      final records = await db.customSelect(
        "SELECT count(*) AS n FROM local_appointments WHERE business_id='shop-test'",
      ).getSingle();
      final queue = await db.customSelect(
        "SELECT count(*) AS n FROM sync_outbox WHERE business_id='shop-test'",
      ).getSingle();
      expect(records.read<int>('n'),0);
      expect(queue.read<int>('n'),0);
    } finally {
      await db.close();
    }
  });

  test('secretary cancels never-synced appointment without deleting it', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final service=AppointmentSyncService(database:db);
    try {
      final start=DateTime.utc(2026,10,12,11);
      final id=await service.queueCreate('shop-test',customerId:'customer',
        title:'Cancelled appointment',startsAt:start,
        endsAt:start.add(const Duration(hours:1)));
      await service.cancelPendingCreate('shop-test',id,canManage:true);
      final record=await db.customSelect(
        "SELECT status FROM local_appointments WHERE id=?",
        variables:[Variable<String>(id)],
      ).getSingle();
      expect(record.read<String>('status'),'cancelled');
      final queue=await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE entity_type='appointment_create'",
      ).getSingle();
      final payload=jsonDecode(queue.read<String>('payload_json')) as Map;
      expect(payload['cancel_after_create'],true);
    } finally { await db.close(); }
  });

  test('appointment upload waits for local-only vehicle dependency', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final service=AppointmentSyncService(database:db);
    try {
      expect(await service.dependenciesReadyForCreate(
        'shop-test','customer-1','local-vehicle-123'),isFalse);
      expect(await service.dependenciesReadyForCreate(
        'shop-test','local-customer-123',null),isFalse);
      expect(await service.dependenciesReadyForCreate(
        'shop-test','customer-1',null),isTrue);
    } finally { await db.close(); }
  });

}
