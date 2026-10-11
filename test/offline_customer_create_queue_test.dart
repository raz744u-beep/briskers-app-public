import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_customer_vehicle_admin_service.dart';

void main() {
  test('offline new customer queues durable creation with stable operation', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final service=OfflineCustomerVehicleAdminService(database:db);
    try {
      final id=await service.queueCustomerCreate('shop-1',
        name:'Customer test',phone:'5045551212');
      expect(id,startsWith('local-customer-'));
      final customers=await db.customSelect(
        "SELECT display_name,sync_state FROM local_customers WHERE id=?",
        variables:[Variable<String>(id)],
      ).getSingle();
      expect(customers.read<String>('display_name'),'Customer test');
      expect(customers.read<String>('sync_state'),'pending');
      final queue=await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE entity_type='customer_create'",
      ).get();
      expect(queue.length,1);
      final payload=jsonDecode(queue.single.read<String>('payload_json')) as Map;
      expect(payload['operation_id'],'customer-create-$id');
    } finally {await db.close();}
  });
  test('customer ID reconciliation updates vehicle and appointment dependencies', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final service=OfflineCustomerVehicleAdminService(database:db);
    try {
      final local=await service.queueCustomerCreate('shop-1',name:'Customer');
      await db.customStatement("""
        INSERT INTO local_customer_vehicles(business_id,customer_id,vehicle_id)
        VALUES('shop-1',?,'local-vehicle-1')
      """,[local]);
      await db.customStatement("""
        INSERT INTO local_appointments(id,business_id,customer_id,starts_at,
          ends_at,status,title,can_check_in,sync_state)
        VALUES('local-appointment-1','shop-1',?,100,200,'confirmed','Visit',0,'pending')
      """,[local]);
      await db.customStatement("""
        INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,
          payload_json,state,attempt_count,created_at)
        VALUES('shop-1','appointment_create','local-appointment-1','create',?,
          'pending',0,100)
      """,[jsonEncode({'customer_id':local})]);
      final queue=await db.customSelect(
        "SELECT id FROM sync_outbox WHERE entity_type='customer_create'",
      ).getSingle();
      await service.reconcileCreatedCustomerId(
        'shop-1',local,'server-customer-1',queue.read<int>('id'));
      final record=await db.customSelect(
        "SELECT customer_id FROM local_appointments WHERE id='local-appointment-1'",
      ).getSingle();
      expect(record.read<String>('customer_id'),'server-customer-1');
      final link=await db.customSelect(
        "SELECT customer_id FROM local_customer_vehicles WHERE business_id='shop-1'",
      ).getSingle();
      expect(link.read<String>('customer_id'),'server-customer-1');
      final dep=await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE entity_type='appointment_create'",
      ).getSingle();
      expect(jsonDecode(dep.read<String>('payload_json'))['customer_id'],
        'server-customer-1');
    } finally {await db.close();}
  });

}
