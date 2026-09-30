import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_customer_repository.dart';

void main() {
  test('local customer repository supports search total and detail', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final repository = LocalCustomerRepository(database: database);
    final now =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    await database.customStatement(
      '''
      INSERT INTO local_customers (
        id, business_id, display_name, is_company,
        email, phone, list_email, list_phone,
        billing_address_json, taxable,
        problem_flag, problem_flag_note, contacts_json,
        server_updated_at, row_version, sync_state
      ) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, 1, 1, ?, ?, ?, 3, 'synced')
      ''',
      [
        'customer-1',
        'business-1',
        'Jane Customer',
        'jane@example.com',
        '5045550100',
        'jane@example.com',
        '5045550100',
        jsonEncode({'city': 'Gretna'}),
        'Call before work',
        jsonEncode([
          {
            'kind': 'phone',
            'label': 'Mobile',
            'value': '5045550100',
            'primary': true,
          },
        ]),
        now,
      ],
    );

    await database.customStatement(
      '''
      INSERT INTO local_vehicles (
        id, business_id, year, make, model, vin,
        license_plate, license_state, mileage, color,
        server_updated_at, row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 2, 'synced')
      ''',
      [
        'vehicle-1',
        'business-1',
        2020,
        'BMW',
        'X5',
        'TESTVIN',
        'ABC123',
        'LA',
        50000,
        'Black',
        now,
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

    final total = await repository.customerTotal('business-1');
    expect(total, 1);

    final customers = await repository.customers(
      'business-1',
      search: 'jane',
    );
    expect(customers, hasLength(1));
    expect(customers.single['display_name'], 'Jane Customer');
    expect(customers.single['vehicle_count'], 1);
    expect(customers.single['problem_flag'], true);

    final detail = await repository.customerDetail(
      'business-1',
      'customer-1',
    );
    expect(detail, isNotNull);
    expect((detail!['customer'] as Map)['name'], 'Jane Customer');
    expect((detail['contacts'] as List), hasLength(1));

    final vehicles = List<dynamic>.from(detail['vehicles'] as List);
    expect(vehicles, hasLength(1));
    expect((vehicles.single as Map)['make'], 'BMW');
    expect((vehicles.single as Map)['license_state'], 'LA');

    await database.close();
  });
}
