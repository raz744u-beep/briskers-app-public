import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/offline_customer_vehicle_service.dart';

class _FakeWriteApi extends BriskersApi {
  _FakeWriteApi({
    this.customerConflict = false,
    this.vehicleConflict = false,
  });

  final bool customerConflict;
  final bool vehicleConflict;

  String? createdCustomerName;
  bool? createdCustomerFlag;
  String? createdVehicleModel;
  num? createdVehicleMileage;

  @override
  Future<Map<String, dynamic>> syncCreateCustomerWrite(
    String businessId, {
    required String customerId,
    required String operationId,
    required String name,
    String? email,
    String? phone,
    bool problemFlag = false,
    String? problemFlagNote,
  }) async {
    createdCustomerName = name;
    createdCustomerFlag = problemFlag;
    return {
      'status': 'applied',
      'customer': {
        'id': customerId,
        'name': name,
        'display_name': name,
        'is_company': false,
        'email': email,
        'phone': phone,
        'list_email': email,
        'list_phone': phone,
        'billing_address': <String, dynamic>{},
        'taxable': true,
        'problem_flag': problemFlag,
        'problem_flag_note': problemFlagNote ?? '',
        'updated_at': '2026-09-30T23:30:00Z',
        'row_version': 1,
        'contacts': [
          if (email != null)
            {
              'kind': 'email',
              'label': 'Email',
              'value': email,
              'primary': true,
            },
          if (phone != null)
            {
              'kind': 'phone',
              'label': 'Mobile',
              'value': phone,
              'primary': true,
            },
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> syncUpdateCustomerWrite(
    String businessId,
    String customerId, {
    required String operationId,
    required int? expectedRowVersion,
    required String name,
    String? email,
    String? phone,
    required bool problemFlag,
    String? problemFlagNote,
  }) async {
    if (customerConflict) {
      return {
        'status': 'conflict',
        'reason': 'row_version_mismatch',
        'server': {
          'id': customerId,
          'name': 'Server Customer',
          'row_version': (expectedRowVersion ?? 0) + 1,
        },
      };
    }

    return {
      'status': 'applied',
      'customer': {
        'id': customerId,
        'name': name,
        'display_name': name,
        'is_company': false,
        'email': email,
        'phone': phone,
        'list_email': email,
        'list_phone': phone,
        'billing_address': <String, dynamic>{},
        'taxable': true,
        'problem_flag': problemFlag,
        'problem_flag_note': problemFlagNote ?? '',
        'updated_at': '2026-09-30T23:31:00Z',
        'row_version': (expectedRowVersion ?? 0) + 1,
        'contacts': <dynamic>[],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> syncCreateVehicleWrite(
    String businessId,
    String customerId, {
    required String vehicleId,
    required String operationId,
    required String make,
    required String model,
    int? year,
    String? vin,
    String? licensePlate,
    String? licenseState,
    num? mileage,
    String? color,
  }) async {
    createdVehicleModel = model;
    createdVehicleMileage = mileage;
    return {
      'status': 'applied',
      'vehicle': {
        'id': vehicleId,
        'year': year,
        'make': make,
        'model': model,
        'vin': vin,
        'license_plate': licensePlate,
        'license_state': licenseState,
        'mileage': mileage,
        'color': color,
        'updated_at': '2026-09-30T23:32:00Z',
        'row_version': 1,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> syncUpdateVehicleWrite(
    String businessId,
    String vehicleId, {
    required String operationId,
    required int? expectedRowVersion,
    required String make,
    required String model,
    int? year,
    String? vin,
    String? licensePlate,
    String? licenseState,
    num? mileage,
    String? color,
  }) async {
    if (vehicleConflict) {
      return {
        'status': 'conflict',
        'reason': 'row_version_mismatch',
        'server': {
          'id': vehicleId,
          'make': 'BMW',
          'model': 'Server X5',
          'row_version': (expectedRowVersion ?? 0) + 1,
        },
      };
    }

    return {
      'status': 'applied',
      'vehicle': {
        'id': vehicleId,
        'year': year,
        'make': make,
        'model': model,
        'vin': vin,
        'license_plate': licensePlate,
        'license_state': licenseState,
        'mileage': mileage,
        'color': color,
        'updated_at': '2026-09-30T23:33:00Z',
        'row_version': (expectedRowVersion ?? 0) + 1,
      },
    };
  }
}

Future<void> _seedCapabilities(
  BriskersLocalDatabase database,
) async {
  await database.customStatement(
    '''
    INSERT INTO local_sync_states (
      business_id, scope, metadata_json, bootstrapped
    ) VALUES (?, 'customers_vehicles', ?, 1)
    ''',
    [
      'business-1',
      jsonEncode({
        'customers_read': true,
        'customers_create': true,
        'customers_edit': true,
        'vehicles_create': true,
        'vehicles_edit': true,
      }),
    ],
  );
}

void main() {
  test('new customer edits and vehicle edits fold into create operations',
      () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    await _seedCapabilities(database);
    final api = _FakeWriteApi();
    final service = OfflineCustomerVehicleService(
      api: api,
      database: database,
    );

    final customerId = await service.createLocalCustomer(
      'business-1',
      name: 'Initial Name',
      email: 'initial@example.com',
      phone: '5045550100',
    );

    await service.updateLocalCustomer(
      'business-1',
      customerId,
      name: 'Edited Name',
      email: 'edited@example.com',
      phone: '5045550100',
    );

    await service.setLocalProblemFlag(
      'business-1',
      customerId,
      flagged: true,
      note: 'Call before work',
    );

    final vehicleId = await service.createLocalVehicle(
      'business-1',
      customerId,
      make: 'BMW',
      model: 'X5',
      year: 2020,
      mileage: 50000,
    );

    await service.updateLocalVehicle(
      'business-1',
      vehicleId,
      make: 'BMW',
      model: 'X5 xDrive40i',
      year: 2020,
      mileage: 50010,
    );

    final queued = await database.customSelect(
      '''
      SELECT entity_type
      FROM sync_outbox
      WHERE business_id = ?
      ORDER BY id
      ''',
      variables: [const Variable<String>('business-1')],
    ).get();

    expect(queued, hasLength(2));
    expect(queued[0].read<String>('entity_type'), 'customer_create');
    expect(queued[1].read<String>('entity_type'), 'vehicle_create');

    await service.flush('business-1');

    expect(api.createdCustomerName, 'Edited Name');
    expect(api.createdCustomerFlag, true);
    expect(api.createdVehicleModel, 'X5 xDrive40i');
    expect(api.createdVehicleMileage, 50010);

    final customer = await database.customSelect(
      '''
      SELECT display_name, problem_flag, row_version, sync_state
      FROM local_customers
      WHERE business_id = ? AND id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        Variable<String>(customerId),
      ],
    ).getSingle();
    expect(customer.read<String>('display_name'), 'Edited Name');
    expect(customer.read<int>('problem_flag'), 1);
    expect(customer.read<int>('row_version'), 1);
    expect(customer.read<String>('sync_state'), 'synced');

    final vehicle = await database.customSelect(
      '''
      SELECT model, mileage, row_version, sync_state
      FROM local_vehicles
      WHERE business_id = ? AND id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        Variable<String>(vehicleId),
      ],
    ).getSingle();
    expect(vehicle.read<String>('model'), 'X5 xDrive40i');
    expect(vehicle.data['mileage'], 50010.0);
    expect(vehicle.read<int>('row_version'), 1);
    expect(vehicle.read<String>('sync_state'), 'synced');

    final outbox = await database.customSelect(
      'SELECT COUNT(*) AS count FROM sync_outbox',
    ).getSingle();
    expect(outbox.read<int>('count'), 0);

    await database.close();
  });

  test('customer update conflict preserves local edit', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    await _seedCapabilities(database);
    final service = OfflineCustomerVehicleService(
      api: _FakeWriteApi(customerConflict: true),
      database: database,
    );

    await database.customStatement(
      '''
      INSERT INTO local_customers (
        id, business_id, display_name, email, contacts_json,
        billing_address_json, row_version, sync_state
      ) VALUES (?, ?, ?, ?, '[]', '{}', 3, 'synced')
      ''',
      [
        'customer-1',
        'business-1',
        'Old Name',
        'old@example.com',
      ],
    );

    await service.updateLocalCustomer(
      'business-1',
      'customer-1',
      name: 'Offline Name',
      email: 'offline@example.com',
    );
    await service.flush('business-1');

    final row = await database.customSelect(
      '''
      SELECT display_name, email, row_version, sync_state
      FROM local_customers
      WHERE business_id = ? AND id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        const Variable<String>('customer-1'),
      ],
    ).getSingle();

    expect(row.read<String>('display_name'), 'Offline Name');
    expect(row.read<String>('email'), 'offline@example.com');
    expect(row.read<int>('row_version'), 3);
    expect(row.read<String>('sync_state'), 'conflict');

    final outbox = await database.customSelect(
      '''
      SELECT state, last_error
      FROM sync_outbox
      WHERE entity_type = 'customer_update'
      ''',
    ).getSingle();
    expect(outbox.read<String>('state'), 'conflict');
    expect(outbox.read<String>('last_error'),
        contains('row_version_mismatch'));

    await database.close();
  });

  test('vehicle update conflict preserves local edit', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    await _seedCapabilities(database);
    final service = OfflineCustomerVehicleService(
      api: _FakeWriteApi(vehicleConflict: true),
      database: database,
    );

    await database.customStatement(
      '''
      INSERT INTO local_customers (
        id, business_id, display_name, contacts_json,
        billing_address_json, row_version, sync_state
      ) VALUES (?, ?, ?, '[]', '{}', 1, 'synced')
      ''',
      ['customer-1', 'business-1', 'Customer'],
    );
    await database.customStatement(
      '''
      INSERT INTO local_vehicles (
        id, business_id, make, model, row_version, sync_state
      ) VALUES (?, ?, ?, ?, 2, 'synced')
      ''',
      ['vehicle-1', 'business-1', 'BMW', 'X5'],
    );
    await database.customStatement(
      '''
      INSERT INTO local_customer_vehicles (
        business_id, customer_id, vehicle_id, is_primary
      ) VALUES (?, ?, ?, 1)
      ''',
      ['business-1', 'customer-1', 'vehicle-1'],
    );

    await service.updateLocalVehicle(
      'business-1',
      'vehicle-1',
      make: 'BMW',
      model: 'Offline X5',
    );
    await service.flush('business-1');

    final row = await database.customSelect(
      '''
      SELECT model, row_version, sync_state
      FROM local_vehicles
      WHERE business_id = ? AND id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        const Variable<String>('vehicle-1'),
      ],
    ).getSingle();

    expect(row.read<String>('model'), 'Offline X5');
    expect(row.read<int>('row_version'), 2);
    expect(row.read<String>('sync_state'), 'conflict');

    await database.close();
  });

  test('offline writes require the last known permission snapshot', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final service = OfflineCustomerVehicleService(
      api: _FakeWriteApi(),
      database: database,
    );

    expect(
      () => service.createLocalCustomer(
        'business-1',
        name: 'No Permission Snapshot',
      ),
      throwsA(isA<StateError>()),
    );

    await database.close();
  });
}
