import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/lan_customer_vehicle_copy.dart';
import 'package:briskers_app/services/lan_record_inventory.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const shop = 'shop';

  Future<void> seedCursor(BriskersLocalDatabase db, int cursor) =>
      db.customStatement(
        "INSERT INTO local_sync_states (business_id, scope, last_server_cursor, bootstrapped) VALUES (?, 'customers_vehicles', ?, 1)",
        [shop, cursor],
      );

  String identity(String kind, String id) =>
      LanRecordInventory.recordIdentity(shop, kind, id);

  test('copies approved customer and vehicle together without overwriting or queuing a cloud write', () async {
    final sender = BriskersLocalDatabase(NativeDatabase.memory());
    final receiver = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(sender.close);
    addTearDown(receiver.close);
    await seedCursor(sender, 40);
    await seedCursor(receiver, 35);
    await sender.customStatement(
      "INSERT INTO local_customers (id, business_id, display_name, phone) VALUES "
      "('missing','shop','Alex Example','504-555-0100'),"
      "('same-id','shop','From Source',NULL),"
      "('dupe','shop','Another Customer','504-555-0123'),"
      "('protected','shop','Vehicle Key Customer',NULL)",
    );
    await sender.customStatement(
      "INSERT INTO local_vehicles (id, business_id, vin, key_password) VALUES "
      "('car','shop','1FAFP404X1F100001',NULL),"
      "('protected-car','shop','1FAFP404X1F100002','protected-key')",
    );
    await sender.customStatement(
      "INSERT INTO local_customer_vehicles (business_id,customer_id,vehicle_id) VALUES "
      "('shop','missing','car'),('shop','protected','protected-car')",
    );
    await receiver.customStatement(
      "INSERT INTO local_customers (id, business_id, display_name, phone) VALUES "
      "('same-id','shop','Receiver Has Edits',NULL),"
      "('duplicate-on-receiver','shop','Existing Customer','(504) 555-0123')",
    );
    final out = await LanCustomerVehicleCopy(sender).share(shop);
    final bundle = jsonDecode(jsonEncode(out)) as Map<String, dynamic>;
    expect(jsonEncode(bundle), isNot(contains('protected-key')));
    final approval = {
      identity('customer', 'missing'),
      identity('customer', 'same-id'),
      identity('customer', 'dupe'),
      identity('customer', 'protected'),
      identity('vehicle', 'car'),
      identity('vehicle', 'protected-car'),
    };
    final copy = LanCustomerVehicleCopy(receiver);
    final result = await copy.copyMissing(
      business: shop,
      bundle: bundle,
      approvedIdentities: approval,
    );
    expect(result, (customers: 1, vehicles: 1));
    final customers = {
      for (final row in await receiver.select(receiver.localCustomers).get())
        row.id: row.displayName,
    };
    expect(customers, {
      'same-id': 'Receiver Has Edits',
      'duplicate-on-receiver': 'Existing Customer',
      'missing': 'Alex Example',
    });
    final link = await receiver
        .select(receiver.localCustomerVehicles)
        .getSingle();
    expect((link.customerId, link.vehicleId), ('missing', 'car'));
    expect(await receiver.select(receiver.syncOutbox).get(), isEmpty);
    expect(
      (await receiver.select(receiver.localSyncStates).getSingle())
          .lastServerCursor,
      35,
    );
    expect(
      await copy.copyMissing(
        business: shop,
        bundle: bundle,
        approvedIdentities: approval,
      ),
      (customers: 0, vehicles: 0),
    );
  });

  test(
    'refuses older source evidence and leaves the receiver untouched',
    () async {
      final receiver = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(receiver.close);
      await seedCursor(receiver, 41);
      final copy = LanCustomerVehicleCopy(receiver);
      await expectLater(
        copy.copyMissing(
          business: shop,
          bundle: {
            'version': 1,
            'cursor': 40,
            'customers': [],
            'vehicles': [],
            'links': [],
          },
          approvedIdentities: const {},
        ),
        throwsStateError,
      );
      expect(await receiver.select(receiver.localCustomers).get(), isEmpty);
    },
  );
}
