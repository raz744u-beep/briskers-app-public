import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/receipt_scanning_notice.dart';
import 'package:drift/native.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/screens/settings/expense_settings_screen.dart';
import 'package:flutter/material.dart';
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

  testWidgets('payee settings can add, search, edit and deactivate in Force Offline', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    debugUseLocalDatabase(db);
    final mode = BriskersConnectionModeController.instance;
    await mode.setMode(BriskersConnectionMode.offline);
    addTearDown(() async { debugUseLocalDatabase(null); await db.close(); await mode.setMode(BriskersConnectionMode.auto); });
    Future<void> waitFor(Finder widget) async {
      for (var i=0;i<100;i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:10)));
        await tester.pump(const Duration(milliseconds:30));
        if (widget.evaluate().isNotEmpty) return;
      }
      expect(widget,findsWidgets);
    }
    const page = MaterialApp(home: CounterpartiesSettingsScreen(businessId:'shop'));
    await tester.pumpWidget(page);
    await waitFor(find.textContaining('have not been downloaded'));
    await tester.tap(find.text('Payee / payer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField,'Name'),'Shop fixture');
    await tester.tap(find.widgetWithText(FilledButton,'Save'));
    await waitFor(find.text('Shop fixture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop fixture'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField,'Name'),'New fixture');
    await tester.tap(find.text('Active'));
    await tester.tap(find.widgetWithText(FilledButton,'Save'));
    await waitFor(find.text('New fixture'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page);
    await waitFor(find.text('New fixture'));
    expect(find.textContaining('Inactive'),findsOneWidget);
    await tester.enterText(find.byType(TextField),'unrelated');
    await tester.pump();
    expect(find.text('New fixture'), findsNothing);
    await tester.enterText(find.byType(TextField),'fixture');
    await tester.pump();
    expect(find.text('New fixture'), findsOneWidget);
    expect(mode.forceOffline,isTrue);
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
