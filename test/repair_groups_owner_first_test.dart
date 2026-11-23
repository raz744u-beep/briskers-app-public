import 'package:briskers_app/core/briskers_colors.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/core/repair_group.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/screens/jobs/job_document_screen.dart';
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
  late BriskersLocalDatabase db;
  late LocalDocumentDetailCache cache;
  late OfflineDocumentDraftService drafts;
  late LocalRepairGroups groups;
  late String estimate;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    LocalDocumentDetailCache.sqliteWritesEnabled = true;
    cache = LocalDocumentDetailCache(database: db);
    drafts = OfflineDocumentDraftService(database: db, cache: cache);
    groups = LocalRepairGroups(database: db, cache: cache);
    estimate = await drafts.createStandaloneEstimate(
      'shop', customerId: 'customer', customerName: 'Customer',
    );
    await drafts.addLine('shop', estimate, name: 'Brake pads', quantity: 1,
      unitPrice: 100, taxRate: 0.1, lineKind: 'item');
    await drafts.addLine('shop', estimate, name: 'Installation', quantity: 2,
      unitPrice: 40, taxRate: 0, lineKind: 'labor');
  });

  tearDown(() async {
    await db.close();
    LocalDocumentDetailCache.sqliteWritesEnabled = false;
  });

  Future<Map<String, dynamic>> detail() async => (await cache.load('shop', estimate))!;
  List<Map<String, dynamic>> lines(Map<String, dynamic> estimate) =>
      (estimate['lines'] as List).cast<Map<String, dynamic>>();
  Future<String> namedGroup(String name) async {
    await groups.add('shop', estimate, name: name, description: '');
    return (await groups.groups('shop', estimate, await detail()))
        .singleWhere((group) => group.name == name).id;
  }

  test('group changes preserve line IDs, prices, totals and ordinary conversion', () async {
    final before = await detail();
    final quotedLines = lines(before);
    final brakeGroup = await namedGroup('Brake service');
    final second = await namedGroup('Later');
    await groups.move('shop', estimate, {quotedLines.first['id'] as String}, brakeGroup);
    await groups.edit('shop', estimate, brakeGroup, name: 'Front brakes', description: '');
    await groups.reorder('shop', estimate, [second, brakeGroup]);

    final reopened = LocalRepairGroups(database: db, cache: cache);
    final sections = await reopened.groups('shop', estimate, await detail());
    expect(sections.map((group) => group.name), ['Later', 'Front brakes', 'Other Items']);
    expect(sections[1].lines.single['name'], 'Brake pads');
    expect(sections[2].lines.single['name'], 'Installation');
    await groups.remove('shop', estimate, brakeGroup);
    expect((await reopened.groups('shop', estimate, await detail())).last.lines, quotedLines);
    expect((await detail())['total_amount'], 190);
    expect(lines(await detail()), quotedLines);

    await groups.move('shop', estimate, {quotedLines.first['id'] as String}, second);
    final invoice = await drafts.convertEstimateOffline('shop', estimate);
    final saved = (await cache.load('shop', invoice))!;
    expect(lines(saved).map((line) => line['name']), ['Brake pads', 'Installation']);
    expect(saved['total_amount'], 190);
  });

  test('single item can move between groups and back to Other Items offline', () async {
    final before = await detail();
    final originalLines = [
      for (final line in lines(before)) Map<String, dynamic>.from(line),
    ];
    final front = await namedGroup('Front brakes');
    final later = await namedGroup('Later');
    final laborId = originalLines.last['id'] as String;

    await groups.move('shop', estimate, {laborId}, front);
    await groups.move('shop', estimate, {laborId}, later);
    await groups.move('shop', estimate, {laborId}, later);
    var sections = await groups.groups('shop', estimate, await detail());
    expect(sections.singleWhere((group) => group.id == front).lines, isEmpty);
    expect(sections.singleWhere((group) => group.id == later).lines.single['id'], laborId);

    await groups.move('shop', estimate, {laborId}, RepairGroup.otherId);
    sections = await groups.groups('shop', estimate, await detail());
    expect(sections.singleWhere((group) => group.id == later).lines, isEmpty);
    expect(sections.last.isOther, isTrue);
    expect(sections.last.lines.map((line) => line['id']), [
      for (final line in originalLines) line['id'],
    ]);
    final after = await detail();
    expect(lines(after), originalLines);
    expect(after['total_amount'], before['total_amount']);
    expect(after['tax_amount'], before['tax_amount']);
  });

  test('sync ID replacement preserves group membership and rejects changed content', () async {
    final original = await detail();
    final before = lines(original);
    final front = await namedGroup('Front brakes');
    await groups.move('shop', estimate, {before.first['id'] as String}, front);
    final after = [
      for (final (index, line) in before.indexed)
        {...line, 'id': 'server-line-$index', 'position': index + 1},
    ];
    await expectLater(groups.remapDraft('shop', estimate, 'server-estimate', before, [
      {...after.first, 'unit_price': 101},
      after.last,
    ]), throwsStateError);
    expect((await groups.groups('shop', estimate, original)).first.lines.single['id'],
        before.first['id']);

    await groups.remapDraft('shop', estimate, 'server-estimate', before, after.reversed.toList());
    await groups.remapLine('shop', 'server-estimate', 'server-line-0', 'replacement-line');
    final sections = await groups.groups('shop', 'server-estimate', {
      'lines': [{...after.first, 'id': 'replacement-line'}, after.last],
    });
    expect(sections.first.lines.single['id'], 'replacement-line');
    expect(sections.last.id, RepairGroup.otherId);
    expect(sections.last.lines.single['id'], 'server-line-1');
    expect((await groups.groups('shop', estimate, original)).single.isOther, isTrue);
  });

  testWidgets('issued estimates show edit or explain the saved lock', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final mode = BriskersConnectionModeController.instance;
    await tester.runAsync(() async {
      debugUseLocalDatabase(db);
      await mode.setMode(BriskersConnectionMode.offline);
      final quote = await detail();
      await cache.save('shop', 'issued-editable', {
        ...quote,
        'id': 'issued-editable',
        'document_number': 'E-2010',
        'status': 'issued',
        'legacy_read_only': false,
      });
      await cache.save('shop', 'issued-unverified', {
        ...quote,
        'id': 'issued-unverified',
        'document_number': 'E-2011',
        'status': 'issued',
      }..remove('legacy_read_only'));
    });
    addTearDown(() async {
      debugUseLocalDatabase(null);
      await mode.setMode(BriskersConnectionMode.auto);
    });
    for (final (id, editable) in [('issued-editable', true), ('issued-unverified', false)]) {
      await tester.pumpWidget(MaterialApp(home: JobDocumentScreen(
        key: ValueKey(id), businessId: 'shop', documentId: id, isOwner: true,
        roleCode: 'owner',
      )));
      final actions = find.byTooltip('Estimate actions');
      for (var i = 0; i < 50 && actions.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.tap(actions);
      await tester.pumpAndSettle();
      expect(find.text('Edit estimate'), editable ? findsOneWidget : findsNothing);
      expect(find.text('Estimate editing is locked'), editable ? findsNothing : findsOneWidget);
      expect(find.text('Copy Estimate'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('an owner can move items and save an edited group at phone width', (tester) async {
    final (saved, groupId) = await tester.runAsync(() async {
      final saved = await detail();
      final groupId = await namedGroup('Front brakes');
      await groups.move('shop', estimate, {lines(saved).first['id'] as String}, groupId);
      return (saved, groupId);
    }) ?? (throw StateError('Could not prepare the estimate fixture'));
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? edited;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [
      RepairGroupPanel(
        store: groups,
        business: 'shop',
        estimate: estimate,
        editable: true,
        lines: lines(saved),
        buildLine: (line) => ListTile(
          title: Text(line['name'] as String),
          onTap: () => edited = line['id'] as String,
        ),
      ),
    ]))));
    final card = find.byKey(PageStorageKey('repair-group-$estimate-$groupId'));
    for (var i = 0; i < 30 && card.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(card, findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Brake pads').hitTestable(), findsNothing);
    await tester.tap(find.text('Front brakes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brake pads'));
    expect(edited, lines(saved).first['id']);
    final menu = find.descendant(
      of: card,
      matching: find.byTooltip('Repair group actions'),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Move items here'));
    await tester.pumpAndSettle();
    expect(find.text('Move items to Front brakes'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) {
      if (widget case Container(decoration: BoxDecoration(:final gradient))) {
        return gradient == BriskersColors.blueHeader;
      }
      return false;
    }), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Installation'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Move items'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 30 && find.text('2 items').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.descendant(of: card, matching: find.text('2 items')), findsOneWidget);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Edit group'));
    await tester.pumpAndSettle();
    final nameField = find.widgetWithText(TextFormField, 'Repair group name');
    final descriptionField = find.widgetWithText(TextFormField, 'Description');
    for (final field in [nameField, descriptionField]) {
      final input = find.descendant(of: field, matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(input).textCapitalization,
          TextCapitalization.sentences);
    }
    await tester.enterText(nameField, 'oil leaks');
    await tester.enterText(descriptionField, 'check the valve cover');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(descriptionField).dy - tester.getBottomLeft(nameField).dy,
      greaterThanOrEqualTo(16),
    );
    expect(find.text('Save group').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Save group'));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    final renamed = find.descendant(of: card, matching: find.text('Oil leaks'));
    for (var i = 0; i < 30 && renamed.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(renamed, findsOneWidget);
    final persisted = await tester.runAsync(() => groups.groups('shop', estimate, saved));
    expect(persisted?.first.name, 'Oil leaks');
    expect(persisted?.first.description, 'Check the valve cover');
    expect(persisted?.first.lines, hasLength(2));
    expect(find.text('Record authorization'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
