import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
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
      await service.queueCustomerProfile('shop-1',id,
        name:'Changed name',phone:'5045550000',email:null,
        billingAddress:const {});
      final combined=await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE entity_type='customer_create'",
      ).get();
      expect(combined.length,1);
      expect(jsonDecode(combined.single.read<String>('payload_json'))['name'],
        'Changed name');
      await db.customStatement(
        "UPDATE sync_outbox SET attempt_count=1 WHERE entity_type='customer_create'",
      );
      await expectLater(
        service.queueCustomerProfile('shop-1',id,name:'Unsafe edit',
          billingAddress:const {}),
        throwsStateError,
      );
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
      await db.customStatement("""
        INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,
          payload_json,state,attempt_count,created_at)
        VALUES('shop-1','vehicle_create','local-vehicle-1','create',?,
          'pending',0,100)
      """,[jsonEncode({'customer_id':local,'make':'BMW','model':'X5'})]);
      await db.customStatement(
        """INSERT INTO local_jobs(id,business_id,access_scope,title,status,customer_id)
           VALUES('local-job-1','shop-1','all','Job','in_progress',?)""",
        [local],
      );
      await db.customStatement(
        """INSERT INTO local_documents(id,business_id,kind,customer_id)
           VALUES('local-invoice-1','shop-1','invoice',?)""",
        [local],
      );
      await db.customStatement(
        """INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,
           payload_json,state,attempt_count,created_at)
           VALUES('shop-1','document_draft_create','local-invoice-1','create',?,
           'pending',0,100)""",
        [jsonEncode({'customer_id':local})],
      );
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
      for (final table in <String>['local_jobs','local_documents']) {
        final rows=await db.customSelect(
          "SELECT customer_id FROM $table WHERE business_id='shop-1'",
        ).getSingle();
        expect(rows.read<String>('customer_id'),'server-customer-1');
      }
      final documentQueue=await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE entity_type='document_draft_create'",
      ).getSingle();
      expect(jsonDecode(documentQueue.read<String>('payload_json'))['customer_id'],
        'server-customer-1');
      final vehicleQueue=await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE entity_type='vehicle_create'",
      ).getSingle();
      expect(jsonDecode(vehicleQueue.read<String>('payload_json'))['customer_id'],
        'server-customer-1');
      final updatedCustomer=await db.customSelect(
        "SELECT id,sync_state FROM local_customers WHERE business_id='shop-1'",
      ).getSingle();
      expect(updatedCustomer.read<String>('id'),'server-customer-1');
      expect(updatedCustomer.read<String>('sync_state'),'synced');
      final oldCreate=await db.customSelect(
        "SELECT count(*) AS n FROM sync_outbox WHERE entity_type='customer_create'",
      ).getSingle();
      expect(oldCreate.read<int>('n'),0);
    } finally {await db.close();}
  });

  test('Customers screen does not disable Add solely because offline', () async {
    final screen = await File('lib/screens/customers/customers_screen.dart').readAsString();
    expect(screen, contains('if (_canManageCustomers && MediaQuery.viewInsetsOf(context).bottom == 0)'));
    expect(screen, contains('onPressed: _add,'));
    expect(screen, contains('FloatingActionButton.extended('));
    expect(screen, isNot(contains('onPressed: _onlineReady && _canManageCustomers ? _add : null')));
  });
}
