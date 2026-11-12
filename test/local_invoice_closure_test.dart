import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:briskers_app/widgets/job_financial_status_card.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:briskers_app/services/invoice_payment_feed.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/core/document_presentation.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_invoice_closure.dart';
import 'package:briskers_app/services/offline_invoice_finalization.dart';
import 'package:briskers_app/screens/documents_screen.dart';

class CloseApi extends BriskersApi {
  int closes=0, payments=0;
  bool fail=false;
  @override Future<void> closeInvoice(String b,String i) async { throw StateError('Legacy close may post receipts'); }
  @override Future<Map<String,dynamic>> finalizeInvoiceOnce(String b,String i,String o,Map<String,dynamic> p) async { if((p['receipts'] as List).isNotEmpty) { payments++; throw StateError('Close must not post receipts'); } closes++; if(fail) throw StateError('unposted receipt'); return {'operation_id':o,'invoice_id':i,'closed':true}; }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late BriskersLocalDatabase db;
  late CloseApi api;
  Map<String,dynamic> detail(String id,double total,{bool pending=true}) => {
    'id':id,'kind':'invoice','job_id':'job-$id','status':'issued','total_amount':total,
    'paid_amount':pending?0:total,'pending_payment':pending?total:0,
    'lines':[{'id':'line-$id','line_kind':'labor','description':'Replace thermostat and coolant pipe','quantity':1}],
    'payments':[{'id':'receipt-$id','state':pending?'pending':'posted','amount':total,
      'payment_method_id':'cash','payment_date':'2026-11-10'}],
  };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir=await Directory.systemTemp.createTemp('close-invoices');
    db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
    await LocalDocumentDetailCache.initialize(db);
    api=CloseApi();
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
    for(final e in {'6368':521.31,'6357':400.0,'6359':7882.11}.entries) {
      await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,customer_name) VALUES(?,'shop','owner','Invoice','open',?,?)",['job-${e.key}',e.key=='6368'?'J-49':e.key=='6357'?'J-38':'J-40',e.key=='6368'?'Rick Francis':e.key=='6357'?'Reginald Willis':'Gloria Johnson']);
      await db.customStatement("INSERT INTO local_documents(id,business_id,kind,status,total,sync_state,job_id,document_number) VALUES(?,'shop','invoice','issued',?,'synced',?,?)",[e.key,e.value,'job-${e.key}',e.key]);
      await LocalDocumentDetailCache(database:db).save('shop',e.key,detail(e.key,e.value,pending:e.key!='6359'));
    }
  });
  tearDown(() async {await db.close(); await dir.delete(recursive:true); LocalDocumentDetailCache.sqliteWritesEnabled=false;});
  Future<String> paymentHistory() async => jsonEncode([
    for(final id in ['6368','6357','6359']) (await LocalDocumentDetailCache(database:db).loadReadOnly('shop',id))!['payments'],
    (await db.customSelect('SELECT * FROM sync_outbox ORDER BY id').get()).map((r)=>r.data).toList(),
  ]);
  test('Force Offline close persists, removes Paid eligibility and survives stale sync without touching payments',() async {
    final before=await paymentHistory();
    final service=LocalInvoiceClosure(database:db,api:api);
    await service.close('shop',['6368'],isOwner:true);
    await service.flush('shop'); expect(api.closes,0); expect(api.payments,0);
    var rows=await LocalDocumentRepository(database:db).listByKind('shop',kind:'invoice');
    expect(documentListStage(rows.singleWhere((r)=>r['id']=='6368'),estimate:false),'Closed');
    await db.close(); db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
    final repo=LocalDocumentRepository(database:db);
    await repo.upsertFromServer('shop',[detail('6368',521.31)]);
    await LocalDocumentDetailCache(database:db).save('shop','6368',detail('6368',521.31));
    expect(DocumentPresentation((await LocalDocumentDetailCache(database:db).load('shop','6368'))!).statusCode,'closed');
    rows=await repo.listByKind('shop',kind:'invoice');
    expect(documentListStage(rows.singleWhere((r)=>r['id']=='6368'),estimate:false),'Closed');
    expect(await paymentHistory(),before);
  });
  test('bulk and repeated close are atomic and idempotent; later sync never invokes finalization',() async {
    final before=await paymentHistory();
    final service=LocalInvoiceClosure(database:db,api:api);
    await service.close('shop',['6368','6357','6359','6368'],isOwner:true);
    await service.close('shop',['6368','6357'],isOwner:true);
    expect(await db.customSelect('SELECT * FROM local_invoice_closures').get(),hasLength(3));
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);
    api.fail=true; await service.flush('shop');
    expect(DocumentPresentation((await LocalDocumentDetailCache(database:db).loadReadOnly('shop','6368'))!).isClosed,isTrue);
    api.fail=false; await service.flush('shop'); expect(api.closes,3);
    await db.customStatement('UPDATE local_invoice_closures SET retry_after=0');
    await service.flush('shop'); await service.flush('shop');
    expect(api.closes,6); expect(api.payments,0); expect(await paymentHistory(),before);
  });
  test('partial or unverified selection rolls back every closure',() async {
    await LocalDocumentDetailCache(database:db).save('shop','6357',{...detail('6357',400),'total_amount':500});
    final service=LocalInvoiceClosure(database:db,api:api);
    await expectLater(service.close('shop',['6368','6357'],isOwner:true),throwsStateError);
    expect(await db.customSelect('SELECT * FROM local_invoice_closures').get(),isEmpty);
    await expectLater(service.close('shop',['6368'],isOwner:false),throwsStateError);
  });
  test('Rick and Reginald pending finalizations retain the same operation and do not block local closure',() async {
    final before=await paymentHistory();
    final finalization=OfflineInvoiceFinalization(database:db);
    for(final id in ['6368','6357']) {
      final saved=(await LocalDocumentDetailCache(database:db).loadReadOnly('shop',id))!;
      expect(DocumentPresentation(saved).balanceDueCents,0);
      await finalization.save('shop',[id],isOwner:true,close:false);
      await finalization.save('shop',[id],isOwner:true,close:false);
      expect(await finalization.stateForDetail('shop',id,saved),'pending');
    }
    final intents=(await db.customSelect('SELECT * FROM invoice_finalization_intents_v1').get()).map((r)=>r.data).toList();
    expect(intents,hasLength(2));
    await LocalInvoiceClosure(database:db,api:api).close('shop',['6368','6357'],isOwner:true);
    expect((await db.customSelect('SELECT * FROM invoice_finalization_intents_v1').get()).map((r)=>r.data).toList(),intents);
    expect(await paymentHistory(),before);
  });
  test('explicit Owner reopen supersedes closure; stale refresh alone cannot reopen',() async {
    final service=LocalInvoiceClosure(database:db,api:api);
    await service.close('shop',['6359'],isOwner:true);
    final original=(await db.customSelect('SELECT operation_id FROM local_invoice_closures').getSingle()).data;
    await LocalInvoiceClosureStore(db).serverReopened('shop','6359');
    expect(DocumentPresentation((await LocalDocumentDetailCache(database:db).loadReadOnly('shop','6359'))!).isClosed,isFalse);
    await service.close('shop',['6359'],isOwner:true);
    expect((await db.customSelect('SELECT operation_id FROM local_invoice_closures').getSingle()).data,isNot(original));
    expect(DocumentPresentation((await LocalDocumentDetailCache(database:db).loadReadOnly('shop','6359'))!).isClosed,isTrue);
  });
  test('recorded customer payment and explicit operational completion stay independent',() async {
    final cached=(await LocalDocumentDetailCache(database:db).loadReadOnly('shop','6368'))!;
    final state=cachedVerifiedJobPaymentState([cached]);
    expect(state,'recorded_pending'); expect(savedJobFinancialStatus(state),'Paid');
    await LocalJobRepository(database:db).saveVerifiedPaymentState('shop','job-6368',state!);
    var job=(await db.customSelect("SELECT status,payment_state FROM local_jobs WHERE id='job-6368'").getSingle()).data;
    expect(job,{'status':'open','payment_state':'recorded_pending'});
    final payments=cached['payments'];
    await OfflineJobAdminService(database:db).queueStatus('shop','job-6368',code:'completed',name:'Completed');
    job=(await db.customSelect("SELECT status,payment_state FROM local_jobs WHERE id='job-6368'").getSingle()).data;
    expect(job,{'status':'completed','payment_state':'recorded_pending'});
    final after=(await LocalDocumentDetailCache(database:db).loadReadOnly('shop','6368'))!;
    expect(after['payments'],payments); expect(DocumentPresentation(after).isClosed,isFalse);
  });
  testWidgets('real offline screen closes Rick immediately, updates count and shows saved labor description',(tester) async {
    tester.view.physicalSize=const Size(390,844); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final icons=File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if(await icons.exists()) await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await icons.readAsBytes())))).load();
      final font=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      if(await font.exists()) await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())))).load();
    });
    final key=GlobalKey();
    final before=await tester.runAsync(paymentHistory);
    await tester.pumpWidget(MaterialApp(theme:ThemeData(fontFamily:'Roboto'),home:RepaintBoundary(key:key,child:DocumentsScreen(
      businessId:'shop',kind:'invoice',roleCode:'owner',isOwner:true,showAppBar:false,
      localDocuments:LocalDocumentRepository(database:db),paymentFeed:InvoicePaymentFeed(database:db),api:api))));
    await tester.pumpAndSettle();
    expect(find.text('Paid'),findsNWidgets(3));
    expect(find.text('Replace thermostat and coolant pipe'),findsNWidgets(3));
    await tester.runAsync(() async {
      final image=await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio:2);
      final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
      final file=File('build/payroll-qa/bugs35-offline-paid-invoices.png');
      await file.parent.create(recursive:true); await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.tap(find.text('Close invoices').first); await tester.pumpAndSettle();
    await tester.tap(find.text('Select all (3)')); await tester.pumpAndSettle();
    await tester.tap(find.text('I-6368  Rick Francis')); await tester.pumpAndSettle();
    await tester.tap(find.text('Close selected')); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'Close invoices').last); await tester.pumpAndSettle();
    expect(find.text('Closed'),findsOneWidget); expect(find.text('Paid'),findsNWidgets(2));
    await tester.tap(find.text('Close invoices').first); await tester.pumpAndSettle();
    expect(find.text('Select all (2)'),findsOneWidget);
    expect(find.text('I-6368  Rick Francis'),findsNothing);
    expect(await tester.runAsync(paymentHistory),before);
    expect(api.closes,0); expect(api.payments,0);
    await tester.pumpWidget(const SizedBox.shrink());
  },timeout:const Timeout(Duration(seconds:30)));

}
