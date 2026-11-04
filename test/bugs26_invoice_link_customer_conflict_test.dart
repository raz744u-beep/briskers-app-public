import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_invoice_link_audit.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('J18 investigation reports actual linked invoices and conflicting customers without repair', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,status,customer_id) VALUES('j18','shop-a','all','J-18','Synthetic','open','customer-a'),('j19','shop-a','all','J-19','Synthetic','open','customer-b')",
    );
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,customer_id,kind,document_number) VALUES('invoice-a','shop-a','j18','customer-other','invoice','6346'),('invoice-b','shop-a','j19','customer-b','invoice','6347')",
    );
    final before =
        (await db
                .customSelect('SELECT * FROM local_documents ORDER BY id')
                .get())
            .map((r) => r.data)
            .toList();
    final result = await LocalInvoiceLinkAudit(
      database: db,
    ).inspect(businessId: 'shop-a', jobNumber: 'J-18', invoiceNumber: '6346');
    expect(result['ambiguous'], true);
    expect(
      (result['references'] as List).single['customer_identity_conflict'],
      true,
    );
    expect(
      (result['target_job_invoices'] as List).single['document_id'],
      'invoice-a',
    );
    final after =
        (await db
                .customSelect('SELECT * FROM local_documents ORDER BY id')
                .get())
            .map((r) => r.data)
            .toList();
    expect(after, before);
  });
}
