import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_customer_vehicle_admin_service.dart';

void main() {
  test('attempted offline vehicle create cannot change replay payload', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final service=OfflineCustomerVehicleAdminService(database:db);
    try {
      final id=await service.queueVehicle('shop-1','customer-1',
        make:'BMW',model:'X5');
      await service.queueVehicle('shop-1','customer-1',
        vehicleId:id,make:'BMW',model:'X6');
      final merged=await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE entity_type='vehicle_create'",
      ).get();
      expect(merged.length,1);
      expect(merged.single.read<String>('payload_json'),contains('"model":"X6"'));
      await db.customStatement(
        "UPDATE sync_outbox SET attempt_count=1 WHERE entity_type='vehicle_create'",
      );
      await expectLater(
        service.queueVehicle('shop-1','customer-1',
          vehicleId:id,make:'BMW',model:'X3'),
        throwsStateError,
      );
      final data=await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE entity_type='vehicle_create'",
      ).getSingle();
      expect(data.read<String>('payload_json'),contains('"model":"X6"'));
    } finally { await db.close(); }
  });
}
