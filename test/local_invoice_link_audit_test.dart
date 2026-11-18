import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_invoice_link_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('invoice-only audit exposes both customers and saved link disagreement without writes', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement("INSERT INTO local_customers(id,business_id,display_name) "
      "VALUES('dakota','shop','Dakota Spinder'),('tyra','shop','Tyra Legard')");
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,status,customer_id) "
      "VALUES('dakota-job','shop','full','J-41','Original','completed','dakota'),"
      "('tyra-job','shop','full','J-41','Newer','open','tyra')");
    await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,customer_id,kind,document_number,total) "
      "VALUES('dakota-invoice','shop','dakota-job','dakota','invoice','6360',554.24),"
      "('tyra-invoice','shop','tyra-job','tyra','invoice','6360',4894.21)");
    final raw = jsonEncode({'id':'dakota-invoice','customer_id':'dakota',
      'job_id':'different-saved-job','paid_amount':554.24,'closed_at':'2026-11-02'});
    SharedPreferences.setMockInitialValues({'briskers_document_detail_shop_dakota-invoice':raw});
    final before = (await db.customSelect("SELECT name,sql FROM sqlite_master ORDER BY name").get()).map((r)=>r.data).toList();
    final audit = await LocalInvoiceLinkAudit(database:db).inspect(businessId:'shop',invoiceNumber:'6360');
    final refs = List<Map<String,dynamic>>.from(audit['references'] as List);
    expect(audit['has_duplicate_invoice_number'],true);
    expect(refs.map((r)=>r['customer_name']),containsAll(['Dakota Spinder','Tyra Legard']));
    final dakota = refs.firstWhere((r)=>r['document_id']=='dakota-invoice');
    expect(dakota['job_id'],'dakota-job');
    expect((dakota['saved'] as Map)['job_id'],'different-saved-job');
    expect((dakota['saved'] as Map)['paid_amount'],554.24);
    expect((await SharedPreferences.getInstance()).getString('briskers_document_detail_shop_dakota-invoice'),raw);
    expect((await db.customSelect("SELECT name,sql FROM sqlite_master ORDER BY name").get()).map((r)=>r.data).toList(),before);
    expect((await db.customSelect("SELECT job_id FROM local_documents WHERE id='dakota-invoice'").getSingle()).data['job_id'],'dakota-job');
  });
  test('invoice number 6346 linked to J-19 is not silently assigned to J-18',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,status,customer_name)"
      " VALUES ('j18','shop-a','all','J-18','Test','open','Test Customer'),"
      " ('j19','shop-a','all','J-19','Real repair','completed','Original Customer')",
    );
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,kind,document_number)"
      " VALUES('invoice-6346','shop-a','j19','invoice','6346')",
    );
    final audit = await LocalInvoiceLinkAudit(database: db).inspect(
      businessId: 'shop-a', jobNumber: 'J-18', invoiceNumber: '6346',
    );
    expect(audit['read_only'], true);
    expect(audit['ambiguous'], true);
    expect((audit['references'] as List).single['job_id'], 'j19');
    expect((audit['references'] as List).single['matches_target_job'], false);
    final rows = await db.customSelect(
      "SELECT job_id FROM local_documents WHERE id='invoice-6346'",
    ).get();
    expect(rows.single.read<String>('job_id'), 'j19');
    await db.close();
  });

  test('duplicate invoice numbers must be flagged without rewriting records',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,status)"
      " VALUES ('j18','shop-a','all','J-18','Test','open')",
    );
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,kind,document_number)"
      " VALUES('a','shop-a','j18','invoice','6346'),"
      " ('b','shop-a',NULL,'invoice','6346')",
    );
    final audit = await LocalInvoiceLinkAudit(database: db).inspect(
      businessId: 'shop-a', jobNumber: 'J-18', invoiceNumber: '6346',
    );
    expect(audit['has_duplicate_invoice_number'], true);
    expect(audit['ambiguous'], true);
    expect((audit['references'] as List).length, 2);
    await db.close();
  });

  test('business scoping prevents another shop from appearing in audit',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,kind,document_number)"
      " VALUES('other','shop-b','invoice','6346')",
    );
    final audit = await LocalInvoiceLinkAudit(database: db).inspect(
      businessId: 'shop-a', jobNumber: 'J-18', invoiceNumber: '6346',
    );
    expect(audit['references'], isEmpty);
    await db.close();
  });
}
