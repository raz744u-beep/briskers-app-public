import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/core/document_presentation.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/customer_document_summary_service.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/local_job_retirement.dart';
import 'package:briskers_app/services/offline_document_edit_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late BriskersLocalDatabase db;
  const source = <String, dynamic>{'id': 'estimate-2007', 'kind': 'estimate',
    'business_id': 'shop', 'status': 'draft', 'converted': false,
    'document_number': 'E-2007', 'total_amount': 1879.03, 'lines': <dynamic>[]};
  const target = <String, dynamic>{'id': 'invoice-6377', 'kind': 'invoice',
    'business_id': 'shop', 'status': 'closed', 'document_number': '6377',
    'converted_from_estimate_id': 'estimate-2007', 'total_amount': 1879.03,
    'paid_amount': 1879.03, 'payments': [{'id': 'saved-payment', 'amount': 1879.03}]};
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('conversion-projection');
    db = BriskersLocalDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
    await LocalDocumentDetailCache.initialize(db);
    await db.customStatement("INSERT INTO local_documents(id,business_id,customer_id,kind,document_number,status,total) VALUES('estimate-2007','shop','jennifer','estimate','E-2007','draft',1879.03)");
    await db.customStatement("INSERT INTO local_documents(id,business_id,customer_id,kind,document_number,status,document_date,total) VALUES('invoice-6377','shop','jennifer','invoice','6377','closed','2026-11-16',1879.03)");
    await LocalDocumentSqlStore.write(db, LocalDocumentDetailCache.key('shop','estimate-2007'), jsonEncode(source));
    await LocalDocumentSqlStore.write(db, LocalDocumentDetailCache.key('shop','invoice-6377'), jsonEncode(target));
  });
  tearDown(() async {
    await db.close(); await dir.delete(recursive: true);
    LocalDocumentDetailCache.sqliteWritesEnabled = false;
  });

  test('exact reverse link agrees across detail, list, customer history, edit guard and restart', () async {
    final invoiceBefore = await LocalDocumentSqlStore.read(db, LocalDocumentDetailCache.key('shop','invoice-6377'));
    for (var pass = 0; pass < 2; pass++) {
      final cache = LocalDocumentDetailCache(database: db);
      final detail = (await cache.load('shop','estimate-2007'))!;
      expect(DocumentPresentation(detail).statusLabel, 'Converted');
      expect(detail['converted_invoice_id'], 'invoice-6377');
      expect(detail['converted_invoice_number'], '6377');
      final rows = await LocalDocumentRepository(database: db).listByKind('shop',kind:'estimate');
      expect(rows.single['converted'], true);
      expect(rows.single['display_status'], 'Converted');
      final history = await CustomerDocumentSummaryService(database: db).forCustomer('shop','jennifer',includeClosed:true);
      expect(DocumentPresentation(history.firstWhere((r)=>r['kind']=='estimate')).statusLabel, 'Converted');
      await expectLater(OfflineDocumentEditService(database:db).addLine('shop','estimate-2007',
        name:'Should not be added',quantity:1,unitPrice:1,taxRate:0,lineKind:'part'),throwsStateError);
      await cache.save('shop','estimate-2007', {...source, 'row_version': 100});
      expect((await cache.load('shop','estimate-2007'))!['converted'], true);
      expect(await LocalDocumentSqlStore.read(db,LocalDocumentDetailCache.key('shop','invoice-6377')),invoiceBefore);
      if (pass == 0) {
        await db.close(); db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
      }
    }
  });

  test('matching customer, total and date never invent a conversion', () async {
    await LocalDocumentSqlStore.write(db,LocalDocumentDetailCache.key('shop','invoice-6377'),
      jsonEncode({...target,'converted_from_estimate_id':'different-estimate'}));
    final cache = LocalDocumentDetailCache(database:db);
    expect((await cache.load('shop','estimate-2007'))!['converted'], false);
    expect((await LocalDocumentRepository(database:db).listByKind('shop',kind:'estimate')).single['converted'],false);
  });

  test('explicit saved conversion survives a newer stale snapshot without an invoice backlink', () async {
    await LocalDocumentSqlStore.write(db,LocalDocumentDetailCache.key('shop','invoice-6377'),
      jsonEncode({...target,'converted_from_estimate_id':null}));
    final cache = LocalDocumentDetailCache(database:db);
    await cache.save('shop','estimate-2007', {...source,'converted':true,'converted_invoice_id':'invoice-6377'});
    await cache.save('shop','estimate-2007', source);
    expect((await cache.load('shop','estimate-2007'))!['converted_invoice_id'],'invoice-6377');
    expect((await cache.load('shop','estimate-2007'))!['converted'],true);
  });

  test('retired conversion remains editable and cannot be resurrected by presentation repair', () async {
    await LocalJobRetirement.ensureSchema(db);
    await db.customStatement("INSERT INTO local_job_retirement_entities VALUES('shop','retired-job','invoice','invoice-6377','retirement','accepted')");
    final cache=LocalDocumentDetailCache(database:db);
    final detail=(await cache.load('shop','estimate-2007'))!;
    expect(detail['converted'],false);
    expect(detail['converted_invoice_id'],isNull);
    expect((await LocalDocumentRepository(database:db).listByKind('shop',kind:'estimate')).single['converted'],false);
  });

  test('corrupt or cross-business invoice cache supplies no conversion evidence', () async {
    for (final raw in ['{invalid', jsonEncode({...target,'business_id':'another-shop'})]) {
      await LocalDocumentSqlStore.write(db,LocalDocumentDetailCache.key('shop','invoice-6377'),raw);
      expect((await LocalDocumentDetailCache(database:db).load('shop','estimate-2007'))!['converted'],false);
      expect((await LocalDocumentRepository(database:db).listByKind('shop',kind:'estimate')).single['converted'],false);
    }
  });

  test('legacy local cache redirect restores conversion on the visible server estimate', () async {
    await LocalDocumentSqlStore.write(db,LocalDocumentDetailCache.key('shop','invoice-6377'),
      jsonEncode({...target,'converted_from_estimate_id':null}));
    await LocalDocumentSqlStore.write(db,LocalDocumentDetailCache.key('shop','local-estimate-original'),
      jsonEncode({...source,'_server_document_id':'estimate-2007','converted':true,
        'converted_invoice_id':'invoice-6377'}));
    final cache=LocalDocumentDetailCache(database:db);
    expect((await cache.load('shop','estimate-2007'))!['converted'],true);
    expect((await cache.load('shop','estimate-2007'))!['converted_invoice_number'],'6377');
    expect((await LocalDocumentRepository(database:db).listByKind('shop',kind:'estimate')).single['converted'],true);
    await cache.save('shop','estimate-2007',source);
    expect((await cache.load('shop','estimate-2007'))!['converted_invoice_id'],'invoice-6377');
  });
  test('server source_estimate_id also proves conversion across detail and list', () async {
    await LocalDocumentSqlStore.write(db,LocalDocumentDetailCache.key('shop','invoice-6377'),
      jsonEncode({...target,'converted_from_estimate_id':null,'source_estimate_id':'estimate-2007'}));
    final detail=(await LocalDocumentDetailCache(database:db).load('shop','estimate-2007'))!;
    expect(detail['converted'],true);
    expect(detail['converted_invoice_id'],'invoice-6377');
    final list=await LocalDocumentRepository(database:db).listByKind('shop',kind:'estimate');
    expect(list.single['display_status'],'Converted');
  });

  test('startup imports legacy conversion proof before either invoice is opened', () async {
    final invoiceKey=LocalDocumentDetailCache.key('shop','invoice-6377');
    await db.customStatement('DELETE FROM local_document_details WHERE cache_key=?',[invoiceKey]);
    final prefs=await SharedPreferences.getInstance();
    final legacy=jsonEncode({...target,'converted_from_estimate_id':null,'source_estimate_id':'estimate-2007'});
    await prefs.setString(invoiceKey,legacy);
    await LocalDocumentDetailCache.initialize(db);
    final cache=LocalDocumentDetailCache(database:db);
    expect((await cache.load('shop','estimate-2007'))!['converted_invoice_id'],'invoice-6377');
    expect((await LocalDocumentRepository(database:db).listByKind('shop',kind:'estimate')).single['converted'],true);
    expect(prefs.getString(invoiceKey),legacy,reason:'Original recovery evidence stays intact');
    expect(await LocalDocumentSqlStore.read(db,invoiceKey),legacy);
    await cache.save('shop','estimate-2007',source);
    expect((await cache.load('shop','estimate-2007'))!['converted'],true);
  });

  test('legacy startup import never overwrites current SQL or revives deleted evidence', () async {
    final invoiceKey=LocalDocumentDetailCache.key('shop','invoice-6377');
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString(invoiceKey,jsonEncode({...target,'source_estimate_id':'unrelated'}));
    final before=await LocalDocumentSqlStore.read(db,invoiceKey);
    await LocalDocumentDetailCache.initialize(db);
    expect(await LocalDocumentSqlStore.read(db,invoiceKey),before);
    await db.customStatement('INSERT INTO local_document_detail_deleted(cache_key) VALUES(?)',[invoiceKey]);
    await db.customStatement('DELETE FROM local_document_details WHERE cache_key=?',[invoiceKey]);
    await LocalDocumentDetailCache.initialize(db);
    expect(await LocalDocumentSqlStore.read(db,invoiceKey),isNull);
    expect((await LocalDocumentDetailCache(database:db).load('shop','estimate-2007'))!['converted'],false);
  });

}
