import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_repair_groups.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/widgets/repair_group_panel.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('compact groups collapse and keep existing item editor callbacks', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    LocalDocumentDetailCache.sqliteWritesEnabled = true;
    final drafts = OfflineDocumentDraftService(database: db, cache: cache);
    final store = LocalRepairGroups(database: db, cache: cache);
    final id = await drafts.createStandaloneEstimate('shop', customerId: 'customer', customerName: 'Customer');
    await drafts.addLine('shop', id, name: 'Brake pads', quantity: 1,
      unitPrice: 100, taxRate: 0.1, lineKind: 'part');
    final group = await store.add('shop', id, 'Front brakes');
    final detail = (await cache.load('shop', id))!;
    await store.move('shop', id, (detail['lines'] as List).first['id'] as String, group);
    String? edited;
    bool? enabled;
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await db.close(); LocalDocumentDetailCache.sqliteWritesEnabled = false;
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [RepairGroupPanel(
      business: 'shop', estimate: id, detail: detail, editable: true, store: store,
      onEnabled: (value) => enabled = value,
      onEditLine: (line) => edited = line['name'] as String, onAddItems: () async {},
    )]))));
    for (var attempt = 0; attempt < 40 && enabled == null; attempt++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(find.text('Brake pads').hitTestable(), findsNothing);
    await tester.tap(find.text('Front brakes')); await tester.pumpAndSettle();
    await tester.tap(find.text('Brake pads')); await tester.pumpAndSettle();
    expect(edited, 'Brake pads');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Front brakes')); await tester.pumpAndSettle();
    expect(find.text('Brake pads').hitTestable(), findsNothing);
    expect((await cache.load('shop', id))!['total_amount'], 110);
  });
}
