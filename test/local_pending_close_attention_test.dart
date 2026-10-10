import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_repository.dart';

void main() {
  test('ATT-001 counts and retrieves pending-close invoices offline', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    const shop = 'attention-test';
    await db.customStatement(
      "INSERT INTO local_customers (id,business_id,display_name) VALUES "
      "('c',?,'Tester')", [shop],
    );
    await db.customStatement(
      "INSERT INTO local_jobs (id,business_id,access_scope,title,status,"
      "job_number,customer_id,customer_name,vehicle_label) "
      "VALUES ('j',?,'full','Job','open','J-2','c','Tester','2011 Car')",
      [shop],
    );
    for (final row in [
      ['d1','6331','pending_close'],
      ['d2','6332','pending_close'],
      ['d3','6333','closed'],
    ]) {
      await db.customStatement(
        "INSERT INTO local_documents (id,business_id,job_id,customer_id,"
        "kind,document_number,status,display_status_code) "
        "VALUES (?,?,'j','c','invoice',?,'issued',?)",
        [row[0],shop,row[1],row[2]],
      );
    }
    final repo = LocalDocumentRepository(database: db);
    final snapshot = await repo.pendingCloseAttention(shop);
    expect(snapshot['count'], 2);
    final items = List<Map<String,dynamic>>.from(snapshot['items'] as List);
    expect(items.map((e)=>e['document_number']).toSet(), {'6331','6332'});
    expect(items.every((e)=>e['customer_name']=='Tester'), isTrue);
    await db.close();
  });
}
