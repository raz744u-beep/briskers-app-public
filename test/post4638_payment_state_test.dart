import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/core/estimate_list_description.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/screens/jobs/job_document_screen.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_invoice_finalization.dart';

Map<String,dynamic> fixture(String id,List<num> amounts) => {
  'id':id,'kind':'invoice','document_number':id,'job_id':'job-$id',
  'document_date':'2026-11-12','status':'issued','row_version':1,
  'customer_name':'Fixture $id','vehicle':'2016 Mercedes E350',
  'total_amount':amounts.fold<num>(0,(a,b)=>a+b),'paid_amount':0,
  'pending_payment':amounts.fold<num>(0,(a,b)=>a+b),
  'payments':[for(var i=0;i<amounts.length;i++) {
    'id':'original-$id-$i','operation_id':'receipt-$id-$i','state':'pending',
    'amount':amounts[i],'payment_method_id':'card','payment_method_name':'Credit card',
    'payment_date':'2026-11-12','pending_sync':true,
  }],
  'lines':[{'id':'line-$id','line_kind':'labor','name':'Labor','description':'Replace front air struts','quantity':3.6,'unit_price':100,'total_amount':360}],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late BriskersLocalDatabase db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
    dir=await Directory.systemTemp.createTemp('post4638-');
    db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
    debugUseLocalDatabase(db);
    await LocalDocumentDetailCache.initialize(db);
  });
  tearDown(() async {
    debugUseLocalDatabase(null);
    await db.close(); await dir.delete(recursive:true);
    LocalDocumentDetailCache.sqliteWritesEnabled=false;
  });
  test('saved alias recognizes same finalization, survives restart, and preserves all original receipts',() async {
    final cache=LocalDocumentDetailCache(database:db);
    for(final e in {'6359':<num>[3000,4882.11],'6368':<num>[521.31],'6357':<num>[1637.62]}.entries) {
      final saved=fixture(e.key,e.value);
      await cache.save('shop',e.key,saved);
      final service=OfflineInvoiceFinalization(database:db);
      await service.save('shop',[e.key],isOwner:true,close:false);
      await service.save('shop',[e.key],isOwner:true,close:false);
      expect(await service.stateForDetail('shop','local-invoice-${e.key}',{...saved,'_server_document_id':e.key}),'pending');
      expect(await service.stateForDetail('other',e.key,saved),isNull);
      expect(jsonEncode((await cache.loadReadOnly('shop',e.key))!['payments']),jsonEncode(saved['payments']));
    }
    final before=(await db.customSelect('SELECT * FROM invoice_finalization_intents_v1 ORDER BY invoice_id').get()).map((r)=>r.data).toList();
    expect(before,hasLength(3));
    await db.close(); db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/db.sqlite'))); debugUseLocalDatabase(db);
    expect((await db.customSelect('SELECT * FROM invoice_finalization_intents_v1 ORDER BY invoice_id').get()).map((r)=>r.data).toList(),before);
    expect(await OfflineInvoiceFinalization(database:db).stateForDetail('shop','6359',fixture('6359',[3000,4882.11])),'pending');
  });
  test('confirmed receipts mixed with new receipts cannot create a duplicate request',() async {
    final service=OfflineInvoiceFinalization(database:db);
    final cache=LocalDocumentDetailCache(database:db);
    final original=fixture('6368',[521.31]);
    await cache.save('shop','6368',original);
    await service.save('shop',['6368'],isOwner:true,close:false);
    await db.customStatement("UPDATE invoice_finalization_intents_v1 SET state='confirmed'");
    final before=(await db.customSelect('SELECT * FROM invoice_finalization_intents_v1').getSingle()).data;
    final mixed=fixture('6368',[521.31,50]);
    await cache.save('shop','6368',mixed);
    expect(await service.stateForDetail('shop','6368',mixed),'review');
    await expectLater(service.save('shop',['6368'],isOwner:true,close:false),throwsStateError);
    expect((await db.customSelect('SELECT * FROM invoice_finalization_intents_v1').getSingle()).data,before);
    expect(jsonEncode((await cache.loadReadOnly('shop','6368'))!['payments']),jsonEncode(mixed['payments']));
  });
  test('description retains meaningful title and description equal to title',() {
    expect(estimateListDescription({'kind':'invoice','title':'Replace thermostat','description':'Replace thermostat'}),'Replace thermostat');
    expect(estimateListDescription({'title':'Invoice #6372'},detail:{'lines':[{'name':'Labor','description':'Replace thermostat'}]}),'Replace thermostat');
    expect(estimateListDescription({'title':'Invoice #6372'}),'');
  });
  testWidgets('actual offline payment screen shows Paid and disables saved finalization after reopen',(tester) async {
    tester.view.physicalSize=const Size(430,1100); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final saved=fixture('6359',[3000,4882.11]);
    await LocalDocumentDetailCache(database:db).save('shop','6359',saved);
    await OfflineInvoiceFinalization(database:db).save('shop',['6359'],isOwner:true,close:false);
    for(var open=0;open<2;open++) {
      await tester.pumpWidget(const MaterialApp(home:JobDocumentScreen(businessId:'shop',documentId:'6359',isOwner:true,roleCode:'owner',initialTab:'payment')));
      await tester.pumpAndSettle();
      expect(find.text('Paid'), findsWidgets);
      expect(find.textContaining('Pending Close'), findsNothing);
      expect(find.text('Finalize Received Payment'), findsNothing);
      await tester.scrollUntilVisible(find.text('Finalization saved · pending sync'),300,scrollable:find.byType(Scrollable).last);
      final button=tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Finalization saved · pending sync'));
      expect(button.onPressed,isNull);
      await tester.pumpWidget(const SizedBox.shrink()); await tester.pumpAndSettle();
    }
    expect((await db.customSelect('SELECT * FROM invoice_finalization_intents_v1').get()),hasLength(1));
    expect(jsonEncode((await LocalDocumentDetailCache(database:db).loadReadOnly('shop','6359'))!['payments']),jsonEncode(saved['payments']));
  });
}
