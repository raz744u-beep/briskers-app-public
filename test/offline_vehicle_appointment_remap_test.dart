import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_customer_vehicle_admin_service.dart';

void main() {
  test('vehicle server ID remaps queued appointment in one transaction', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final service=OfflineCustomerVehicleAdminService(database:db);
    try {
      await db.customStatement("""
        INSERT INTO local_vehicles(id,business_id,make,model,sync_state)
        VALUES('local-vehicle-1','shop-1','BMW','X5','pending')
      """);
      await db.customStatement("""
        INSERT INTO local_customer_vehicles(business_id,customer_id,vehicle_id)
        VALUES('shop-1','customer-1','local-vehicle-1')
      """);
      await db.customStatement("""
        INSERT INTO local_appointments(id,business_id,customer_id,vehicle_id,
        starts_at,ends_at,status,title,can_check_in,sync_state)
        VALUES('local-appointment-1','shop-1','customer-1','local-vehicle-1',
        100,200,'confirmed','Appointment',0,'pending')
      """);
      await db.customStatement("""
        INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,
          payload_json,state,attempt_count,created_at)
        VALUES('shop-1','appointment_create','local-appointment-1','create',
        '{"vehicle_id":"local-vehicle-1"}','pending',0,100)
      """);
      await db.customStatement("""
        INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,
          payload_json,state,attempt_count,created_at)
        VALUES('shop-1','vehicle_create','local-vehicle-1','create','{}','pending',0,100)
      """);
      final rows=await db.customSelect(
        "SELECT id FROM sync_outbox WHERE entity_type='vehicle_create'",
      ).getSingle();
      await service.reconcileCreatedVehicleId('shop-1','local-vehicle-1',
        'server-vehicle-1',rows.read<int>('id'));
      final appointment=await db.customSelect(
        "SELECT vehicle_id FROM local_appointments WHERE id='local-appointment-1'",
      ).getSingle();
      expect(appointment.read<String>('vehicle_id'),'server-vehicle-1');
      final pending=await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE entity_type='appointment_create'",
      ).getSingle();
      expect(jsonDecode(pending.read<String>('payload_json'))['vehicle_id'],
        'server-vehicle-1');
      final vehicle=await db.customSelect(
        "SELECT id FROM local_vehicles WHERE business_id='shop-1'",
      ).getSingle();
      expect(vehicle.read<String>('id'),'server-vehicle-1');
      final q=await db.customSelect(
        "SELECT count(*) AS n FROM sync_outbox WHERE entity_type='vehicle_create'",
      ).getSingle();
      expect(q.read<int>('n'),0);
    } finally {await db.close();}
  });
}
