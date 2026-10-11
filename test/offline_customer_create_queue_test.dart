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
}
