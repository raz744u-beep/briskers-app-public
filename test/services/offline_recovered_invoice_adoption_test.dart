import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_recovered_invoice_adoption.dart';

void main() {
  late BriskersLocalDatabase db;
  setUp(() => db = BriskersLocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  const b = 'synthetic-business';
  const lc = 'local-customer-test';
  const lv = 'local-vehicle-test';
  const lj = 'local-job-test';
  const li = 'local-invoice-test';
  const sc = 'remote-customer-test';
  const sv = 'remote-vehicle-test';
  const sj = 'remote-job-test';
  const si = 'remote-invoice-test';
  const invoiceOp = 'synthetic-invoice-operation';
  const receiptOp = 'synthetic-receipt-operation';

  final remoteInvoice = <String, dynamic>{
    'id': si,
    'business_id': b,
    'customer_id': sc,
    'vehicle_id': sv,
    'job_id': sj,
    'kind': 'invoice',
    'document_number': 'T-100',
    'status': 'issued',
    'display_status_code': 'open',
    'total_amount': 100.00,
    'line_count': 2,
    'offline_operation_id': invoiceOp,
  };
  final remoteReceipt = <String, dynamic>{
    'invoice_id': si,
    'operation_id': receiptOp,
    'amount': 30.00,
    'method_id': 'synthetic-method',
    'payment_date': '2026-10-19',
  };

  Future<void> queue(String type, String id, String operation,
      Map<String, dynamic> payload) async {
    await db.customStatement(
      '''INSERT INTO sync_outbox
       (business_id,entity_type,entity_id,operation,payload_json,
        state,attempt_count,created_at)
       VALUES(?,?,?,?,?,'pending',0,1793301845)''',
      [b,type,id,operation,jsonEncode(payload)],
    );
  }

  Future<void> seed({bool withProvisionalJob = false}) async {
    await db.customStatement(
      '''INSERT INTO local_customers(id,business_id,display_name,sync_state)
         VALUES(?,?,'Synthetic customer','pending')''',[lc,b],
    );
    await db.customStatement(
      '''INSERT INTO local_vehicles(id,business_id,make,model,sync_state)
         VALUES(?,?,'Test','Model','pending')''',[lv,b],
    );
    await db.customStatement(
      '''INSERT INTO local_customer_vehicles(business_id,customer_id,vehicle_id)
         VALUES(?,?,?)''',[b,lc,lv],
    );
    if (withProvisionalJob) {
      await db.customStatement(
        '''INSERT INTO local_jobs
         (id,business_id,access_scope,title,status,customer_id,vehicle_id,sync_state)
         VALUES(?,?,'full','Synthetic invoice','open',?,?,'pending')''',
        [lj,b,lc,lv],
      );
    }
    await db.customStatement(
      '''INSERT INTO local_documents
       (id,business_id,job_id,customer_id,kind,status,total,sync_state)
       VALUES(?,?,?,?,'invoice','issued',100,'pending')''',
      [li,b,lj,lc],
    );
    await queue('customer_create',lc,'create',{'operation_id':'synthetic-customer-op'});
    await queue('vehicle_create',lv,'update',{'idempotent_v1':true,'customer_id':lc});
    await queue('document_draft_create',li,'create_quick_invoice',{
      'operation_id':invoiceOp,'customer_id':lc,'vehicle_id':lv,
      'kind':'invoice',
    });
    await queue('invoice_payment_received',li,'record_received_payment',{
      'operation_id':receiptOp,'invoice_id':li,'amount_cents':3000,
      'method_id':'synthetic-method','payment_date':'2026-10-19',
    });
  }

  Future<void> adopt({bool owner = true,
      Map<String,dynamic>? invoice,
      List<Map<String,dynamic>>? payments}) {
    return OfflineRecoveredInvoiceAdoption(database: db).apply(
      isOwner:owner,businessId:b,
      localCustomerId:lc,localVehicleId:lv,
      localJobId:lj,localInvoiceId:li,
      invoiceOperationId:invoiceOp,paymentOperationId:receiptOp,
      serverCustomerId:sc,serverVehicleId:sv,
      serverJobId:sj,serverInvoiceId:si,
      totalCents:10000,paymentCents:3000,lineCount:2,
      paymentMethodId:'synthetic-method',paymentDate:'2026-10-19',
      serverInvoice:invoice ?? remoteInvoice,
      serverPayments:payments ?? [remoteReceipt],
    );
  }

  Future<int> count(String table) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS n FROM $table WHERE business_id=?',
      variables:[const Variable<String>(b)],
    ).getSingle();
    return row.read<int>('n');
  }

  test('successful adoption quarantines original financial operations',
      () async {
    await seed(withProvisionalJob:true);
    await adopt();
    final original = await db.customSelect(
      "SELECT entity_type,state,entity_id,payload_json FROM sync_outbox "
      "WHERE business_id=? ORDER BY id",
      variables:[const Variable<String>(b)],
    ).get();
    expect(original.length,2);
    expect(original.map((r) => r.read<String>('state')).toSet(),
        {'conflict'});
    expect(original.map((r) => r.read<String>('entity_type')).toSet(),
        {'document_draft_create','invoice_payment_received'});
    final paymentRow = original.singleWhere((r) =>
        r.read<String>('entity_type') == 'invoice_payment_received');
    final paymentPayload =
        jsonDecode(paymentRow.read<String>('payload_json')) as Map;
    expect(paymentPayload['operation_id'],receiptOp);
    expect(paymentPayload['invoice_id'],si);
    expect(paymentPayload['amount_cents'],3000);
    final customer = await db.customSelect(
      "SELECT id FROM local_customers WHERE business_id=?",
      variables:[const Variable<String>(b)],
    ).getSingle();
    expect(customer.read<String>('id'),sc);
    final vehicle = await db.customSelect(
      "SELECT id FROM local_vehicles WHERE business_id=?",
      variables:[const Variable<String>(b)],
    ).getSingle();
    expect(vehicle.read<String>('id'),sv);
    final invoice = await db.customSelect(
      "SELECT status,document_number FROM local_documents "
      "WHERE business_id=? AND id=?",
      variables:[const Variable<String>(b),const Variable<String>(si)],
    ).getSingle();
    expect(invoice.read<String>('status'),'issued');
    expect(invoice.read<String>('document_number'),'T-100');
  });

  test('repeat adoption is rejected without reviving payment replay',
      () async {
    await seed(withProvisionalJob:true);
    await adopt();
    await expectLater(adopt(), throwsStateError);
    final rows = await db.customSelect(
      "SELECT entity_type,state,payload_json FROM sync_outbox "
      "WHERE business_id=? ORDER BY id",
      variables:[const Variable<String>(b)],
    ).get();
    expect(rows.length,2);
    expect(rows.map((r) => r.read<String>('state')).toSet(),
        {'conflict'});
    final receipt = rows.singleWhere((r) =>
        r.read<String>('entity_type') == 'invoice_payment_received');
    final payload = jsonDecode(receipt.read<String>('payload_json')) as Map;
    expect(payload['operation_id'], receiptOp);
    expect(payload['amount_cents'],3000);
    final local = await db.customSelect(
      "SELECT COUNT(*) AS n FROM local_documents "
      "WHERE business_id=? AND id=?",
      variables:[const Variable<String>(b),const Variable<String>(si)],
    ).getSingle();
    expect(local.read<int>('n'),1);
  });

  test('missing original customer operation identity rolls back safely',
      () async {
    await seed(withProvisionalJob:true);
    await db.customStatement(
      """UPDATE sync_outbox SET payload_json='{}'
         WHERE business_id=? AND entity_type='customer_create'""",
      [b],
    );
    await expectLater(adopt(), throwsStateError);
    final rows=await db.customSelect(
      "SELECT COUNT(*) AS n FROM sync_outbox WHERE business_id=? AND state='pending'",
      variables:[const Variable<String>(b)],
    ).getSingle();
    expect(rows.read<int>('n'),4);
  });

  test('mismatched invoice dependencies cannot be adopted', () async {
    await seed(withProvisionalJob:true);
    await db.customStatement(
      """UPDATE sync_outbox SET payload_json=?
         WHERE business_id=? AND entity_type='document_draft_create'""",
      [jsonEncode({'operation_id':invoiceOp,'kind':'invoice',
        'customer_id':'different-customer','vehicle_id':lv}),b],
    );
    await expectLater(adopt(), throwsStateError);
    final rows=await db.customSelect(
      "SELECT COUNT(*) AS n FROM sync_outbox WHERE business_id=? AND state='pending'",
      variables:[const Variable<String>(b)],
    ).getSingle();
    expect(rows.read<int>('n'),4);
  });

  test('non-Owner leaves all original queued operations unchanged', () async {
    await seed();
    await expectLater(adopt(owner:false),throwsStateError);
    expect(await count('sync_outbox'),4);
    expect(await count('local_customers'),1);
    expect(await count('local_vehicles'),1);
  });

  test('payment mismatch fails before any local mutation', () async {
    await seed();
    await expectLater(adopt(payments:[
      {...remoteReceipt,'payment_date':'2026-10-20'}
    ]),throwsStateError);
    expect(await count('sync_outbox'),4);
    final row=await db.customSelect(
      'SELECT id FROM local_customers WHERE business_id=?',
      variables:[const Variable<String>(b)],
    ).getSingle();
    expect(row.read<String>('id'),lc);
  });

  test('missing provisional job rolls back customer and vehicle mapping',
      () async {
    await seed();
    await expectLater(adopt(),throwsStateError);
    expect(await count('sync_outbox'),4);
    final customer=await db.customSelect(
      'SELECT id,sync_state FROM local_customers WHERE business_id=?',
      variables:[const Variable<String>(b)],
    ).getSingle();
    final vehicle=await db.customSelect(
      'SELECT id,sync_state FROM local_vehicles WHERE business_id=?',
      variables:[const Variable<String>(b)],
    ).getSingle();
    expect(customer.read<String>('id'),lc);
    expect(vehicle.read<String>('id'),lv);
    expect(await count('local_documents'),1);
  });
}
