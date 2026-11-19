import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/core/document_presentation.dart';
import 'package:briskers_app/core/vehicle_invoice_repair_search.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/screens/customers/customer_detail_screen.dart';
import 'package:briskers_app/screens/jobs/job_document_screen.dart';
import 'package:briskers_app/services/local_document_party_identity.dart';
import 'package:briskers_app/services/customer_document_summary_service.dart';
import 'package:briskers_app/services/local_customer_navigation_identity.dart';
import 'package:briskers_app/services/local_customer_vehicle_identity.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/duplicate_number_fixture.dart';

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Customer navigation/history must remain offline');
}

Future<void> _seed(BriskersLocalDatabase db, {bool aliases = true, String? creationVehicle = 'audi'}) async {
  await seedDuplicateNumbers(db);
  await db.customStatement("INSERT INTO local_vehicles(id,business_id,year,make,model,vin) VALUES"
      "('audi','shop',2015,'Audi','A5','TEST-VIN'),('porsche','shop',2018,'Porsche','Macan','OTHER-VIN')");
  await db.customStatement("INSERT INTO local_customer_vehicles(business_id,customer_id,vehicle_id) VALUES"
      "('shop','dakota','audi'),('shop','tyra','porsche')");
  await LocalCustomerVehicleIdentity(db).save('shop','local-vehicle-original','audi');
  if (!aliases) await db.customStatement('DELETE FROM local_customer_vehicle_create_ids');
  final createRow = await db.customSelect("SELECT id,payload_json FROM sync_outbox WHERE entity_type='document_draft_create'").getSingle();
  final create = jsonDecode(createRow.read<String>('payload_json')) as Map;
  await db.customStatement('UPDATE sync_outbox SET payload_json=? WHERE id=?',
    [jsonEncode({...create,'vehicle_id':creationVehicle}),createRow.read<int>('id')]);
  await db.customStatement("UPDATE local_jobs SET vehicle_id='audi',vehicle_label='2015 Audi A5',job_number='J-62' WHERE id=?",[duplicateJob]);
  await db.customStatement("UPDATE local_jobs SET vehicle_id='porsche' WHERE id=?",[retainedJob]);
  await db.customStatement("UPDATE local_documents SET document_number='6382' WHERE id=?",[duplicateInvoice]);
  final raw = jsonDecode((await LocalDocumentSqlStore.read(db,duplicateSnapshotKey))!) as Map;
  await LocalDocumentSqlStore.write(db,duplicateSnapshotKey,jsonEncode({...raw,
    'document_number':'6382','job_number':'J-62','vehicle_id':'local-vehicle-original',
    'lines':[{'id':'original-line','name':'Original service','line_kind':'labor','quantity':1,'net_amount':505.00}],
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late HttpOverrides? previousHttp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalDocumentDetailCache.sqliteWritesEnabled = true;
    db = BriskersLocalDatabase(NativeDatabase.memory());
    debugUseLocalDatabase(db);
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = _NoNetwork();
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
  });
  tearDown(() async {
    debugUseLocalDatabase(null);
    await db.close();
    HttpOverrides.global = previousHttp;
    LocalDocumentDetailCache.sqliteWritesEnabled = false;
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);
  });

  Future<List<Map<String,dynamic>>> rows(String table) async =>
      (await db.customSelect('SELECT * FROM $table').get()).map((r)=>r.data).toList();

  test('closed invoice appears for its canonical vehicle and finalized receipt stays finalized on repeat hydration', () async {
    await _seed(db);
    final raw = await LocalDocumentSqlStore.read(db,duplicateSnapshotKey);
    final before = {for (final table in ['local_documents','local_jobs','sync_outbox',
      'local_invoice_closed_receipts','local_invoice_closures','local_finalized_invoice_income',
      'regular_payroll_paid_work','local_financial_cache']) table: await rows(table)};
    final summaries = CustomerDocumentSummaryService(database:db);
    var documents = await summaries.forCustomer('shop','dakota',includeClosed:true);
    expect(documents,hasLength(1));
    for (var repeat=0;repeat<3;repeat++) {
      final invoice=documents.single;
      expect(invoice['document_number'],'6382');
      expect(invoice['vehicle_id'],'audi');
      expect(invoice['customer_id'],'dakota');
      final view=DocumentPresentation(invoice);
      expect(view.isClosed,true); expect(view.finalizedCents,55424);
      expect(view.pendingCents,0); expect(view.balanceDueCents,0);
      expect(VehicleInvoiceRepairSearch.forVehicle(documents,vehicleId:'audi'),hasLength(1));
      expect(VehicleInvoiceRepairSearch.forVehicle(documents,vehicleId:'porsche'),isEmpty);
      expect((invoice['payments'] as List).single['state'],'posted');
      documents=[await summaries.hydrate('shop',invoice)];
    }
    expect(await LocalDocumentSqlStore.read(db,duplicateSnapshotKey),raw);
    for (final table in before.keys) { expect(await rows(table),before[table],reason:table); }
  });

  test('job customer link uses its current exact index even without the old customer alias', () async {
    await _seed(db);
    await db.customStatement('DELETE FROM local_customer_vehicle_create_ids');
    final identity=LocalCustomerNavigationIdentity(db);
    final before=await rows('local_jobs');
    expect(await identity.customer('shop','local-customer-original',localJobId:duplicateJob),'dakota');
    expect(await identity.customer('other-shop','local-customer-original',localJobId:duplicateJob),'local-customer-original');
    expect(await rows('local_jobs'),before);
  });

  test('only proven aliases normalize a saved customer and vehicle; wrong customer detail is rejected', () async {
    await _seed(db);
    final identity=LocalCustomerNavigationIdentity(db);
    final saved={'customer':{'id':'local-customer-original','name':'Dakota Spinder'},
      'vehicles':[{'id':'local-vehicle-original','vin':'TEST-VIN'}]};
    final projected=await identity.detail('shop','dakota',saved);
    expect((projected!['customer'] as Map)['id'],'dakota');
    expect((projected['vehicles'] as List).single['id'],'audi');
    expect(await identity.detail('other-shop','dakota',saved),isNull);
    expect(await identity.detail('shop','tyra',saved),isNull);
    expect((saved['customer'] as Map)['id'],'local-customer-original');
  });

  test('missing alias table entries use exact document customer and original vehicle creation proof', () async {
    await _seed(db,aliases:false);
    final before = {for(final table in ['local_documents','local_jobs','sync_outbox',
      'local_invoice_closures','local_invoice_closed_receipts','local_finalized_invoice_income']) table:await rows(table)};
    final raw = (await LocalDocumentSqlStore.read(db,duplicateSnapshotKey))!;
    final projected = await LocalDocumentPartyIdentity(db).project('shop',
      Map<String,dynamic>.from(jsonDecode(raw) as Map));
    expect(projected['customer_id'],'dakota');
    expect(projected['vehicle_id'],'audi');
    expect(projected['_vehicle_identity_source'],'original_creation');
    final summaries=await CustomerDocumentSummaryService(database:db).forCustomer('shop','dakota',includeClosed:true);
    expect(VehicleInvoiceRepairSearch.forVehicle(summaries,vehicleId:'audi'),hasLength(1));
    expect(DocumentPresentation(summaries.single).finalizedCents,55424);
    expect(await LocalDocumentSqlStore.read(db,duplicateSnapshotKey),raw);
    for(final table in before.keys){expect(await rows(table),before[table],reason:table);}
    final other=await LocalDocumentPartyIdentity(db).project('other-shop',
      Map<String,dynamic>.from(jsonDecode(raw) as Map));
    expect(other['customer_id'],'local-customer-original');
    expect(other['vehicle_id'],'local-vehicle-original');
  });

  test('missing or conflicting creation evidence cannot reassign an unresolved vehicle', () async {
    await _seed(db,aliases:false,creationVehicle:'porsche');
    final saved=Map<String,dynamic>.from(jsonDecode((await LocalDocumentSqlStore.read(db,duplicateSnapshotKey))!) as Map);
    final result=await LocalDocumentPartyIdentity(db).project('shop',saved);
    expect(result['customer_id'],'dakota');
    expect(result['vehicle_id'],'local-vehicle-original');
    expect(result['_vehicle_identity_unresolved'],true);
    final actual=await LocalDocumentPartyIdentity(db).project('shop',{...saved,'vehicle_id':'porsche'});
    expect(actual['vehicle_id'],'porsche');
    final conflicted=await LocalDocumentPartyIdentity(db).project('shop',{...saved,'customer_id':'tyra'});
    expect(conflicted['customer_id'],'tyra');
    expect(conflicted['vehicle_id'],'local-vehicle-original');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i=0;i<12;i++) {
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:25)));
      await tester.pump(const Duration(milliseconds:100));
    }
  }

  testWidgets('missing offline customer reaches a visible retry state instead of spinning forever', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:CustomerDetailScreen(
      businessId:'shop',customerId:'missing',roleCode:'owner')));
    await settle(tester);
    expect(find.text('Customer details are not saved on this device.'),findsOneWidget);
    expect(find.text('Try again'),findsOneWidget);
    expect(find.byType(CircularProgressIndicator),findsNothing);
    expect(find.byType(FloatingActionButton),findsNothing);
    await tester.tap(find.text('Try again')); await settle(tester);
    expect(find.byType(CircularProgressIndicator),findsNothing);
    expect(await rows('sync_outbox'),isEmpty);
    await tester.pumpWidget(const SizedBox.shrink()); await settle(tester);
  });

  testWidgets('legacy customer link opens Dakota and Audi history shows 6382 without pending-finalization label', (tester) async {
    tester.view.physicalSize=const Size(412,915);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.reset);
    await tester.runAsync(()=>_seed(db));
    await tester.pumpWidget(const MaterialApp(home:CustomerDetailScreen(
      businessId:'shop',customerId:'local-customer-original',roleCode:'owner')));
    await settle(tester);
    expect(find.text('Dakota Spinder'),findsWidgets);
    expect(find.text('Received · pending finalization'),findsNothing);
    expect(find.text('Tyra Legard'),findsNothing);
    await tester.tap(find.text('Vehicles').first); await settle(tester);
    await tester.tap(find.text('2015 Audi A5').first); await settle(tester);
    await tester.ensureVisible(find.text('Repair History')); await tester.pump();
    await tester.tap(find.text('Repair History')); await settle(tester);
    expect(find.text('Vehicle Repair History'),findsOneWidget);
    expect(find.text('No invoices for this vehicle.'),findsNothing);
    expect(find.textContaining('6382'),findsWidgets);
    expect(find.text('Invoices (1)'),findsOneWidget);
    expect(find.text('0 visits'),findsNothing);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink()); await settle(tester);
  });
  testWidgets('invoice customer tap works without customer or vehicle alias entries', (tester) async {
    tester.view.physicalSize=const Size(412,915);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.reset);
    await tester.runAsync(()=>_seed(db,aliases:false));
    await tester.pumpWidget(const MaterialApp(home:JobDocumentScreen(
      businessId:'shop',documentId:duplicateInvoice,isOwner:true,roleCode:'owner')));
    await settle(tester);
    final customer=find.text('Dakota Spinder').first;
    await tester.ensureVisible(customer); await tester.pump();
    await tester.tap(customer); await settle(tester);
    expect(find.byType(CustomerDetailScreen),findsOneWidget);
    expect(find.text('Customer details are not saved on this device.'),findsNothing);
    expect(find.text('Dakota Spinder'),findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink()); await settle(tester);
  });

  testWidgets('unproven temporary vehicle keeps the saved invoice visible for review', (tester) async {
    tester.view.physicalSize=const Size(412,915);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.reset);
    await tester.runAsync(()=>_seed(db,aliases:false,creationVehicle:null));
    await tester.pumpWidget(const MaterialApp(home:CustomerDetailScreen(
      businessId:'shop',customerId:'dakota',roleCode:'owner')));
    await settle(tester);
    await tester.tap(find.text('Vehicles').first); await settle(tester);
    await tester.tap(find.text('2015 Audi A5').first); await settle(tester);
    await tester.ensureVisible(find.text('Repair History')); await tester.pump();
    await tester.tap(find.text('Repair History')); await settle(tester);
    expect(find.text('Vehicle link needs review'),findsOneWidget);
    expect(find.text('Unmatched customer invoices (1)'),findsOneWidget);
    expect(find.textContaining('6382'),findsWidgets);
    expect(find.text('No invoices for this vehicle.'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink()); await settle(tester);
  });

  testWidgets('current SQLite vehicle list wins over an old full customer snapshot without aliases', (tester) async {
    tester.view.physicalSize=const Size(412,915);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await _seed(db,aliases:false);
      final prefs=await SharedPreferences.getInstance();
      await prefs.setString('briskers_customer_detail_shop_dakota',jsonEncode({
        'customer':{'id':'dakota','name':'Dakota Spinder'},
        'vehicles':[{'id':'local-vehicle-original','year':2015,'make':'Audi','model':'A5'}],
      }));
    });
    await tester.pumpWidget(const MaterialApp(home:CustomerDetailScreen(
      businessId:'shop',customerId:'dakota',roleCode:'owner')));
    await settle(tester);
    await tester.tap(find.text('Vehicles').first); await settle(tester);
    await tester.tap(find.text('2015 Audi A5').first); await settle(tester);
    await tester.ensureVisible(find.text('Repair History')); await tester.pump();
    await tester.tap(find.text('Repair History')); await settle(tester);
    expect(find.text('Invoices (1)'),findsOneWidget);
    expect(find.textContaining('6382'),findsWidgets);
    expect(find.text('No invoices for this vehicle.'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink()); await settle(tester);
  });

}
