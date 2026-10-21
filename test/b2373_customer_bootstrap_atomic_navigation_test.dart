import 'dart:async';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/customer_vehicle_sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _PagedApi extends BriskersApi {
  bool failOnSecond = true;
  int requests = 0;
  final Completer<void> enteredSecondPage = Completer<void>();
  final Completer<void> releaseSecondPage = Completer<void>();
  bool holdSecondPage = false;

  Map<String, dynamic> _bundle(String id) => {
    'customer': {
      'id': id,
      'name': 'Customer $id',
      'display_name': 'Customer $id',
      'is_company': false,
    },
    'vehicles': <dynamic>[],
    'contacts': <dynamic>[],
  };

  @override
  Future<Map<String, dynamic>> syncPullCustomersVehicles(
    String businessId, {
    int? afterCursor,
    String? afterCustomerId,
    int limit = 250,
  }) async {
    requests++;
    if (afterCustomerId == null) {
      return {
        'mode': 'bootstrap',
        'bootstrap_cursor': 19,
        'next_customer_id': 'new-1',
        'has_more': true,
        'bundles': [_bundle('new-1')],
      };
    }
    if (!enteredSecondPage.isCompleted) enteredSecondPage.complete();
    if (holdSecondPage) await releaseSecondPage.future;
    if (failOnSecond) throw StateError('Synthetic page-two disconnect');
    return {
      'mode': 'bootstrap',
      'bootstrap_cursor': 19,
      'has_more': false,
      'bundles': [_bundle('new-2')],
    };
  }
}

Future<void> _insertCustomer(
  BriskersLocalDatabase db, String id, {
  String syncState = 'synced',
}) async {
  await db.customStatement(
    "INSERT INTO local_customers("
    "id,business_id,display_name,contacts_json,billing_address_json,sync_state) "
    "VALUES (?, 'shop', ?, '[]', '{}', ?)",
    [id, id, syncState],
  );
}

Future<List<String>> _ids(BriskersLocalDatabase db) async {
  final rows = await db.customSelect(
    "SELECT id FROM local_customers WHERE business_id='shop' ORDER BY id",
  ).get();
  return rows.map((row) => row.read<String>('id')).toList();
}

void main() {
  test('multi-page failure preserves verified cache and prior successful date',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _PagedApi();
    final sync = CustomerVehicleSyncService(api: api, database: db);
    try {
      await _insertCustomer(db, 'existing-verified');
      await _insertCustomer(db, 'local-pending', syncState: 'pending');
      await db.customStatement(
        "INSERT INTO local_sync_states "
        "(business_id,scope,last_server_cursor,last_pull_at,bootstrapped) "
        "VALUES ('shop','customers_vehicles',7,1730000000,0)",
      );
      await expectLater(sync.pull('shop'), throwsStateError);
      expect(await _ids(db), ['existing-verified', 'local-pending']);
      final status = await db.customSelect(
        "SELECT last_pull_at,bootstrapped,last_error FROM local_sync_states "
        "WHERE business_id='shop' AND scope='customers_vehicles'",
      ).getSingle();
      expect(status.read<int>('last_pull_at'), 1730000000);
      expect(status.read<int>('bootstrapped'), 0);
      expect(status.read<String>('last_error'),
          contains('Synthetic page-two disconnect'));

      // A successful retry commits a complete new directory, but pending
      // locally created customers remain separate and are not deleted.
      api.failOnSecond = false;
      await sync.pull('shop');
      expect(await _ids(db), ['local-pending', 'new-1', 'new-2']);
      final completed = await db.customSelect(
        "SELECT bootstrapped,last_server_cursor,last_error "
        "FROM local_sync_states WHERE business_id='shop' "
        "AND scope='customers_vehicles'",
      ).getSingle();
      expect(completed.read<int>('bootstrapped'), 1);
      expect(completed.read<int>('last_server_cursor'), 19);
      expect(completed.readNullable<String>('last_error'), isNull);
    } finally {
      await db.close();
    }
  });

  test('while page two downloads, old directory remains complete',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _PagedApi()..failOnSecond = false
      ..holdSecondPage = true;
    try {
      await _insertCustomer(db, 'existing-verified');
      final one = CustomerVehicleSyncService(api: api, database: db);
      final two = CustomerVehicleSyncService(api: api, database: db);
      final pull1 = one.pull('shop');
      await api.enteredSecondPage.future;
      // Second screen joins the same in-flight customer transfer.
      final pull2 = two.pull('shop');
      expect(await _ids(db), ['existing-verified']);
      api.releaseSecondPage.complete();
      await Future.wait([pull1, pull2]);
      expect(api.requests, 2);
      expect(await _ids(db), ['new-1', 'new-2']);
    } finally {
      if (!api.releaseSecondPage.isCompleted) api.releaseSecondPage.complete();
      await db.close();
    }
  });

  test('Customers dock changes screens before unread IDs are queried', () {
    final shell = File('lib/screens/shell_screen.dart').readAsStringSync();
    final begin = shell.indexOf('void _selectCustomersFromDock() {');
    final end = shell.indexOf('void _goTo(int index)', begin);
    final body = shell.substring(begin, end);
    final navigate = body.indexOf('_goTo(1);');
    final lookup = body.indexOf('unawaited(_openCustomers(request));');
    expect(navigate, greaterThan(0));
    expect(lookup, greaterThan(navigate));
    expect(shell, contains('_customersRefreshToken++;'));

    final customers = File('lib/screens/customers/customers_screen.dart')
        .readAsStringSync();
    expect(customers, contains(
      'if (BriskersConnectionModeController.instance.forceOffline) {'));
    expect(customers, contains('_rows ??= const <Map<String, dynamic>>[];'));
    expect(customers, contains("description.contains('failed host lookup')"));
    expect(customers, contains('network/DNS issue'));
    expect(customers, contains('query == _search.text.trim()'));
    expect(customers, contains('++_loadRequest;'));
    expect(customers, contains('search: query, limit: 100'));
    expect(customers, contains('_search.text.trim() != query'));
  });
}
