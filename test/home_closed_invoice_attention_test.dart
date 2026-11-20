import 'dart:convert';
import 'dart:io';
import 'package:briskers_app/core/invoice_attention_projection.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_invoice_closure.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late BriskersLocalDatabase db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('home-closed-invoices');
    db = BriskersLocalDatabase(NativeDatabase(File('${dir.path}/shop.sqlite')));
    await LocalInvoiceClosureStore(db).prepare();
    for (final number in ['6355','6356','6357','6358','6390']) {
      await db.customStatement("INSERT INTO local_documents(id,business_id,kind,document_number,status,display_status_code,total) VALUES(?,'shop','invoice',?,'issued','pending_close',100)", ['invoice-$number',number]);
      if (number != '6390') {
        await db.customStatement("INSERT INTO local_invoice_closures(business_id,invoice_id,closed_at,operation_id,payload) VALUES('shop',?,'2026-11-19T15:00:00Z',?,'{\"close\":true}')",['invoice-$number','close-$number']);
      }
    }
  });
  tearDown(() async { await db.close(); await dir.delete(recursive:true); });

  test('four stale pending flags cannot override saved closures after restart or consume the limit', () async {
    for (var pass=0;pass<2;pass++) {
      final before = (await db.customSelect('SELECT * FROM local_documents ORDER BY id').get()).map((r)=>r.data).toList();
      final repo = LocalDocumentRepository(database:db);
      final attention = await repo.pendingCloseAttention('shop',limit:1);
      expect(attention['count'],1);
      expect((attention['items'] as List).single['document_number'],'6390');
      expect(await repo.openInvoiceCount('shop'),0,reason:'Paid/ready-to-close is distinct from unpaid Open.');
      final after = (await db.customSelect('SELECT * FROM local_documents ORDER BY id').get()).map((r)=>r.data).toList();
      expect(after,before,reason:'A Home read must not rewrite invoice status, amounts or sync state.');
      if(pass==0) {
        await db.close(); db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/shop.sqlite')));
      }
    }
  });

  test('stale Auto response is filtered and unknown remainder and other attention counts survive', () async {
    final source = {'counts':{'pending_close_invoices':10,'unassigned_jobs':7},
      'pending_close_invoices':[for(final n in ['6355','6356','6357','6358','6390']) {'id':'invoice-$n'}],
      'unassigned_jobs':[{'id':'unassigned-job'}]};
    final encoded = jsonEncode(source);
    final projected = await LocalDocumentRepository(database:db).projectPendingCloseAttention('shop',source);
    expect((projected['counts'] as Map)['pending_close_invoices'],6);
    expect((projected['counts'] as Map)['unassigned_jobs'],7);
    expect((projected['pending_close_invoices'] as List).single['id'],'invoice-6390');
    expect(jsonEncode(source),encoded);
  });

  test('closed index status wins even if old pending-close code remains', () async {
    await db.customStatement("UPDATE local_documents SET status='closed' WHERE id='invoice-6390'");
    expect((await LocalDocumentRepository(database:db).pendingCloseAttention('shop'))['count'],0);
  });

  test('explicit Owner reopening is respected and another business closure cannot hide an invoice', () async {
    await db.customStatement("UPDATE local_invoice_closures SET reopened_at='2026-11-19T16:00:00Z',sync_state='reopen_pending' WHERE invoice_id='invoice-6357'");
    await db.customStatement("INSERT INTO local_invoice_closures(business_id,invoice_id,closed_at,operation_id,payload) VALUES('elsewhere','invoice-6390','2026-11-19T15:00:00Z','foreign-close','{}')");
    final attention=await LocalDocumentRepository(database:db).pendingCloseAttention('shop');
    expect(attention['count'],2);
    expect((attention['items'] as List).map((r)=>r['id']).toSet(),{'invoice-6357','invoice-6390'});
  });

  test('exact saved Closed detail excludes a stale pending index without modifying it', () async {
    final key=LocalDocumentDetailCache.key('shop','invoice-6390');
    await LocalDocumentSqlStore.ensure(db);
    await LocalDocumentSqlStore.write(db,key,jsonEncode({'id':'invoice-6390','kind':'invoice',
      'business_id':'shop','status':'closed','row_version':10,'paid_amount':100,'total_amount':100}));
    final repo=LocalDocumentRepository(database:db);
    expect((await repo.pendingCloseAttention('shop'))['count'],0);
    await db.customStatement("UPDATE local_documents SET display_status_code='open' WHERE id='invoice-6390'");
    expect(await repo.openInvoiceCount('shop'),0,reason:'The invoice tile must respect the same saved Closed detail.');
    await db.customStatement("UPDATE local_documents SET display_status_code='pending_close' WHERE id='invoice-6390'");
    expect(await LocalDocumentSqlStore.read(db,key),contains('"paid_amount":100'));
    expect((await db.customSelect("SELECT display_status_code FROM local_documents WHERE id='invoice-6390'").getSingle()).read<String>('display_status_code'),'pending_close');
  });

  test('only explicit reopening can supersede a saved Closed detail; foreign cache is rejected', () async {
    final key=LocalDocumentDetailCache.key('shop','invoice-6390');
    await LocalDocumentSqlStore.ensure(db);
    await db.customStatement("UPDATE local_documents SET row_version=11 WHERE id='invoice-6390'");
    await LocalDocumentSqlStore.write(db,key,jsonEncode({'id':'invoice-6390','kind':'invoice',
      'business_id':'shop','status':'closed','row_version':10}));
    final repo=LocalDocumentRepository(database:db);
    expect((await repo.pendingCloseAttention('shop'))['count'],0,
      reason:'An unrelated newer index version cannot reopen a saved Closed invoice.');
    await db.customStatement("UPDATE local_documents SET display_status_code='reopened' WHERE id='invoice-6390'");
    expect(await repo.openInvoiceCount('shop'),1,reason:'A current explicit reopening remains visible.');
    await db.customStatement("UPDATE local_documents SET display_status_code='pending_close' WHERE id='invoice-6390'");
    await LocalDocumentSqlStore.write(db,key,jsonEncode({'id':'invoice-6390','kind':'invoice',
      'business_id':'elsewhere','status':'closed','row_version':12}));
    expect((await repo.pendingCloseAttention('shop'))['count'],1);
  });

  test('verified close event projection is idempotent and count never goes negative', () {
    final source=<String,dynamic>{'counts':{'pending_close_invoices':1,'unread_messages':3},
      'pending_close_invoices':[{'id':'closed'},{'id':'closed'}]};
    final once=withoutClosedAttentionInvoices(source,{'closed'});
    expect((once['counts'] as Map)['pending_close_invoices'],0);
    expect((once['counts'] as Map)['unread_messages'],3);
    expect(withoutClosedAttentionInvoices(once,{'closed'}),once);
  });
}
