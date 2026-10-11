import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/offline_customer_vehicle_admin_service.dart';

class _FakeApi extends BriskersApi {
  String? customerUsedForVehicle;
  @override
  Future<String> createCustomerOfflineIdempotent(
    String businessId, {
    required String operationId,
    required String name,
    String? phone,
    String? email,
    Map<String,dynamic>? billingAddress,
  }) async => 'server-customer-1';

  @override
  Future<String> createVehicleOfflineIdempotent(
    String businessId,String customerId, {
    required String operationId,
    required String localVehicleId,
    required String make,
    required String model,
    int? year,
    String? vin,
    String? licensePlate,
    String? licenseState,
    num? mileage,
    String? color,
    String? keyPassword,
  }) async {
    customerUsedForVehicle=customerId;
    if(customerId!='server-customer-1') {
      throw StateError('Vehicle sync received stale customer ID');
    }
    return 'server-vehicle-1';
  }
}

void main() {
  test('customer and vehicle synchronize in one pass with rekeyed dependency', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final api=_FakeApi();
    final service=OfflineCustomerVehicleAdminService(api:api,database:db);
    try {
      final customer=await service.queueCustomerCreate(
        'shop-1',name:'Test customer',
      );
      await service.queueVehicle(
        'shop-1',customer,make:'BMW',model:'X5',
      );
      await service.flush('shop-1');
      expect(api.customerUsedForVehicle,'server-customer-1');
      final customers=await db.customSelect(
        "SELECT id FROM local_customers WHERE business_id='shop-1'",
      ).getSingle();
      expect(customers.read<String>('id'),'server-customer-1');
      final vehicles=await db.customSelect(
        "SELECT id FROM local_vehicles WHERE business_id='shop-1'",
      ).getSingle();
      expect(vehicles.read<String>('id'),'server-vehicle-1');
      final outbox=await db.customSelect(
        "SELECT count(*) AS total FROM sync_outbox WHERE business_id='shop-1'",
      ).getSingle();
      expect(outbox.read<int>('total'),0);
    } finally {await db.close();}
  });
}
