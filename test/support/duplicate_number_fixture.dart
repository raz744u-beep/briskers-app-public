import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_customer_vehicle_identity.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/local_invoice_closure.dart';
import 'package:briskers_app/services/local_number_allocator.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';

const duplicateOperation = '00000000-0000-4000-8000-000000000111';
const duplicateInvoice = 'local-invoice-$duplicateOperation';
const duplicateJob = 'local-job-$duplicateOperation';
const retainedInvoice = '00000000-0000-4000-8000-000000000222';
const retainedJob = 'server-job';
const duplicateSnapshotKey = 'briskers_document_detail_shop_$duplicateInvoice';

Future<void> seedDuplicateNumbers(BriskersLocalDatabase db) async {
  await db.customStatement("INSERT INTO local_customers(id,business_id,display_name) VALUES"
    "('dakota','shop','Dakota Spinder'),('tyra','shop','Tyra Legard'),('latest','shop','Other')");
  await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,status,customer_id,sync_state) VALUES"
    "(?,'shop','full','J-41','Original','completed','dakota','pending'),"
    "(?,'shop','full','J-41','Newer','in_progress','tyra','synced'),"
    "('latest-job','shop','full','J-61','Latest','open','latest','pending')",[duplicateJob,retainedJob]);
  await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,customer_id,kind,document_number,status,total,closed_at,document_date,sync_state) VALUES"
    "(?,'shop',?,'dakota','invoice','6360','closed',554.2375,1794875052,'2026-11-02','pending'),"
    "(?,'shop',?,'tyra','invoice','6360','draft',4894.21,NULL,'2026-11-17','synced'),"
    "('latest-invoice','shop','latest-job','latest','invoice','6381','issued',100,NULL,'2026-11-18','pending')",
    [duplicateInvoice,duplicateJob,retainedInvoice,retainedJob]);
  await LocalCustomerVehicleIdentity(db).save('shop','local-customer-original','dakota');
  await LocalDocumentSqlStore.write(db,duplicateSnapshotKey,jsonEncode({
    'id':duplicateInvoice,'kind':'invoice','document_number':'6360','job_number':'J-41',
    'job_id':duplicateJob,'customer_id':'local-customer-original','customer_name':'Dakota Spinder',
    'total_amount':554.2375,'paid_amount':0,'pending_payment':0,'status':'issued','closed_at':null,
    'document_date':'2026-11-02','lines':[{'id':'original-line','name':'Original service','quantity':1,'net_amount':505.00}],
  }));
  await db.customStatement("INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,state) VALUES"
    "('shop','document_draft_create',?,'create_invoice',?,'pending'),"
    "('shop','invoice_payment_received',?,'receive',?,'pending')",[
      duplicateInvoice,jsonEncode({'operation_id':duplicateOperation,'kind':'invoice','provisional_job_id':duplicateJob,
        'customer_id':'dakota','local_document_number':'6360','local_job_number':'J-41'}),
      duplicateInvoice,jsonEncode({'operation_id':'receipt-original','invoice_id':duplicateInvoice,
        'amount_cents':55424,'method_id':'cash','method_name':'Cash','payment_date':'2026-11-02'}),
    ]);
  final closures = LocalInvoiceClosureStore(db);
  await closures.prepare(); await closures.prepareIncome();
  await db.customStatement('INSERT INTO local_invoice_closures(business_id,invoice_id,closed_at,operation_id,payload) VALUES (?,?,?,?,?)',
    ['shop',duplicateInvoice,'2026-11-17T00:00:00Z','original-close','{"total_cents":55424,"paid_cents":55424}']);
  await db.customStatement('INSERT INTO local_finalized_invoice_income VALUES (?,?,?,?)',
    ['shop',duplicateInvoice,'receipt-original',jsonEncode({'invoice_id':duplicateInvoice,'operation_id':'receipt-original',
      'receipt_id':'receipt-original','payment_method':'Cash',
      'document_number':'6360','amount':554.24,'transaction_date':'2026-11-02','customer_name':'Dakota Spinder','receipt_state':'local_finalized'})]);
  await closures.saveFinalized('shop',duplicateInvoice,{'receipt-original':55424});
  await LocalPayrollRepository(db,business:'shop',owner:true).prepare();
  await db.customStatement('INSERT INTO regular_payroll_paid_work VALUES (?,?,?,?)',
    ['shop','paid-credit','paid-operation','{"paid_cents":4000,"invoice_id":"unrelated"}']);
  await db.customStatement('INSERT INTO local_financial_cache(business_id,cache_key,payload_json) VALUES (?,?,?)',
    ['shop','original-expenses',jsonEncode([{'id':'expense-original','invoice_id':duplicateInvoice,'job_id':duplicateJob,'amount':200}])]);
  final allocator = LocalNumberAllocator(db);
  await allocator.ensureSchema();
  await allocator.setNextNumber('shop','invoice',6382);
  await allocator.setNextNumber('shop','job',62);
  await db.customStatement('INSERT INTO local_number_reservations VALUES (?,?,?,?,1),(?,?,?,?,1)',
    ['shop','invoice',6360,duplicateInvoice,'shop','job',41,duplicateJob]);
}
