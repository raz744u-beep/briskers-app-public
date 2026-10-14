import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/customer_notification_service.dart';
import 'package:briskers_app/services/local_customer_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 14, 12);
  final baseline = now.millisecondsSinceEpoch ~/ 1000;
  late BriskersLocalDatabase db;

  CustomerNotificationService inbox({
    String user = 'owner',
    String shop = 'shop',
  }) => CustomerNotificationService(
    businessId: shop,
    userId: user,
    database: db,
    now: () => now,
  );

  Future<void> customer(
    String id, {
    int? created,
    String shop = 'shop',
    String sync = 'synced',
  }) => db.customStatement(
    'INSERT INTO local_customers(id,business_id,display_name,created_at,sync_state) VALUES(?,?,?,?,?)',
    [id, shop, id, created ?? baseline + 1, sync],
  );

  Future<void> bootstrap({String shop = 'shop', int complete = 1}) =>
      db.customStatement(
        "INSERT OR REPLACE INTO local_sync_states(business_id,scope,bootstrapped) VALUES(?,'customers_vehicles',?)",
        [shop, complete],
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    await bootstrap();
  });
  tearDown(() => db.close());

  test('initial historical snapshot is baseline; one or many new IDs persist', () async {
    await customer('historic');
    expect(await inbox().unreadCustomerIds(), isEmpty);
    await customer('arrival-1');
    await customer('arrival-2');
    expect(
      await inbox().unreadCustomerIds(),
      unorderedEquals(['arrival-1', 'arrival-2']),
    );
    // Recreating the service simulates navigation/resume without an in-memory cursor.
    expect(
      await inbox().unreadCustomerIds(),
      unorderedEquals(['arrival-1', 'arrival-2']),
    );
    await inbox().markReviewed(['arrival-1']);
    expect(await inbox().unreadCustomerIds(), ['arrival-2']);
    await db.customStatement(
      "UPDATE local_customers SET display_name='Updated' WHERE id='arrival-1'",
    );
    expect(await inbox().unreadCustomerIds(), ['arrival-2']);
  });

  test(
    'badge read and normal filtered search never consume arrivals',
    () async {
      await inbox().unreadCustomerIds();
      await customer('arrival');
      expect(await inbox().unreadCustomerIds(), ['arrival']);
      final repository = LocalCustomerRepository(database: db);
      expect(await repository.customers('shop', search: 'unrelated'), isEmpty);
      expect(
        (await repository.customersByIds('shop', ['arrival'])).single['id'],
        'arrival',
      );
      expect(await inbox().unreadCustomerIds(), ['arrival']);
    },
  );

  test('review snapshot cannot consume a later arrival; concurrent refresh is safe', () async {
    await inbox().unreadCustomerIds();
    await customer('first');
    final reviewSnapshot = await inbox().unreadCustomerIds();
    await customer('later');
    await Future.wait([
      inbox().markReviewed(reviewSnapshot),
      inbox().unreadCustomerIds(),
    ]);
    expect(await inbox().unreadCustomerIds(), ['later']);
  });

  test('read state is isolated by both user and business', () async {
    await bootstrap(shop: 'other');
    await inbox().unreadCustomerIds();
    await inbox(user: 'office').unreadCustomerIds();
    await inbox(shop: 'other').unreadCustomerIds();
    await customer('arrival');
    await customer('other-arrival', shop: 'other');
    await inbox().unreadCustomerIds();
    await inbox().markReviewed(['arrival']);
    expect(await inbox().unreadCustomerIds(), isEmpty);
    expect(await inbox(user: 'office').unreadCustomerIds(), ['arrival']);
    expect(await inbox(shop: 'other').unreadCustomerIds(), ['other-arrival']);
    expect(await inbox(user: '').unreadCustomerIds(), isEmpty);
  });

  test('historical downloads and local creation do not alert; revoked IDs disappear', () async {
    await inbox().unreadCustomerIds();
    await customer('old-import', created: baseline - 86400);
    await customer('local-customer-offline', sync: 'pending');
    await db.customStatement(
      "INSERT INTO local_customers(id,business_id,display_name) VALUES('unknown-date','shop','Unknown')",
    );
    await customer('arrival');
    expect(await inbox().unreadCustomerIds(), ['arrival']);
    await inbox().markReviewed(['arrival']);
    await db.customStatement("DELETE FROM local_customers WHERE id='arrival'");
    expect(await inbox().unreadCustomerIds(), isEmpty);
    await customer('arrival');
    expect(await inbox().unreadCustomerIds(), isEmpty);
  });

  test('partial bootstrap is not consumed; rebuilt import suppresses only new baseline IDs', () async {
    await inbox().unreadCustomerIds();
    await customer('unreviewed');
    expect(await inbox().unreadCustomerIds(), ['unreviewed']);
    await bootstrap(complete: 0);
    await customer('reimported-with-new-id');
    expect(await inbox().unreadCustomerIds(), ['unreviewed']);
    await bootstrap();
    await db.customStatement(
      "INSERT INTO local_sync_states(business_id,scope,last_server_cursor,bootstrapped) VALUES('shop','customer_notification_baseline',100,1)",
    );
    expect(await inbox().unreadCustomerIds(), ['unreviewed']);
    await customer('post-bootstrap');
    expect(
      await inbox().unreadCustomerIds(),
      unorderedEquals(['unreviewed', 'post-bootstrap']),
    );
  });

  test(
    'unread and reviewed IDs survive database close and offline restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'customer-inbox-',
      );
      final file = File('${directory.path}/cache.sqlite');
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      await bootstrap();
      await inbox().unreadCustomerIds();
      await customer('read');
      await customer('unread');
      await inbox().unreadCustomerIds();
      await inbox().markReviewed(['read']);
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      expect(await inbox().unreadCustomerIds(), ['unread']);
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase.memory());
      await directory.delete(recursive: true);
    },
  );
}
