import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_owner_invoice_numbering.dart';
import 'package:briskers_app/services/local_document_repository.dart';

void main() {
  late BriskersLocalDatabase db;
  setUp(() => db=BriskersLocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());
  const business='synthetic-business';
  Future<void> seed() async {
    await db.customStatement(
      '''INSERT INTO local_jobs(id,business_id,access_scope,title,status,sync_state,vehicle_id)
      VALUES('local-job-test',?,'full','Test job','open','pending','local-vehicle-test')''',[business]);
    await db.customStatement(
      '''INSERT INTO local_documents
      (id,business_id,job_id,customer_id,kind,status,total,sync_state)
      VALUES('local-invoice-test',?,'local-job-test','local-customer-test','invoice','issued',100,'pending')''',[business]);
    final records=<String, Map<String,dynamic>>{
      'customer_create':{'operation_id':'synthetic-customer'},
      'vehicle_create':{'idempotent_v1':true,'customer_id':'local-customer-test'},
      'document_draft_create':{'operation_id':'synthetic-invoice','kind':'invoice'},
      'invoice_payment_received':{
        'operation_id':'synthetic-payment','invoice_id':'local-invoice-test',
        'amount_cents':3000,'method_id':'synthetic-card',
        'payment_date':'2026-10-19',
      },
    };
    for(final entry in records.entries){
      final entity= switch(entry.key){
        'customer_create'=>'local-customer-test',
        'vehicle_create'=>'local-vehicle-test',
        _=>'local-invoice-test',
      };
      await db.customStatement(
        '''INSERT INTO sync_outbox(business_id,entity_type,entity_id,
          operation,payload_json,state,attempt_count,created_at)
          VALUES(?,?,?,'create',?,'pending',0,1793301845)''',
        [business,entry.key,entity,jsonEncode(entry.value)]);
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
    expect(rows.length,4);
    expect(rows.every((x)=>x.read<String>('state')=='conflict'),true);
    expect(rows.any((x)=>jsonDecode(x.read<String>('payload_json'))['operation_id']=='synthetic-payment'),true);
  });
  test('numbered local invoice remains visible and issued in offline list',() async {
    await seed();
    await assign();
    final docs = await LocalDocumentRepository(database:db)
        .listByKind(business,kind:'invoice');
    final local = docs.singleWhere((d)=>d['id']=='local-invoice-test');
    expect(local['document_number'],'8101');
    expect(local['job_number'],'J-8101');
    expect(local['status'],'issued');
    expect(local['display_status'],'Open');
    expect(local['_local_snapshot'],true);
  });
  test('missing recorded payment never assigns invoice number',() async {
    await seed();
    await db.customStatement(
      "DELETE FROM sync_outbox WHERE entity_type='invoice_payment_received'",
    );
    await expectLater(assign(), throwsStateError);
    expect((await invoice())['document_number'],null);
  });
  test('payment amount and UUID are preserved on local numbering',() async {
    await seed();
    await assign();
    final row=await db.customSelect(
      "SELECT payload_json FROM sync_outbox "
      "WHERE entity_type='invoice_payment_received'").getSingle();
    final original=jsonDecode(row.read<String>('payload_json')) as Map;
    expect(original['amount_cents'],3000);
    expect(original['operation_id'],'synthetic-payment');
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
