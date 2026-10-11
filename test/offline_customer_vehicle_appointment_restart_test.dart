import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/appointment_sync_service.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/offline_customer_vehicle_admin_service.dart';

class _RestartApi extends BriskersApi {
  String? vehicleCustomer;
  String? appointmentCustomer;
  String? appointmentVehicle;

  @override
  Future<String> createCustomerOfflineIdempotent(
    String businessId, {
    required String operationId,
    required String name,
    String? phone,
    String? email,
    Map<String,dynamic>? billingAddress,
  }) async => 'server-customer-restart';

  @override
  Future<String> createVehicleOfflineIdempotent(
    String businessId, String customerId, {
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
    vehicleCustomer=customerId;
    if(customerId!='server-customer-restart') {
      throw StateError('Vehicle received temporary customer ID');
    }
    return 'server-vehicle-restart';
  }

  @override
  Future<String> syncOfflineAppointmentCreate(
    String businessId, {
    required String operationId,
    required String customerId,
    String? vehicleId,
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    String? employeeId,
  }) async {
    appointmentCustomer=customerId;
    appointmentVehicle=vehicleId;
    if(customerId!='server-customer-restart' ||
        vehicleId!='server-vehicle-restart') {
      throw StateError('Appointment received temporary dependencies');
    }
    return 'server-appointment-restart';
  }
}

void main() {
  test('offline customer, vehicle and appointment survive restart and upload in order', () async {
    final dir=await Directory.systemTemp.createTemp('briskers-restart-test-');
    final file=File('${dir.path}/offline.sqlite');
    final api=_RestartApi();
    var database=BriskersLocalDatabase(NativeDatabase(file));
    try {
      final customers=OfflineCustomerVehicleAdminService(
        api:api,database:database);
      final appointments=AppointmentSyncService(api:api,database:database);
      final customerId=await customers.queueCustomerCreate(
        'shop-1',name:'Restart customer');
      final vehicleId=await customers.queueVehicle(
        'shop-1',customerId,make:'Audi',model:'Q5');
      final start=DateTime.utc(2026,10,14,10);
      await appointments.queueCreate('shop-1',
        customerId:customerId,vehicleId:vehicleId,
        title:'Restart appointment',startsAt:start,
        endsAt:start.add(const Duration(hours:1)));
      await database.close();

      database=BriskersLocalDatabase(NativeDatabase(file));
      final resumedCustomers=OfflineCustomerVehicleAdminService(
        api:api,database:database);
      final resumedAppointments=AppointmentSyncService(
        api:api,database:database);
      await resumedCustomers.flush('shop-1');
      await resumedAppointments.flushCreates('shop-1');

      expect(api.vehicleCustomer,'server-customer-restart');
      expect(api.appointmentCustomer,'server-customer-restart');
      expect(api.appointmentVehicle,'server-vehicle-restart');
      final records=await database.customSelect(
        "SELECT customer_id,vehicle_id,sync_state FROM local_appointments WHERE business_id='shop-1'",
      ).getSingle();
      expect(records.read<String>('customer_id'),'server-customer-restart');
      expect(records.read<String>('vehicle_id'),'server-vehicle-restart');
      expect(records.read<String>('sync_state'),'synced');
      final queue=await database.customSelect(
        "SELECT count(*) AS n FROM sync_outbox WHERE business_id='shop-1'",
      ).getSingle();
      expect(queue.read<int>('n'),0);
    } finally {
      await database.close();
      await dir.delete(recursive:true);
    }
  });
}
