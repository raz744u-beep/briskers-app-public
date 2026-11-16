import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_repository.dart';

void main() {
  late BriskersLocalDatabase db;
  setUp(() => db=BriskersLocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('verified recovery alias hides duplicate server invoice only',() async {
    await db.customStatement(
      """INSERT INTO local_jobs(id,business_id,access_scope,title,status,
         job_number,sync_state) VALUES('local-job','shop','full','Test',
         'open','J-8','pending')""");
    await db.customStatement(
      """INSERT INTO local_documents(id,business_id,job_id,kind,status,
         document_number,total,sync_state) VALUES('local-invoice','shop',
         'local-job','invoice','issued','8008',125.0,'pending')""");
    final repository=LocalDocumentRepository(database:db);
    await repository.listByKind('shop',kind:'invoice');
    await db.customStatement(
      """INSERT INTO owner_recovery_aliases(
         business_id,local_invoice_id,server_invoice_id,server_job_id,
         payment_operation_id,invoice_number,job_number,total_cents,payment_cents)
         VALUES('shop','local-invoice','server-invoice','server-job',
         'operation-one','8008','J-8',12500,3000)""");
    await db.customStatement(
      """INSERT INTO local_documents(id,business_id,job_id,kind,status,
         document_number,total,sync_state) VALUES('server-invoice','shop',
         'local-job','invoice','issued','8008',125.0,'synced')""");
    final invoices=await repository.listByKind('shop',kind:'invoice');
    expect(invoices.map((d)=>d['id']).toList(),['local-invoice']);
    final raw=await db.customSelect(
      "SELECT count(*) AS n FROM local_documents WHERE business_id='shop'").getSingle();
    expect(raw.read<int>('n'),2); // no deletion
  });
}
