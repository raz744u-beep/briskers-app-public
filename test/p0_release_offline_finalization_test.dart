import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/services/local_job_retirement.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:briskers_app/widgets/job_compact_card.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_invoice_finalization.dart';

class RecordingApi extends BriskersApi {
  int calls=0;
  bool fail=false;
  final operations=<String>[];
  @override
  Future<Map<String,dynamic>> finalizeInvoiceOnce(String businessId,String invoiceId,String operationId,Map<String,dynamic> request) async {
    calls++;
    operations.add(operationId);
    if(fail) throw StateError('Synthetic conflict');
    return {'operation_id':operationId,'invoice_id':invoiceId,'finalized':true};
  }
}
Map<String,dynamic> invoice(String id,{int total=100}) => {
  'id':id,'kind':'invoice','job_id':'job','total_amount':total,
  'paid_amount':0,'pending_payment':100,'status':'issued',
  'payments':[{'id':'receipt','state':'pending','amount':100,
    'payment_method_id':'method','payment_date':'2026-11-10'}],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);
  });
  test('offline intent survives restart and repeated confirm, bulk eligibility is atomic',() async {
    final dir=await Directory.systemTemp.createTemp('finalization-');
    final file=File('${dir.path}/shop.sqlite');
    var db=BriskersLocalDatabase(NativeDatabase(file));
    await LocalDocumentDetailCache.initialize(db);
    final cache=LocalDocumentDetailCache(database:db);
    await cache.save('shop','one',invoice('one'));
    await cache.save('shop','partial',invoice('partial',total:200));
    final service=OfflineInvoiceFinalization(database:db);
    await expectLater(service.save('shop',['one','partial'],isOwner:true,close:true),throwsStateError);
    expect(await service.state('shop','one'),isNull);
    await service.save('shop',['one'],isOwner:true,close:true);
    await service.save('shop',['one'],isOwner:true,close:true);
    final before=await db.customSelect('SELECT operation_id,payload FROM invoice_finalization_intents_v1').getSingle();
    await db.close();
    db=BriskersLocalDatabase(NativeDatabase(file));
    final after=await db.customSelect('SELECT operation_id,payload FROM invoice_finalization_intents_v1').getSingle();
    expect(after.data,before.data);
    expect(await OfflineInvoiceFinalization(database:db).state('shop','one'),'pending');
    await expectLater(OfflineInvoiceFinalization(database:db).save('shop',['one'],isOwner:false,close:true),throwsStateError);
    await db.close(); await dir.delete(recursive:true);
  });
  test('receipt mismatch and missing receipt identity fail closed',() {
    expect(()=>OfflineInvoiceFinalization.snapshot({...invoice('x'),'pending_payment':99},true),throwsStateError);
    expect(()=>OfflineInvoiceFinalization.snapshot({...invoice('x'),'payments':[]},true),throwsStateError);
    expect(()=>OfflineInvoiceFinalization.snapshot({...invoice('x'),'_payment_reconciliation_required':true},true),throwsStateError);
  });
  testWidgets('phone card shows exact linked invoice and saved labor summary', (tester) async {
    tester.view.physicalSize=const Size(390,850);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened=false;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:JobCompactCard(
      job:const {'job_number':'J-48','title':'Invoice','invoice_number':'6367',
        'work_summary':'Diagnose cooling leak','customer_name':'Example','vehicle':'BMW X3'},
      statusControl:const Text('In progress'),onOpen:(){},onOpenInvoice:(){opened=true;},
    ))));
    expect(find.text('Invoice 6367'),findsOneWidget);
    expect(find.text('Diagnose cooling leak'),findsOneWidget);
    await tester.tap(find.text('Invoice 6367'));
    expect(opened,isTrue);
    expect(tester.takeException(),isNull);
  });

  test('a retired invoice never replays its earlier finalization intent',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory()); addTearDown(db.close);
    await LocalDocumentDetailCache.initialize(db);
    await LocalDocumentDetailCache(database:db).save('shop','invoice',invoice('invoice'));
    final api=RecordingApi();
    final service=OfflineInvoiceFinalization(database:db,api:api);
    await service.save('shop',['invoice'],isOwner:true,close:true);
    await LocalJobRetirement.ensureSchema(db);
    await db.customStatement("INSERT INTO local_job_retirement_entities VALUES('shop','job','invoice','invoice','retire','pending')");
    await service.flush('shop');
    expect(api.calls,0);
    expect(await service.state('shop','invoice'),'pending');
  });

  test('offline replay makes no request; conflicts hold and explicit retry keeps identity',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory()); addTearDown(db.close);
    await LocalDocumentDetailCache.initialize(db);
    await LocalDocumentDetailCache(database:db).save('shop','invoice',invoice('invoice'));
    final api=RecordingApi()..fail=true;
    final service=OfflineInvoiceFinalization(database:db,api:api);
    await service.save('shop',['invoice'],isOwner:true,close:false);
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
    await service.flush('shop');
    expect(api.calls,0);
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);
    await service.flush('shop');
    expect(await service.state('shop','invoice'),'review');
    await service.flush('shop');
    expect(api.calls,1);
    api.fail=false;
    await service.retry('shop','invoice',isOwner:true);
    expect(api.operations.toSet(),hasLength(1));
    expect(await service.state('shop','invoice'),'confirmed');
    await service.flush('shop');
    expect(api.calls,2);
  });

  test('partial receipts can finalize but cannot close; changed saved receipts cannot replace intent',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory()); addTearDown(db.close);
    await LocalDocumentDetailCache.initialize(db);
    final cache=LocalDocumentDetailCache(database:db);
    await cache.save('shop','invoice',invoice('invoice',total:200));
    final service=OfflineInvoiceFinalization(database:db);
    await service.save('shop',['invoice'],isOwner:true,close:false);
    final before=(await db.customSelect('SELECT operation_id,payload FROM invoice_finalization_intents_v1').getSingle()).data;
    await cache.save('shop','invoice',invoice('invoice',total:250));
    await expectLater(service.save('shop',['invoice'],isOwner:true,close:false),throwsStateError);
    expect((await db.customSelect('SELECT operation_id,payload FROM invoice_finalization_intents_v1').getSingle()).data,before);
    await expectLater(service.save('shop',['invoice'],isOwner:true,close:true),throwsStateError);
  });

}
