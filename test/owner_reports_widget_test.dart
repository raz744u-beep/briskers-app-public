import 'package:briskers_app/core/owner_report_models.dart';
import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/screens/reports/owner_reports_screen.dart';
import 'package:briskers_app/services/local_owner_reports.dart';
import 'package:briskers_app/widgets/briskers_curved_tabs.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedReports extends LocalOwnerReports {
  SavedReports(BriskersLocalDatabase database, this.snapshot) : super(database: database);
  OwnerReportData snapshot;
  int reads = 0, changes = 0;
  @override
  Future<int> revision() async => changes;
  @override
  Future<OwnerReportData> load(String business, {required bool isOwner}) async { reads++; return snapshot; }
}

OwnerReportData fixture() => OwnerReportData(business:'shop', invoices:[
  {'id':'invoice','kind':'invoice','business_id':'shop','customer_id':'c','customer_name':'Jennifer',
    'document_number':'6380','document_date':'2026-11-19','total_amount':108,'tax_amount':8,
    'lines':[{'id':'part','name':'Water pump','item_id':'pump','quantity':1,'unit_price':100,'unit_cost':50}]},
],transactions:[],jobs:[],expenses:[],labor:[]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late SavedReports reports;
  setUp(() {
    SharedPreferences.setMockInitialValues({'owner_reports_overview_v1:shop':
      '{"preset":"custom","start":"2026-11-01","end":"2026-11-30"}'});
    db=BriskersLocalDatabase(NativeDatabase.memory());
    reports=SavedReports(db,fixture());
  });
  tearDown(() async => db.close());
  Future<void> open(WidgetTester tester, {bool owner=true}) async {
    await tester.pumpWidget(MaterialApp(home:OwnerReportsScreen(businessId:'shop',isOwner:owner,
      repository:reports,sharedBottomNavigationBar:const SizedBox(key:ValueKey('installed-dock'),height:70,child:Text('Existing navigation')))));
    await tester.pumpAndSettle();
  }
  Future<void> tab(WidgetTester tester, String title) async {
    final finder=find.descendant(of:find.byType(BriskersCurvedTabs),matching:find.text(title));
    await tester.ensureVisible(finder); await tester.tap(finder); await tester.pumpAndSettle();
  }
  testWidgets('overview has four configurable slots and preserves the installed dock', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('installed-dock')),findsOneWidget);
    expect(find.byType(BriskersCurvedTabs),findsOneWidget);
    expect(find.text('Income Received'),findsOneWidget);
    expect(find.text('Sales Excl. Tax'),findsNWidgets(2));
    for(var i=0;i<4;i++) { expect(find.byKey(ValueKey('overview-report-tile-$i')),findsOneWidget); }
    expect(find.text('Filters'),findsNothing); expect(find.text('Export'),findsNothing);
    await tester.tap(find.byKey(const ValueKey('edit-overview-report-tile-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choose-report-projected')));
    await tester.pumpAndSettle();
    expect(find.text('Projected Net Income'),findsOneWidget);
    // Fixed customer/item summaries never acquire Overview's metric or edit control.
    await tab(tester,'Customers');
    expect(find.text('Total Customers'),findsOneWidget);
    expect(find.text('Projected Net Income'),findsNothing);
    expect(find.byTooltip('Change report'),findsNothing);
    await tab(tester,'Items');
    expect(find.text('Top-Selling Items'),findsOneWidget);
    expect(find.text('Projected Net Income'),findsNothing);
    expect(find.byTooltip('Change report'),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('customer and item searches use actual local results', (tester) async {
    await open(tester); await tab(tester,'Customers');
    expect(find.text('Jennifer'),findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('report-customer-search')),'no such person');
    await tester.pumpAndSettle(); expect(find.text('Jennifer'),findsNothing);
    await tab(tester,'Items');
    expect(find.text('Water pump'),findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('report-item-search')),'no such part');
    await tester.pumpAndSettle(); expect(find.text('Water pump'),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [320.0,375.0,800.0]) {
    testWidgets('reports fit a $width pixel viewport', (tester) async {
      tester.view.physicalSize=Size(width,900);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester);
      expect(tester.takeException(),isNull);
      await tab(tester,'Customers');expect(tester.takeException(),isNull);
      await tab(tester,'Items');expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('owner guard does not read data for other roles', (tester) async {
    await open(tester,owner:false);
    expect(find.text('Owner access is required.'),findsOneWidget);
    expect(reports.reads,0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('local revisions refresh results and disposal stops polling', (tester) async {
    await open(tester);final initial=reports.reads;
    reports.changes++;
    await tester.pump(const Duration(seconds:2));await tester.pumpAndSettle();
    expect(reports.reads,initial+1);
    await tester.pumpWidget(const SizedBox());
    reports.changes++;
    await tester.pump(const Duration(seconds:3));
    expect(reports.reads,initial+1);
  });
}
