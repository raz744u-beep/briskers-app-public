import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_invoice_link_audit.dart';

void main() {
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
