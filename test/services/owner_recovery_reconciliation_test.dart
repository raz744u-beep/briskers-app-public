import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/owner_recovery_reconciliation.dart';

void main() {
  late BriskersLocalDatabase db;
  setUp(() => db=BriskersLocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());
  Future<void> seed() async {
    await db.customStatement(
      """INSERT INTO local_jobs(id,business_id,access_scope,title,status,
         job_number,sync_state) VALUES('local-job','test','full','Test',
         'open','J-8','pending')""");
    await db.customStatement(
      """INSERT INTO local_documents(id,business_id,job_id,kind,status,
         document_number,total,sync_state) VALUES('local-invoice','test',
         'local-job','invoice','issued','8008',125.00,'pending')""");
    await db.customStatement(
      """INSERT INTO sync_outbox(business_id,entity_type,entity_id,
         operation,payload_json,state,attempt_count,created_at,last_error)
         VALUES('test','invoice_payment_received','local-invoice',
         'record_received_payment',?,'conflict',0,123,
         'Owner recovery payment preserved; sync disabled')""",
      [jsonEncode({'invoice_id':'local-invoice','operation_id':'synthetic-op',
                    'amount_cents':3000,'payment_date':'2026-10-19'})]);
  }
  Future<bool> check({int payment=3000,int total=12500,int count=1}) =>
    OwnerRecoveryReconciliation(database:db).verify(
      isOwner:true,businessId:'test',localInvoiceId:'local-invoice',
      serverInvoiceId:'server-invoice',serverJobId:'server-job',
      invoiceNumber:'8008',jobNumber:'J-8',
      totalCents:total,paymentCents:payment,
      serverPaymentOperationId:'synthetic-op',
      serverPaymentDate:'2026-10-19',
      serverLineCount:2,serverPaymentCount:count);

  test('matching identities leave quarantined outbox unchanged',() async {
    await seed();
    expect(await check(),true);
    final row=await db.customSelect('SELECT state,payload_json FROM sync_outbox')
      .getSingle();
    expect(row.read<String>('state'),'conflict');
    expect(jsonDecode(row.read<String>('payload_json'))['operation_id'],
      'synthetic-op');
  });
  test('rejects incorrect payment amount without changing records',() async {
    await seed();
    await expectLater(check(payment:2000),throwsStateError);
    final row=await db.customSelect('SELECT state FROM sync_outbox').getSingle();
    expect(row.read<String>('state'),'conflict');
  });
  test('rejects missing original payment date identity',() async {
    await seed();
    await db.customStatement("UPDATE sync_outbox SET payload_json=?", [
      jsonEncode({'invoice_id':'local-invoice','operation_id':'synthetic-op','amount_cents':3000,'payment_date':'2026-10-20'})]);
    await expectLater(check(),throwsStateError);
  });
  test('rejects mismatched total and multiple server payments',() async {
    await seed();
    await expectLater(check(total:12600),throwsStateError);
    await expectLater(check(count:2),throwsStateError);
  });
}
