import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/receipt_scanning_notice.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('offline payee survives database reopen, partial download and duplicate acknowledgement', () async {
    final dir = await Directory.systemTemp.createTemp('briskers-payees');
    final file = File('${dir.path}/shop.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    var cache = LocalFinancialCache(database: db);
    addTearDown(() async { await db.close(); await dir.delete(recursive: true); });
    expect(await cache.loadOptions('shop'), isEmpty);
    await cache.saveOptions('shop', {'counterparties': [{'id': 'old', 'name': 'Existing'}]});
    final row = {'id': 'new', 'name': 'Vendor', 'active': true, 'default_surcharge_percent': 3};
    await cache.saveLocalCounterparty('shop', row);
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(file));
    cache = LocalFinancialCache(database: db);
    Future<List> people() async => (await cache.loadOptions('shop'))['counterparties'] as List;
    await cache.saveOptions('shop', {'counterparties': []});
    final pending = Map<String, dynamic>.from((await people()).last as Map);
    expect(pending['sync_state'], 'pending');
    expect(await cache.loadOptions('other'), isEmpty);
    await expectLater(cache.saveLocalCounterparty('shop', {...row, 'id': 'collision'}), throwsStateError);
    await cache.saveLocalCounterparty('shop', {...row, 'name': 'Renamed', 'active': false});
    await cache.reconcileCounterparty('shop', pending, () async => 'new');
    final edited = Map<String, dynamic>.from((await people()).last as Map);
    expect(edited['active'], false);
    expect(edited['base']['name'], 'Vendor');
    await cache.reconcileCounterparty('shop', edited, () async => 'new');
    await cache.reconcileCounterparty('shop', edited, () async => 'new');
    expect((await people()).length, 2);
    expect((await people()).last['name'], 'Renamed');
    expect((await people()).last['sync_state'], isNull);
  });

  test('scan notice defaults on and can be hidden and restored per shop', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ReceiptScanningNotice.shown('shop'), true);
    await ReceiptScanningNotice.setShown('shop', false);
    expect(await ReceiptScanningNotice.shown('shop'), false);
    expect(await ReceiptScanningNotice.shown('other'), true);
    await ReceiptScanningNotice.setShown('shop', true);
    expect(await ReceiptScanningNotice.shown('shop'), true);
  });
}
