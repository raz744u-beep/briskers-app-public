import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/customer_vehicle_sync_service.dart';

class _FakeCustomerVehicleApi extends BriskersApi {
  _FakeCustomerVehicleApi({this.revokeAll = false});

  final bool revokeAll;
  var calls = 0;

  @override
  Future<Map<String, dynamic>> customerVehicleCapabilities(
    String businessId,
  ) async {
    return {
      'customers_read': !revokeAll,
      'customers_create': !revokeAll,
      'customers_edit': !revokeAll,
      'vehicles_create': !revokeAll,
      'vehicles_edit': !revokeAll,
    };
  }

  @override
  Future<Map<String, dynamic>> syncPullCustomersVehicles(
    String businessId, {
    int? afterCursor,
    String? afterCustomerId,
    int limit = 250,
  }) async {
    calls++;

    if (revokeAll) {
      return {
        'mode': 'permission_revoked',
        'revoke_all': true,
        'next_cursor': 20,
        'has_more': false,
        'bundles': <dynamic>[],
        'revoked_customer_ids': <dynamic>[],
      };
    }

    if (calls == 1) {
      expect(afterCursor, isNull);
      expect(afterCustomerId, isNull);
      return {
        'mode': 'bootstrap',
        'revoke_all': false,
        'bootstrap_cursor': 10,
        'next_customer_id': 'customer-1',
        'has_more': false,
        'revoked_customer_ids': <dynamic>[],
        'bundles': [
          {
            'customer': {
              'id': 'customer-1',
              'name': 'Jane Customer',
              'display_name': 'Jane Customer',
              'is_company': false,
              'email': 'jane@example.com',
              'phone': '5045550100',
              'list_email': 'jane@example.com',
              'list_phone': '5045550100',
              'billing_address': {'city': 'Gretna'},
              'taxable': true,
              'problem_flag': true,
              'problem_flag_note': 'Call before work',
              'updated_at': '2026-09-30T20:00:00Z',
              'row_version': 3,
            },
            'contacts': [
              {
                'kind': 'phone',
                'label': 'Mobile',
                'value': '5045550100',
                'primary': true,
              },
            ],
            'vehicles': [
              {
                'id': 'vehicle-1',
                'year': 2020,
                'make': 'BMW',
                'model': 'X5',
                'vin': 'TESTVIN',
                'license_plate': 'ABC123',
                'license_state': 'LA',
                'mileage': 50000,
                'color': 'Black',
                'updated_at': '2026-09-30T20:00:00Z',
                'row_version': 2,
                'is_primary': true,
              },
            ],
          },
        ],
      };
    }

    expect(afterCursor, 10);
    return {
      'mode': 'incremental',
      'revoke_all': false,
      'next_cursor': 11,
      'has_more': false,
      'bundles': <dynamic>[],
      'revoked_customer_ids': ['customer-1'],
    };
  }
}

class _DirtyCustomerVehicleApi extends BriskersApi {
  @override
  Future<Map<String, dynamic>> customerVehicleCapabilities(
    String businessId,
  ) async {
    return {
      'customers_read': true,
      'customers_create': true,
      'customers_edit': true,
      'vehicles_create': true,
      'vehicles_edit': true,
    };
  }

  @override
  Future<Map<String, dynamic>> syncPullCustomersVehicles(
    String businessId, {
    int? afterCursor,
    String? afterCustomerId,
    int limit = 250,
  }) async {
    expect(afterCursor, 10);
    return {
      'mode': 'incremental',
      'revoke_all': false,
      'next_cursor': 11,
      'has_more': false,
      'revoked_customer_ids': <dynamic>[],
      'bundles': [
        {
          'customer': {
            'id': 'customer-1',
            'name': 'Server Name',
            'display_name': 'Server Name',
            'is_company': false,
            'email': 'server@example.com',
            'phone': '5045559999',
            'list_email': 'server@example.com',
            'list_phone': '5045559999',
            'billing_address': <String, dynamic>{},
            'taxable': true,
            'problem_flag': false,
            'problem_flag_note': '',
            'updated_at': '2026-09-30T23:40:00Z',
            'row_version': 4,
          },
          'contacts': <dynamic>[],
          'vehicles': [
            {
              'id': 'vehicle-1',
              'year': 2020,
              'make': 'BMW',
              'model': 'Server X5',
              'mileage': 40000,
              'updated_at': '2026-09-30T23:40:00Z',
              'row_version': 3,
              'is_primary': true,
            },
          ],
        },
      ],
    };
  }
}

void main() {
  test('customer vehicle sync bootstraps then revokes one customer', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeCustomerVehicleApi();
    final sync = CustomerVehicleSyncService(
      api: api,
      database: database,
    );

    await sync.pull('business-1');

    final customer = await database.customSelect(
      '''
      SELECT display_name, problem_flag, row_version
      FROM local_customers
      WHERE business_id = ? AND id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        const Variable<String>('customer-1'),
      ],
    ).getSingle();

    expect(customer.read<String>('display_name'), 'Jane Customer');
    expect(customer.read<int>('problem_flag'), 1);
    expect(customer.read<int>('row_version'), 3);

    final vehicle = await database.customSelect(
      '''
      SELECT v.make, v.model, v.row_version
      FROM local_customer_vehicles cv
      JOIN local_vehicles v
        ON v.business_id = cv.business_id
       AND v.id = cv.vehicle_id
      WHERE cv.business_id = ? AND cv.customer_id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        const Variable<String>('customer-1'),
      ],
    ).getSingle();

    expect(vehicle.read<String>('make'), 'BMW');
    expect(vehicle.read<String>('model'), 'X5');
    expect(vehicle.read<int>('row_version'), 2);

    final state = await database.customSelect(
      '''
      SELECT last_server_cursor, bootstrapped
      FROM local_sync_states
      WHERE business_id = ? AND scope = 'customers_vehicles'
      ''',
      variables: [const Variable<String>('business-1')],
    ).getSingle();
    expect(state.read<int>('last_server_cursor'), 10);
    expect(state.read<int>('bootstrapped'), 1);

    await sync.pull('business-1');

    final remaining = await database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM local_customers
      WHERE business_id = ?
      ''',
      variables: [const Variable<String>('business-1')],
    ).getSingle();
    expect(remaining.read<int>('count'), 0);

    final vehicleRemaining = await database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM local_vehicles
      WHERE business_id = ?
      ''',
      variables: [const Variable<String>('business-1')],
    ).getSingle();
    expect(vehicleRemaining.read<int>('count'), 0);

    await database.close();
  });

  test('incremental pull preserves pending customer and vehicle edits',
      () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());

    await database.customStatement(
      '''
      INSERT INTO local_sync_states (
        business_id, scope, last_server_cursor,
        metadata_json, bootstrapped
      ) VALUES (?, 'customers_vehicles', 10, ?, 1)
      ''',
      [
        'business-1',
        '{"customers_read":true,"customers_create":true,"customers_edit":true,"vehicles_create":true,"vehicles_edit":true}',
      ],
    );
    await database.customStatement(
      '''
      INSERT INTO local_customers (
        id, business_id, display_name, email,
        contacts_json, billing_address_json,
        row_version, sync_state
      ) VALUES (?, ?, ?, ?, '[]', '{}', 3, 'pending')
      ''',
      [
        'customer-1',
        'business-1',
        'Offline Name',
        'offline@example.com',
      ],
    );
    await database.customStatement(
      '''
      INSERT INTO local_vehicles (
        id, business_id, make, model, mileage,
        row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, 2, 'pending')
      ''',
      [
        'vehicle-1',
        'business-1',
        'BMW',
        'Offline X5',
        50000,
      ],
    );
    await database.customStatement(
      '''
      INSERT INTO local_customer_vehicles (
        business_id, customer_id, vehicle_id, is_primary
      ) VALUES (?, ?, ?, 1)
      ''',
      ['business-1', 'customer-1', 'vehicle-1'],
    );

    final sync = CustomerVehicleSyncService(
      api: _DirtyCustomerVehicleApi(),
      database: database,
    );
    await sync.pull('business-1');

    final customer = await database.customSelect(
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

    expect(customer.read<String>('display_name'), 'Offline Name');
    expect(customer.read<String>('email'), 'offline@example.com');
    expect(customer.read<int>('row_version'), 3);
    expect(customer.read<String>('sync_state'), 'pending');

    final vehicle = await database.customSelect(
      '''
      SELECT model, mileage, row_version, sync_state
      FROM local_vehicles
      WHERE business_id = ? AND id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        const Variable<String>('vehicle-1'),
      ],
    ).getSingle();

    expect(vehicle.read<String>('model'), 'Offline X5');
    expect(vehicle.data['mileage'], 50000.0);
    expect(vehicle.read<int>('row_version'), 2);
    expect(vehicle.read<String>('sync_state'), 'pending');

    await database.close();
  });

  test('permission revoke-all purges cached customers and vehicles', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());

    await database.customStatement(
      '''
      INSERT INTO local_customers (
        id, business_id, display_name, contacts_json,
        billing_address_json, sync_state
      ) VALUES (?, ?, ?, '[]', '{}', 'synced')
      ''',
      ['customer-1', 'business-1', 'Jane Customer'],
    );
    await database.customStatement(
      '''
      INSERT INTO local_vehicles (
        id, business_id, make, model, sync_state
      ) VALUES (?, ?, ?, ?, 'synced')
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
    await database.customStatement(
      '''
      INSERT INTO local_sync_states (
        business_id, scope, last_server_cursor, bootstrapped
      ) VALUES (?, 'customers_vehicles', 10, 1)
      ''',
      ['business-1'],
    );

    await database.customStatement(
      '''
      INSERT INTO sync_outbox (
        business_id, entity_type, entity_id, operation,
        payload_json, state, attempt_count, created_at
      ) VALUES (?, 'customer_update', ?, 'update', '{}',
                'pending', 0, ?)
      ''',
      [
        'business-1',
        'customer-1',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );
    await database.customStatement(
      '''
      INSERT INTO sync_outbox (
        business_id, entity_type, entity_id, operation,
        payload_json, state, attempt_count, created_at
      ) VALUES (?, 'vehicle_update', ?, 'update', '{}',
                'pending', 0, ?)
      ''',
      [
        'business-1',
        'vehicle-1',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );

    final sync = CustomerVehicleSyncService(
      api: _FakeCustomerVehicleApi(revokeAll: true),
      database: database,
    );

    await sync.pull('business-1');

    final customers = await database.customSelect(
      'SELECT COUNT(*) AS count FROM local_customers',
    ).getSingle();
    final vehicles = await database.customSelect(
      'SELECT COUNT(*) AS count FROM local_vehicles',
    ).getSingle();
    expect(customers.read<int>('count'), 0);
    expect(vehicles.read<int>('count'), 0);

    final outbox = await database.customSelect(
      'SELECT COUNT(*) AS count FROM sync_outbox',
    ).getSingle();
    expect(outbox.read<int>('count'), 0);

    final state = await database.customSelect(
      '''
      SELECT bootstrapped, last_server_cursor
      FROM local_sync_states
      WHERE business_id = ? AND scope = 'customers_vehicles'
      ''',
      variables: [const Variable<String>('business-1')],
    ).getSingle();
    expect(state.read<int>('bootstrapped'), 0);
    expect(state.readNullable<int>('last_server_cursor'), isNull);

    await database.close();
  });
}
