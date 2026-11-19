import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/invoice_payment_feed.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/local_duplicate_number_correction.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/duplicate_number_fixture.dart';

class _Store implements OwnerEnrollmentStore {
  @override Future<String?> read() async => null;
  @override Future<void> write(String value) async => throw StateError('No enrollment write');
  @override Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late LocalDuplicateNumberCorrection service;
  late LocalOwnerAuthorization owner;
  late LocalOwnerGrant grant;
  late bool offline;
  const identity = OwnerSessionIdentity('owner','session');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalDocumentDetailCache.sqliteWritesEnabled = true;
    db = BriskersLocalDatabase(NativeDatabase.memory());
    offline = true;
    service = LocalDuplicateNumberCorrection(db,forceOffline:()=>offline);
    owner = LocalOwnerAuthorization(store:_Store(), currentIdentity:()=>identity,
      verifyOwner:(_) async=>throw StateError('Network must not be called'),
      verifyLocalOwner:(b) async=>VerifiedOwnerEnrollment(identity,b),
      authenticateDevice:() async=>throw StateError('Session authorization only'));
    grant = await owner.authorizeSession('shop');
    await seedDuplicateNumbers(db);
  });
  tearDown(() async { LocalDocumentDetailCache.sqliteWritesEnabled=false; await db.close(); });
  Future<DuplicateNumberCorrectionPlan> preview() => service.preview('shop',duplicateInvoice,retainedInvoice);
  Future<List<Map<String,dynamic>>> rows(String table) async =>
    (await db.customSelect('SELECT * FROM $table').get()).map((r)=>r.data).toList();
  Future<Map<String,dynamic>> finances() async => {
    for (final table in ['local_invoice_closures','local_invoice_closed_receipts',
      'local_finalized_invoice_income','regular_payroll_paid_work','local_financial_cache']) table:await rows(table),
    'receipts':(await rows('sync_outbox')).where((r)=>r['entity_type']=='invoice_payment_received').toList(),
  };

  test('preview changes no records and chooses fresh numbers above all current numbers', () async {
    final before = await rows('local_documents');
    final money = await finances();
    final plan = await preview();
    expect(plan.customer,'Dakota Spinder');
    expect(plan.keepCustomer,'Tyra Legard');
    expect(plan.invoiceNumber,6382); expect(plan.jobNumber,62);
    expect(await rows('local_documents'),before);
    expect(await finances(),money);
  });

  test('atomic correction preserves paid history, Closed status and Tyra, and is idempotent', () async {
    final before = await rows('local_documents');
    final originalJob = (await rows('local_jobs')).singleWhere((r)=>r['id']==duplicateJob);
    final keptJob = (await rows('local_jobs')).singleWhere((r)=>r['id']==retainedJob);
    final money = await finances();
    final rawBefore = jsonDecode((await LocalDocumentSqlStore.read(db,duplicateSnapshotKey))!) as Map;
    final plan = await preview();
    await service.apply(plan,grant); await service.apply(plan,grant);
    final after = await rows('local_documents');
    expect(after.singleWhere((r)=>r['id']==retainedInvoice),before.singleWhere((r)=>r['id']==retainedInvoice));
    final original = before.singleWhere((r)=>r['id']==duplicateInvoice);
    expect(after.singleWhere((r)=>r['id']==duplicateInvoice),{...original,'document_number':'6382'});
    expect((await rows('local_jobs')).singleWhere((r)=>r['id']==duplicateJob),{...originalJob,'job_number':'J-62'});
    expect((await rows('local_jobs')).singleWhere((r)=>r['id']==retainedJob),keptJob);
    expect(await finances(),money);
    final rawAfter = jsonDecode((await LocalDocumentSqlStore.read(db,duplicateSnapshotKey))!) as Map;
    expect(rawAfter,{...rawBefore,'document_number':'6382','job_number':'J-62'});
    final create = jsonDecode((await rows('sync_outbox')).singleWhere((r)=>r['entity_type']=='document_draft_create')['payload_json'] as String) as Map;
    expect(create['operation_id'],duplicateOperation);
    expect(create['local_document_number'],'6382'); expect(create['local_job_number'],'J-62');
    final history = await rows('local_invoice_number_corrections');
    expect(history,hasLength(1)); expect(history.single['old_invoice_number'],'6360');
    final held = await rows('local_number_reservations');
    expect(held.singleWhere((r)=>r['kind']=='invoice' && r['number']==6360)['entity_id'],retainedInvoice);
    expect(held.singleWhere((r)=>r['kind']=='job' && r['number']==41)['entity_id'],retainedJob);
    final feed = await InvoicePaymentFeed(database:db).load('shop');
    final receipt = feed.singleWhere((r)=>r['invoice_id']==duplicateInvoice);
    expect(receipt['document_number'],'6382'); expect(receipt['amount'],554.24);
    expect(receipt['transaction_date'],'2026-11-02');
    expect(await finances(),money);
    final saved = await LocalDocumentDetailCache(database:db).loadReadOnly('shop',duplicateInvoice);
    expect(saved?['status'],'closed'); expect(saved?['document_number'],'6382');
  });

  test('job-number race rolls back invoice reservation and both records', () async {
    final plan = await preview();
    final before = await rows('local_documents');
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,status) VALUES('racer','shop','full','J-62','Other','open')");
    await expectLater(service.apply(plan,grant),throwsStateError);
    expect(await rows('local_documents'),before);
    expect((await rows('local_number_reservations')).where((r)=>r['kind']=='invoice' && r['number']==6382),isEmpty);
  });

  test('wrong target, submitted create and revoked Owner cannot mutate', () async {
    await expectLater(service.preview('shop',retainedInvoice,duplicateInvoice),throwsStateError);
    final plan = await preview();
    final before = await rows('local_documents');
    await owner.revoke();
    await expectLater(service.apply(plan,grant),throwsStateError);
    expect(await rows('local_documents'),before);
    grant=await owner.authorizeSession('shop');
    offline=false;
    await expectLater(service.apply(plan,grant),throwsStateError);
    offline=true;
    await db.customStatement("UPDATE sync_outbox SET attempt_count=1 WHERE entity_type='document_draft_create'");
    await expectLater(preview(),throwsStateError);
    expect(await rows('local_documents'),before);
  });

  test('unproved customer identity prevents guessed relinking', () async {
    final before = await rows('local_documents');
    await db.customStatement('DELETE FROM local_customer_vehicle_create_ids');
    final create = (await rows('sync_outbox')).singleWhere((r)=>r['entity_type']=='document_draft_create');
    final payload = jsonDecode(create['payload_json'] as String) as Map;
    await db.customStatement('UPDATE sync_outbox SET payload_json=? WHERE id=?',
      [jsonEncode({...payload,'customer_id':'unproved-customer'}),create['id']]);
    await expectLater(preview(),throwsStateError);
    expect(await rows('local_documents'),before);
  });

  test('a grant for another business cannot authorize the correction', () async {
    final plan = await preview();
    final other = await owner.authorizeSession('other-shop');
    final before = await rows('local_documents');
    await expectLater(service.apply(plan,other),throwsStateError);
    expect(await rows('local_documents'),before);
  });

  test('canonical creation identity can prove an older temporary customer without rewriting it', () async {
    await db.customStatement('DELETE FROM local_customer_vehicle_create_ids');
    final plan = await preview(); await service.apply(plan,grant);
    final raw = jsonDecode((await LocalDocumentSqlStore.read(db,duplicateSnapshotKey))!) as Map;
    expect(raw['customer_id'],'local-customer-original');
    expect((await rows('local_documents')).singleWhere((r)=>r['id']==duplicateInvoice)['customer_id'],'dakota');
  });

  test('stale preview stops if the saved closure or creation changes', () async {
    final plan = await preview();
    await db.customStatement('UPDATE local_documents SET closed_at=closed_at+1 WHERE id=?',[duplicateInvoice]);
    await expectLater(service.apply(plan,grant),throwsStateError);
    expect((await rows('local_documents')).singleWhere((r)=>r['id']==duplicateInvoice)['document_number'],'6360');
  });

  test('correction survives SQLite restart and a server list refresh', () async {
    final dir = await Directory.systemTemp.createTemp('number-correction-');
    addTearDown(()=>dir.delete(recursive:true));
    await db.close();
    db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/shop.sqlite')));
    await seedDuplicateNumbers(db);
    service=LocalDuplicateNumberCorrection(db,forceOffline:()=>true);
    final plan = await preview(); await service.apply(plan,grant);
    await db.close(); db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/shop.sqlite')));
    await LocalDocumentRepository(database:db).replaceFromServer('shop',[
      {'id':retainedInvoice,'kind':'invoice','document_number':'6360','job_id':retainedJob,
        'customer_id':'tyra','total_amount':4894.21,'status':'draft'}],kind:'invoice');
    final local = (await rows('local_documents')).singleWhere((r)=>r['id']==duplicateInvoice);
    expect(local['document_number'],'6382'); expect(local['status'],'closed');
    expect((await rows('local_invoice_number_corrections')).single['kept_invoice_id'],retainedInvoice);
  });
}
