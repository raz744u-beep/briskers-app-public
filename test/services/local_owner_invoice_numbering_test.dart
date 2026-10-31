import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_owner_invoice_numbering.dart';

void main() {
  late BriskersLocalDatabase db;
  setUp(() => db=BriskersLocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());
  const business='synthetic-business';
  Future<void> seed() async {
    await db.customStatement(
      '''INSERT INTO local_jobs(id,business_id,access_scope,title,status,sync_state)
      VALUES('local-job-test',?,'full','Test job','open','pending')''',[business]);
    await db.customStatement(
      '''INSERT INTO local_documents
      (id,business_id,job_id,kind,status,total,sync_state)
      VALUES('local-invoice-test',?,'local-job-test','invoice','issued',100,'pending')''',[business]);
    for(final type in const ['document_draft_create','invoice_payment_received']){
      await db.customStatement(
        '''INSERT INTO sync_outbox(business_id,entity_type,entity_id,
          operation,payload_json,state,attempt_count,created_at)
          VALUES(?,?,'local-invoice-test','create',?,'pending',0,1793301845)''',
        [business,type,jsonEncode({'operation_id':'synthetic-operation'})]);
    }
  }
  Future<void> assign({bool owner=true,String invoice='8101',String job='J-8101'}) =>
    LocalOwnerInvoiceNumbering(database:db).assign(
      isOwner:owner,businessId:business,invoiceId:'local-invoice-test',
      jobId:'local-job-test',invoiceNumber:invoice,jobNumber:job);
  Future<Map<String,dynamic>> invoice() async =>
    (await db.customSelect('SELECT * FROM local_documents WHERE id=?',
      variables:[const Variable<String>('local-invoice-test')]).getSingle()).data;

  test('assigns numbers without creating invoice or deleting payment',() async {
    await seed();await assign();
    expect((await invoice())['document_number'],'8101');
    final rows=await db.customSelect('SELECT state,payload_json FROM sync_outbox').get();
    expect(rows.length,2);
    expect(rows.every((x)=>x.read<String>('state')=='conflict'),true);
    expect(rows.every((x)=>jsonDecode(x.read<String>('payload_json'))['operation_id']=='synthetic-operation'),true);
  });
  test('non-Owner cannot change numbers',() async {
    await seed();await expectLater(assign(owner:false),throwsStateError);
    expect((await invoice())['document_number'],null);
  });
  test('invoice number collision rolls back both numbers',() async {
    await seed();
    await db.customStatement(
      '''INSERT INTO local_documents(id,business_id,kind,status,
        document_number,sync_state) VALUES('other-invoice',?,'invoice',
        'issued','8101','synced')''',[business]);
    await expectLater(assign(),throwsStateError);
    expect((await invoice())['document_number'],null);
    final j=await db.customSelect("SELECT job_number FROM local_jobs WHERE id='local-job-test'").getSingle();
    expect(j.readNullable<String>('job_number'),null);
  });
  test('job number collision rolls back invoice update',() async {
    await seed();
    await db.customStatement(
      '''INSERT INTO local_jobs(id,business_id,access_scope,title,
        status,job_number) VALUES('other-job',?,'full','Other','open','J-8101')''',[business]);
    await expectLater(assign(),throwsStateError);
    expect((await invoice())['document_number'],null);
  });
}
