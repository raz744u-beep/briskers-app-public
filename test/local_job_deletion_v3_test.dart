import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart' hide LocalFinancialCache;
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_job_deletion_v3.dart';
import 'package:briskers_app/services/local_job_quarantine.dart';
import 'package:briskers_app/services/local_job_retirement.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const business = '10000000-0000-4000-8000-000000000001';
const job = '10000000-0000-4000-8000-000000000002';
const invoice = '10000000-0000-4000-8000-000000000003';
const estimate = '10000000-0000-4000-8000-000000000004';
const transaction = '10000000-0000-4000-8000-000000000005';
const payment = '10000000-0000-4000-8000-000000000006';
const operation = '10000000-0000-4000-8000-000000000007';
const other = '10000000-0000-4000-8000-000000000008';
const attachment = '10000000-0000-4000-8000-000000000009';
const inspection = '10000000-0000-4000-8000-000000000010';
const photo = '10000000-0000-4000-8000-000000000011';
const finding = '10000000-0000-4000-8000-000000000012';

Map<String, dynamic> entity(String kind, String id) => {'entity_kind': kind, 'entity_id': id};
List<Map<String, dynamic>> identities() => [entity('job', job), entity('invoice', invoice),
  entity('estimate', estimate), entity('payment', payment), entity('transaction', transaction)];
Map<String, dynamic> receipt([List<Map<String, dynamic>>? ids]) => {
  'schema_version': 3, 'protocol_version': LocalJobDeletionV3.protocol,
  'business_id': business, 'job_id': job, 'operation_id': operation,
  'graph_hash': List.filled(64, 'a').join(), 'deleted_entities': ids ?? identities(),
  'status': 'deleted', 'storage_cleanup': 'not_required', 'status_version': 1,
};

Future<int> count(BriskersLocalDatabase db, String table) async =>
    (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle()).read<int>('n');
Future<void> seed(BriskersLocalDatabase db) async {
  await db.customStatement("INSERT INTO local_jobs (id,business_id,access_scope,title,status) VALUES (?,?,'full','Private Job text','open')", [job, business]);
  await db.customStatement("INSERT INTO local_documents (id,business_id,job_id,kind,status) VALUES (?,?,?,'invoice','paid')", [invoice, business, job]);
  await db.customStatement("INSERT INTO local_documents (id,business_id,job_id,kind,status) VALUES (?,?,?,'estimate','accepted')", [estimate, business, job]);
  await db.customStatement("INSERT INTO local_documents (id,business_id,job_id,kind,status) VALUES (?,?,NULL,'invoice','paid')", [other, business]);
  await db.customStatement("INSERT INTO local_customers (id,business_id,display_name) VALUES ('shared-customer',?,'Keep customer')", [business]);
  await db.customStatement("INSERT INTO local_findings (id,business_id,found_job_id,repair_job_id,body,status) VALUES (?,?,NULL,NULL,'Keep shared finding','open')", [finding, business]);
}
Future<int> enqueue(BriskersLocalDatabase db, String type, String id, Map<String, dynamic> payload,
    {String action = 'update'}) async {
  await db.customStatement('INSERT INTO sync_outbox (business_id,entity_type,entity_id,operation,payload_json) VALUES (?,?,?,?,?)',
      [business, type, id, action, jsonEncode(payload)]);
  return (await db.customSelect('SELECT MAX(id) AS id FROM sync_outbox').getSingle()).read<int>('id');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late Directory support;
  setUp(() async {
    LocalJobDeletionV3.currentActorIdProvider = null;
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    support = await Directory.systemTemp.createTemp('briskers-v3-test-');
    await seed(db);
  });
  tearDown(() async {
    LocalJobDeletionV3.currentActorIdProvider = null;
    await db.close();
    await support.delete(recursive: true);
  });

  test('only verified exact identities purge, including paid invoice and estimate', () async {
    final cache = LocalDocumentDetailCache(database: db);
    await cache.save(business, invoice, {'id': invoice, 'kind': 'invoice', 'memo': 'private invoice',
      'paid_amount': 125, 'payments': [{'id': payment, 'amount': 125}]});
    await cache.save(business, estimate, {'id': estimate, 'kind': 'estimate', 'memo': 'private estimate'});
    await cache.save(business, other, {'id': other, 'kind': 'invoice', 'memo': 'keep'});
    await enqueue(db, 'financial_update', other, {'transaction_id': other, 'remarks': 'unrelated unsynced'});
    await LocalFinancialCache(database: db).saveTransactions(business, [
      {'id': transaction, 'amount': 125}, {'id': other, 'remarks': 'keep projection'},
    ]);
    final result = await LocalJobDeletionV3.applyVerifiedReceipt(db, receipt: receipt());
    expect(result.complete, isTrue);
    expect(await count(db, 'local_jobs'), 0);
    expect(await count(db, 'local_documents'), 1);
    expect(await count(db, 'local_customers'), 1);
    expect(await count(db, 'local_findings'), 1);
    expect(await count(db, 'sync_outbox'), 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('briskers_document_detail_${business}_$invoice'), isNull);
    expect(prefs.getString('briskers_document_detail_${business}_$estimate'), isNull);
    expect((await cache.load(business, other))!['memo'], 'keep');
    final columns = await db.customSelect('PRAGMA table_info(local_job_deletion_v3_entities)').get();
    expect(columns.map((r) => r.read<String>('name')), unorderedEquals(
      ['business_id','job_id','operation_id','entity_kind','entity_id']));
  });

  test('invalid or v2 receipt cannot delete or establish markers', () async {
    for (final invalid in [
      {...receipt(), 'schema_version': 2},
      {...receipt(), 'status': 'accepted'},
      {...receipt(), 'deleted_entities': [entity('job', job), entity('unknown_table', invoice)]},
      {...receipt(), 'deleted_entities': [entity('job', job), entity('invoice', '6346')]},
      {...receipt(), 'deleted_entities': [entity('invoice', invoice)]},
      {...receipt(), 'storage_cleanup': 'pending'},
    ]) {
      await expectLater(LocalJobDeletionV3.applyVerifiedReceipt(db, receipt: invalid), throwsFormatException);
    }
    expect(await count(db, 'local_jobs'), 1);
  });

  test('permanent markers fence late invoice, estimate, payment, transaction and operation writes', () async {
    final ids = [...identities(), entity('operation', 'invoice_payment/old-key')];
    expect((await LocalJobDeletionV3.applyVerifiedReceipt(db, receipt: receipt(ids))).complete, isTrue);
    for (final item in [invoice, estimate]) {
      await expectLater(db.customStatement("INSERT INTO local_documents (id,business_id,kind) VALUES (?,?,?)",
          [item, business, item == invoice ? 'invoice' : 'estimate']), throwsA(isA<Exception>()));
    }
    for (final payload in [
      {'pending_payment_id': payment}, {'transaction_id': transaction},
    ]) {
      await expectLater(enqueue(db, 'financial_update', other, payload), throwsA(isA<Exception>()));
    }
    await expectLater(enqueue(db, 'invoice_payment_received', other, {'operation_id': 'old-key'}), throwsA(isA<Exception>()));
    await enqueue(db, 'unrelated_namespace', other, {'operation_id': 'old-key'});
    await expectLater(db.customStatement('DELETE FROM local_job_deletion_v3_entities'), throwsA(isA<Exception>()));
    await expectLater(db.customStatement('INSERT OR REPLACE INTO local_job_deletion_v3_entities '
      '(business_id,job_id,operation_id,entity_kind,entity_id) VALUES (?,?,?,?,?)',
      [business, other, other, 'invoice', invoice]), throwsA(isA<Exception>()));
    await expectLater(db.customStatement("INSERT INTO local_financial_cache (business_id,cache_key,payload_json) VALUES (?, 'late', ?)",
      [business, jsonEncode({'payments': [{'id': payment}]})]), throwsA(isA<Exception>()));
  });

  test('pending intent is reversible and cannot authorize erasure', () async {
    await LocalJobDeletionV3.setPendingIntent(db, businessId: business, jobId: job,
        operationId: operation, deletedEntities: identities());
    expect(await count(db, 'local_jobs'), 1);
    expect(await count(db, 'local_documents'), 3);
    expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
    expect(await LocalJobRetirement.isDocumentBlocked(db, business, estimate), isTrue);
    expect(await LocalJobDeletionV3.isEntityDeleted(db, business, 'job', job), isFalse);
    await expectLater(enqueue(db, 'document_edit', invoice, {'document_id': invoice}), throwsA(isA<Exception>()));
    await LocalJobDeletionV3.releasePendingIntent(db, business, operation);
    expect(await LocalJobRetirement.isJobBlocked(db, business, job), isFalse);
    await enqueue(db, 'document_edit', invoice, {'document_id': invoice});
  });

  test('preflight blocks unconfirmed edits and malformed queue without changing data', () async {
    await enqueue(db, 'document_edit', invoice, {'document_id': invoice, 'memo': 'new edit'});
    await expectLater(LocalJobDeletionV3.assertNoUnconfirmedLocalChanges(db, business, identities()), throwsStateError);
    expect(await count(db, 'sync_outbox'), 1);
    await db.customStatement('DELETE FROM sync_outbox');
    await db.customStatement("INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json) VALUES (?,'unknown',?,'update','not-json')", [business, other]);
    await expectLater(LocalJobDeletionV3.assertNoUnconfirmedLocalChanges(db, business, identities()), throwsStateError);
    expect(await count(db, 'local_jobs'), 1);
  });

  test('cross-device receipt preserves newer local work hidden and reports cleanup pending', () async {
    await db.customStatement("UPDATE local_documents SET sync_state='pending' WHERE id=?", [invoice]);
    await enqueue(db, 'invoice_payment_received', invoice, {'operation_id': 'unconfirmed-payment', 'invoice_id': invoice, 'amount_cents': 10000});
    await LocalDocumentDetailCache(database: db).save(business, invoice,
      {'id': invoice, 'kind': 'invoice', 'sync_state': 'pending', 'memo': 'new offline edit'});
    final result = await LocalJobDeletionV3.applyVerifiedReceipt(db, receipt: receipt());
    expect(result.complete, isFalse);
    expect(result.issueCode, 'reconciliation_pending');
    expect(await count(db, 'sync_outbox'), 1);
    expect((await db.customSelect("SELECT sync_state FROM local_documents WHERE id='$invoice'").getSingle()).read<String>('sync_state'), 'pending');
    expect(await LocalDocumentDetailCache(database: db).load(business, invoice), isNull);
    expect((await SharedPreferences.getInstance()).getString('briskers_document_detail_${business}_$invoice'), contains('new offline edit'));
    await expectLater(LocalJobQuarantine.assertReplayAllowed(db, business, outboxId: 1), throwsStateError);
  });

  test('acknowledged pending payment payload is erased only by own payment or namespaced operation', () async {
    await enqueue(db, 'invoice_payment_received', invoice,
      {'operation_id': 'paid-key', 'invoice_id': invoice, 'server_payment_id': payment, 'amount_cents': 12500});
    await enqueue(db, 'other_namespace', other, {'operation_id': 'paid-key', 'memo': 'keep unrelated'});
    final result = await LocalJobDeletionV3.applyVerifiedReceipt(db,
      receipt: receipt([...identities(), entity('operation', 'invoice_payment/paid-key')]));
    expect(await count(db, 'sync_outbox'), 1);
    expect((await db.customSelect('SELECT entity_type FROM sync_outbox').getSingle()).read<String>('entity_type'), 'other_namespace');
    // A coincidentally equal raw key in another namespace is not this operation.
    expect(result.complete, isTrue);
    await LocalJobQuarantine.assertReplayAllowed(db, business, outboxId: 2);
  });

  test('scoped feed can omit job, expand, then receive full immutable receipt', () async {
    Map<String, dynamic> group(List<Map<String, dynamic>> ids) => {
      'scope_complete': true, 'business_id': business, 'job_id': job,
      'operation_id': operation, 'deleted_entities': ids, 'status': 'deleted',
      'storage_cleanup': 'not_required', 'status_version': 1,
    };
    await LocalJobDeletionV3.applyVerifiedTombstone(db, group([entity('invoice', invoice)]));
    expect(await count(db, 'local_jobs'), 1);
    await LocalJobDeletionV3.applyVerifiedTombstone(db, group(identities()));
    expect((await LocalJobDeletionV3.applyVerifiedReceipt(db, receipt: receipt())).complete, isTrue);
    await expectLater(LocalJobDeletionV3.applyVerifiedReceipt(db,
      receipt: receipt([...identities(), entity('appointment', other)])), throwsStateError);
  });

  test('late preference and financial cache results cannot resurrect deleted identities', () async {
    await LocalJobDeletionV3.applyVerifiedReceipt(db, receipt: receipt());
    final detail = LocalDocumentDetailCache(database: db);
    await detail.save(business, estimate, {'id': estimate, 'kind': 'estimate', 'memo': 'late'});
    await detail.save(business, 'local-alias', {'id': invoice, 'kind': 'invoice', 'memo': 'late alias'});
    expect(await detail.load(business, estimate), isNull);
    expect((await SharedPreferences.getInstance()).getString('briskers_document_detail_${business}_local-alias'), isNull);
    final financial = LocalFinancialCache(database: db);
    await financial.saveTransactions(business, [{'id': transaction, 'amount': 999}, {'id': other, 'amount': 5}]);
    expect((await financial.loadTransactions(business)).map((e) => e['id']), [other]);
    await financial.saveTransactionDetail(business, transaction, {'id': transaction, 'amount': 999});
    expect(await financial.loadTransactionDetail(business, transaction), isNull);
  });

  test('app-owned media is removed and SAF original file remains untouched', () async {
    final local = File('${support.path}/briskers_media/$business/preinspection/$job/owned.jpg');
    await local.parent.create(recursive: true);
    await local.writeAsString('private photo');
    final original = File('${support.path}/external.jpg');
    await original.writeAsString('external original');
    await db.customStatement('INSERT INTO local_pre_inspections(id,business_id,job_id) VALUES (?,?,?)', [inspection, business, job]);
    await db.customStatement('INSERT INTO local_pre_inspection_photos(id,business_id,inspection_id,attachment_id,local_file_path) VALUES (?,?,?,?,?)',
      [photo, business, inspection, attachment, local.path]);
    await db.customStatement('INSERT INTO local_expense_iq_photos(business_id,transaction_id,photo_id,filename,source_uri,updated_at) VALUES (?,?,?,?,?,0)',
      [business, transaction, photo, 'external.jpg', original.uri.toString()]);
    final result = await LocalJobDeletionV3.applyVerifiedReceipt(db,
      receipt: receipt([...identities(), entity('pre_inspection', inspection), entity('pre_inspection_photo', photo), entity('attachment', attachment)]),
      mediaDirectoryProvider: () async => support);
    expect(result.complete, isTrue);
    expect(await local.exists(), isFalse);
    expect(await original.readAsString(), 'external original');
    expect(await count(db, 'local_job_deletion_v3_media'), 0);
    expect(await count(db, 'local_expense_iq_photos'), 0);
  });

  test('outside-root and shared file references prevent erasure and remain pending', () async {
    final external = File('${support.path}/outside.jpg');
    await external.writeAsString('must keep');
    await db.customStatement('INSERT INTO local_pre_inspections(id,business_id,job_id) VALUES (?,?,?)', [inspection, business, job]);
    await db.customStatement('INSERT INTO local_pre_inspection_photos(id,business_id,inspection_id,attachment_id,local_file_path) VALUES (?,?,?,?,?)',
      [photo, business, inspection, attachment, external.path]);
    final result = await LocalJobDeletionV3.applyVerifiedReceipt(db,
      receipt: receipt([...identities(), entity('pre_inspection', inspection), entity('pre_inspection_photo', photo), entity('attachment', attachment)]),
      mediaDirectoryProvider: () async => support);
    expect(result.complete, isFalse);
    expect(await external.exists(), isTrue);
    expect(await count(db, 'local_job_deletion_v3_media'), 1);
    await LocalJobDeletionV3.resumePendingCleanup(db, business, mediaDirectoryProvider: () async => support);
    expect(await external.exists(), isTrue);
  });

  test('cleanup failure keeps durable fences, and retry resumes after failure is removed', () async {
    await db.customStatement("CREATE TRIGGER simulate_failure BEFORE DELETE ON local_documents BEGIN SELECT RAISE(ABORT,'disk fixture failure'); END");
    final failed = await LocalJobDeletionV3.applyVerifiedReceipt(db, receipt: receipt());
    expect(failed.complete, isFalse);
    expect(await LocalJobDeletionV3.isEntityDeleted(db, business, 'job', job), isTrue);
    expect(await LocalJobRetirement.isDocumentBlocked(db, business, estimate), isTrue);
    expect(await count(db, 'local_jobs'), 1); // scrub transaction rolled back
    await db.customStatement('DROP TRIGGER simulate_failure');
    await LocalJobDeletionV3.resumePendingCleanup(db, business);
    expect(await count(db, 'local_jobs'), 0);
    expect((await db.customSelect('SELECT state FROM local_job_deletion_v3_cleanup').getSingle()).read<String>('state'), 'complete');
  });

  test('v2 accepted immutability is preserved and never treated as v3 consent', () async {
    await LocalJobRetirement.ensureSchema(db);
    await LocalJobRetirement.recordEntity(db, businessId: business, jobId: job,
      entityKind: 'invoice', entityId: invoice, operationId: other, state: 'accepted');
    final result = await LocalJobDeletionV3.applyVerifiedReceipt(db, receipt: receipt());
    expect(result.complete, isFalse);
    expect(await count(db, 'local_job_retirement_entities'), 1);
    expect(await count(db, 'local_documents'), 3);
  });

  test('standalone estimate operation fences its local alias and preserves unknown namespace collisions', () async {
    const alias = 'local-estimate-draft';
    await db.customStatement("INSERT INTO local_documents(id,business_id,kind,sync_state) VALUES (?,?,'estimate','pending')", [alias,business]);
    await enqueue(db, 'document_draft_create', alias, {'operation_id':'estimate-key','kind':'estimate',
      'local_id':alias, 'customer_id':'shared-customer'}, action:'create_estimate');
    await enqueue(db, 'unrelated_namespace', other, {'operation_id':'estimate-key'});
    final result = await LocalJobDeletionV3.applyVerifiedReceipt(db,
      receipt:receipt([...identities(),entity('operation','standalone_estimate/estimate-key')]));
    expect(await LocalJobRetirement.isDocumentBlocked(db,business,alias), isTrue);
    expect(await count(db,'sync_outbox'),1);
    expect(await count(db,'local_job_deletion_v3_aliases'),1);
    // The local draft's unconfirmed contents are retained for reconciliation.
    expect(result.complete,isFalse);
    await expectLater(enqueue(db,'document_draft_create','local-new',{'operation_id':'estimate-key',
      'kind':'estimate'},action:'create_estimate'),throwsA(isA<Exception>()));
  });

  test('embedded or malformed recovery JSON and malformed financial cache cannot disappear silently', () async {
    await db.customStatement('CREATE TABLE local_job_recovery_rows(id INTEGER PRIMARY KEY,business_id TEXT,job_id TEXT,table_name TEXT,original_key TEXT,row_json TEXT)');
    await db.customStatement('INSERT INTO local_job_recovery_rows VALUES (1,?,?,?,?,?)',
      [business,job,'sync_outbox','outside',jsonEncode({'entity_type':'unknown',
        'entity_id':other,'payload_json':jsonEncode({'invoice_id':invoice,'secret':'keep unknown'})})]);
    await db.customStatement('INSERT INTO local_job_recovery_rows VALUES (2,?,?,?,?,?)',
      [business,job,'local_documents',invoice,'malformed original']);
    await db.customStatement("INSERT INTO local_financial_cache(business_id,cache_key,payload_json) VALUES (?,'unknown','malformed cache')",[business]);
    final result = await LocalJobDeletionV3.applyVerifiedReceipt(db,receipt:receipt());
    expect(result.complete,isFalse);
    expect(result.issueCode,'reconciliation_pending');
    expect(await count(db,'local_job_recovery_rows'),2);
    expect(await count(db,'local_financial_cache'),1);
  });

  test('rejected v2 previews and intentions are scrubbed without upgrading old consent', () async {
    await LocalJobRetirement.ensureSchema(db);
    await db.customStatement('INSERT INTO local_job_retirement_requests(business_id,job_id,operation_id,actor_id,snapshot_json,state,created_at) VALUES (?,?,?,?,?,?,0)',
      [business,job,other,other,jsonEncode({'job_id':job,'memo':'old private contents'}),'rejected']);
    await db.customStatement('CREATE TABLE local_job_deletion_v3_intentions(business_id TEXT,job_id TEXT,actor_id TEXT)');
    await db.customStatement('INSERT INTO local_job_deletion_v3_intentions VALUES (?,?,?)',[business,job,other]);
    final result = await LocalJobDeletionV3.applyVerifiedReceipt(db,receipt:receipt());
    expect(result.complete,isTrue);
    final row=await db.customSelect('SELECT snapshot_json,state FROM local_job_retirement_requests').getSingle();
    expect(row.read<String>('snapshot_json'),'{}');
    expect(row.read<String>('state'),'rejected');
    expect(await count(db,'local_job_deletion_v3_intentions'),0);
  });

  test('shared media is retained until no unrelated reference remains', () async {
    final file=File('${support.path}/briskers_media/$business/preinspection/$job/shared.jpg');
    await file.parent.create(recursive:true); await file.writeAsString('shared');
    await db.customStatement('INSERT INTO local_pre_inspections(id,business_id,job_id) VALUES (?,?,?)',[inspection,business,job]);
    await db.customStatement('INSERT INTO local_pre_inspection_photos(id,business_id,inspection_id,attachment_id,local_file_path) VALUES (?,?,?,?,?)',
      [photo,business,inspection,attachment,file.path]);
    await db.customStatement('INSERT INTO local_finding_photos(id,business_id,finding_id,attachment_id,local_file_path) VALUES (?,?,?,?,?)',
      [other,business,finding,other,file.path]);
    final result=await LocalJobDeletionV3.applyVerifiedReceipt(db,receipt:receipt([...identities(),
      entity('pre_inspection',inspection),entity('pre_inspection_photo',photo),entity('attachment',attachment)]),
      mediaDirectoryProvider:() async=>support);
    expect(result.complete,isFalse);
    expect(await file.readAsString(),'shared');
    expect(await count(db,'local_finding_photos'),1);
  });

  test('scope expansion serialized with cleanup resets generation and erases every accepted ID', () async {
    Map<String,dynamic> group(List<Map<String,dynamic>> ids)=>{
      'scope_complete':true,'business_id':business,'job_id':job,'operation_id':operation,
      'deleted_entities':ids,'status':'deleted','storage_cleanup':'not_required','status_version':1};
    await Future.wait([
      LocalJobDeletionV3.applyVerifiedTombstone(db,group([entity('invoice',invoice)])),
      LocalJobDeletionV3.applyVerifiedTombstone(db,group(identities())),
    ]);
    expect(await count(db,'local_jobs'),0);
    expect(await count(db,'local_documents'),1);
    final row=await db.customSelect('SELECT state,inventory_generation FROM local_job_deletion_v3_cleanup').getSingle();
    expect(row.read<String>('state'),'complete');
    expect(row.read<int>('inventory_generation'),2);
  });


  test('reopen resumes newly expanded inventory even when prior group was complete', () async {
    final path=File('${support.path}/restart.sqlite');
    var persistent=BriskersLocalDatabase(NativeDatabase(path));
    await seed(persistent);
    Map<String,dynamic> group(List<Map<String,dynamic>> ids)=>{
      'scope_complete':true,'business_id':business,'job_id':job,'operation_id':operation,
      'deleted_entities':ids,'status':'deleted','storage_cleanup':'not_required','status_version':1};
    expect((await LocalJobDeletionV3.applyVerifiedTombstone(persistent,group([entity('invoice',invoice)]))).complete,isTrue);
    await persistent.customStatement("CREATE TRIGGER interrupt_cleanup BEFORE DELETE ON local_documents BEGIN SELECT RAISE(ABORT,'interrupt'); END");
    expect((await LocalJobDeletionV3.applyVerifiedTombstone(persistent,group(identities()))).complete,isFalse);
    await persistent.close();
    persistent=BriskersLocalDatabase(NativeDatabase(path));
    try {
      final pending=await persistent.customSelect('SELECT state,inventory_generation FROM local_job_deletion_v3_cleanup').getSingle();
      expect(pending.read<String>('state'),'cleanup_pending');
      expect(pending.read<int>('inventory_generation'),2);
      await persistent.customStatement('DROP TRIGGER interrupt_cleanup');
      await LocalJobDeletionV3.resumePendingCleanup(persistent,business);
      expect(await count(persistent,'local_jobs'),0);
      expect(await count(persistent,'local_documents'),1);
      expect((await persistent.customSelect('SELECT state FROM local_job_deletion_v3_cleanup').getSingle()).read<String>('state'),'complete');
    } finally { await persistent.close(); }
  });


  test('reused display numbers resolve only new UUIDs while retained old identities stay hidden', () async {
    const newJob='20000000-0000-4000-8000-000000000001';
    const newInvoice='20000000-0000-4000-8000-000000000002';
    const newEstimate='20000000-0000-4000-8000-000000000003';
    await db.customStatement("UPDATE local_jobs SET job_number='J-19',sync_state='pending' WHERE id=?",[job]);
    await db.customStatement("UPDATE local_documents SET document_number='6346',sync_state='pending' WHERE id=?",[invoice]);
    await db.customStatement("UPDATE local_documents SET document_number='EST-100',sync_state='pending' WHERE id=?",[estimate]);
    expect((await LocalJobDeletionV3.applyVerifiedReceipt(db,receipt:receipt())).complete,isFalse);
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) VALUES (?,?,'full','New Job','open','J-19')",[newJob,business]);
    await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,kind,document_number,status) VALUES (?,?,?,'invoice','6346','draft')",[newInvoice,business,newJob]);
    await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,kind,document_number,status) VALUES (?,?,?,'estimate','EST-100','draft')",[newEstimate,business,newJob]);
    expect((await LocalJobRepository(database:db).listJobs(business,search:'19')).map((r)=>r['id']),[newJob]);
    final documents=LocalDocumentRepository(database:db);
    expect((await documents.search(business,'6346')).map((r)=>r['id']),[newInvoice]);
    expect((await documents.search(business,'EST-100')).map((r)=>r['id']),[newEstimate]);
    await expectLater(db.customStatement("INSERT INTO local_documents(id,business_id,kind,document_number) VALUES (?,?,'invoice','6346') ON CONFLICT(id) DO UPDATE SET status='late old write'",[invoice,business]),throwsA(isA<Exception>()));
    expect((await db.customSelect("SELECT status FROM local_documents WHERE id='$newInvoice'").getSingle()).read<String>('status'),'draft');
  });


  test('preserved reassigned document can correct stale parent link without reviving deleted identity', () async {
    await db.customStatement('UPDATE local_documents SET job_id=? WHERE id=?',[job,other]);
    expect((await LocalJobDeletionV3.applyVerifiedReceipt(db,receipt:receipt())).complete,isFalse);
    await db.customStatement('UPDATE local_documents SET job_id=? WHERE id=?',[other,other]);
    expect(await LocalJobRetirement.isDocumentBlocked(db,business,other),isFalse);
    await LocalJobDeletionV3.resumePendingCleanup(db,business);
    expect((await db.customSelect('SELECT state FROM local_job_deletion_v3_cleanup').getSingle()).read<String>('state'),'complete');
    expect((await db.customSelect("SELECT job_id FROM local_documents WHERE id='$other'").getSingle()).read<String>('job_id'),other);
  });

  test('malformed acknowledgement and unknown legacy request copies prevent false completion', () async {
    await LocalJobRetirement.ensureSchema(db);
    await db.customStatement('CREATE TABLE local_job_recovery_receipts(id INTEGER PRIMARY KEY,business_id TEXT,outbox_id INTEGER,response_json TEXT)');
    await db.customStatement("INSERT INTO local_job_recovery_receipts VALUES (1,?,NULL,'malformed response')",[business]);
    await db.customStatement('INSERT INTO local_job_retirement_requests(business_id,job_id,operation_id,actor_id,snapshot_json,state,created_at,receipt_json) VALUES (?,?,?,?,?,?,0,?)',
      [business,other,other,other,'malformed snapshot','rejected','malformed old receipt']);
    final result=await LocalJobDeletionV3.applyVerifiedReceipt(db,receipt:receipt());
    expect(result.complete,isFalse);
    expect(result.issueCode,'reconciliation_pending');
    expect(await count(db,'local_job_recovery_receipts'),1);
    expect((await db.customSelect('SELECT snapshot_json FROM local_job_retirement_requests').getSingle()).read<String>('snapshot_json'),'malformed snapshot');
  });

  test('first staff scope hides legacy privileged caches until exact authorized refresh', () async {
    final detail = LocalDocumentDetailCache(database: db);
    await detail.save(business, invoice, {'id': invoice, 'kind': 'invoice', 'memo': 'old owner secret'});
    await LocalFinancialCache(database: db).saveTransactions(business, [{'id': transaction, 'amount': 125}]);
    expect(await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: other, visibilityScope: 'mechanic-scope', readerScope: 'staff'), isTrue);
    expect(await detail.load(business, invoice), isNull);
    expect(await LocalFinancialCache(database: db).loadTransactions(business), isEmpty);
    expect(await LocalDocumentRepository(database: db).listByKind(business, kind: 'invoice'), isEmpty);
    expect(await LocalJobDeletionV3.deletedIds(db, business), isEmpty);
    final generation = await LocalJobDeletionV3.captureVisibilityGeneration(db, business);
    await detail.save(business, invoice, {'id': invoice, 'kind': 'invoice', 'memo': 'authorized',
      '_local_visibility_generation': generation});
    expect((await detail.load(business, invoice))!['memo'], 'authorized');
    final stored = (await SharedPreferences.getInstance()).getString('briskers_document_detail_${business}_$invoice')!;
    expect(stored, isNot(contains('_local_visibility_generation')));
  });

  test('same business customer switch hides absent invoice and rejects known and unseen late results', () async {
    final detail = LocalDocumentDetailCache(database: db);
    await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: job, visibilityScope: 'owner-scope', readerScope: 'staff');
    final old = await LocalJobDeletionV3.captureVisibilityGeneration(db, business);
    await detail.save(business, invoice, {'id': invoice, 'kind': 'invoice', 'memo': 'owner secret'}, visibilityGeneration: old);
    await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: other, visibilityScope: 'customer-scope', readerScope: 'customer');
    expect(await detail.load(business, invoice), isNull);
    expect(await LocalJobRetirement.isDocumentBlocked(db, business, invoice), isTrue);
    await expectLater(detail.save(business, invoice, {'id': invoice, 'kind': 'invoice', 'memo': 'late'}, visibilityGeneration: old), throwsStateError);
    await expectLater(detail.save(business, 'unseen', {'id': 'unseen', 'kind': 'invoice', 'memo': 'late unseen'}, visibilityGeneration: old), throwsStateError);
    await detail.save(business, 'untagged', {'id': 'untagged', 'kind': 'invoice'});
    expect(await detail.load(business, invoice), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('briskers_document_detail_${business}_unseen'), isNull);
    expect(prefs.getString('briskers_document_detail_${business}_untagged'), isNull);
    await expectLater(LocalJobDeletionV3.assertVisibilityGeneration(db, business, old), throwsStateError);
    final fresh = await LocalJobDeletionV3.captureVisibilityGeneration(db, business);
    await detail.save(business, other, {'id': other, 'kind': 'invoice', 'memo': 'customer allowed'}, visibilityGeneration: fresh);
    expect((await detail.load(business, other))!['memo'], 'customer allowed');
    expect(await LocalJobDeletionV3.deletedIds(db, business), isEmpty);
  });

  test('scope change preserves dirty snapshots and outbox inaccessible for reconciliation', () async {
    final detail = LocalDocumentDetailCache(database: db);
    await detail.save(business, invoice, {'id': invoice, 'kind': 'invoice', '_local_pending': true, 'memo': 'sole local edit'});
    final outboxId = await enqueue(db, 'invoice_update', invoice, {'document_id': invoice, 'memo': 'sole queued edit'});
    await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: other, visibilityScope: 'customer', readerScope: 'customer');
    expect(await detail.load(business, invoice), isNull);
    final generation = await LocalJobDeletionV3.captureVisibilityGeneration(db, business);
    await expectLater(detail.save(business, invoice, {'id': invoice, 'kind': 'invoice', 'memo': 'server replacement'}, visibilityGeneration: generation), throwsStateError);
    expect((await SharedPreferences.getInstance()).getString('briskers_document_detail_${business}_$invoice'), contains('sole local edit'));
    expect(await count(db, 'sync_outbox'), 1);
    expect(await LocalJobDeletionV3.visibilityScopeState(db, business), 'authorized_reconciliation_required');
    await expectLater(LocalJobDeletionV3.assertReplayAllowed(db, business, outboxId: outboxId), throwsStateError);
    expect(await LocalJobDeletionV3.isEntityDeleted(db, business, 'invoice', invoice), isFalse);
  });

  test('actor and known role changes deny reads immediately before new feed', () async {
    var actor = job;
    await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: actor, visibilityScope: 'owner', readerScope: 'staff');
    LocalJobDeletionV3.currentActorIdProvider = () => actor;
    final detail = LocalDocumentDetailCache(database: db);
    final generation = await LocalJobDeletionV3.captureVisibilityGeneration(db, business);
    await detail.save(business, invoice, {'id': invoice, 'kind': 'invoice'}, visibilityGeneration: generation);
    actor = other;
    await expectLater(detail.load(business, invoice), throwsStateError);
    await expectLater(LocalJobRepository(database: db).listJobs(business), throwsStateError);
    actor = job;
    await LocalJobDeletionV3.lockKnownRoleChange(db, business);
    await expectLater(detail.load(business, invoice), throwsStateError);
    await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: actor, visibilityScope: 'owner', readerScope: 'staff');
    expect(await detail.load(business, invoice), isNull);
  });

  test('fresh financial scope results rehydrate while stale and mixed generations do not', () async {
    final cache = LocalFinancialCache(database: db);
    await cache.saveTransactions(business, [{'id': transaction, 'amount': 20}]);
    await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: other, visibilityScope: 'staff', readerScope: 'staff');
    final generation = await LocalJobDeletionV3.captureVisibilityGeneration(db, business);
    await cache.saveTransactions(business, [{'id': transaction, 'amount': 50, '_local_visibility_generation': generation}]);
    expect((await cache.loadTransactions(business)).single['amount'], 50);
    await cache.saveTransactions(business, [{'id': other, 'amount': 900, '_local_visibility_generation': generation - 1}]);
    expect((await cache.loadTransactions(business)).single['amount'], 50);
    final raw = (await db.customSelect("SELECT payload_json FROM local_financial_cache WHERE cache_key='transactions_snapshot'").getSingle()).read<String>('payload_json');
    expect(raw, isNot(contains('_local_visibility_generation')));
  });
  test('failed preference write cannot grant current scope to old private snapshot', () async {
    final cache = LocalDocumentDetailCache(database: db);
    await cache.save(business, invoice, {'id': invoice, 'kind': 'invoice', 'memo': 'old private body'});
    await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: other, visibilityScope: 'customer', readerScope: 'customer');
    final generation = await LocalJobDeletionV3.captureVisibilityGeneration(db, business);
    final failing = LocalDocumentDetailCache(database: db, preferenceWriter: (_, _, _) async => false);
    await expectLater(failing.save(business, invoice, {'id': invoice, 'kind': 'invoice', 'memo': 'new permitted body'},
      visibilityGeneration: generation), throwsStateError);
    expect(await cache.load(business, invoice), isNull);
    expect((await SharedPreferences.getInstance()).getString('briskers_document_detail_${business}_$invoice'), contains('old private body'));
  });
  test('server receipt preserves scope-dirty baseline and snapshots for pending reconciliation', () async {
    final cache = LocalDocumentDetailCache(database: db);
    await cache.save(business, invoice, {'id': invoice, 'kind': 'invoice', 'memo': 'baseline needed by queued edit'});
    await enqueue(db, 'invoice_update', invoice, {'document_id': invoice, 'memo': 'unconfirmed delta'});
    await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: other, visibilityScope: 'customer', readerScope: 'customer');
    final result = await LocalJobDeletionV3.applyVerifiedReceipt(db, receipt: receipt());
    expect(result.complete, isFalse);
    expect((await SharedPreferences.getInstance()).getString('briskers_document_detail_${business}_$invoice'), contains('baseline needed'));
    expect(await count(db, 'sync_outbox'), 1);
    expect(await cache.load(business, invoice), isNull);
  });
  test('structurally invalid scope snapshots remain inaccessible and cannot be overwritten', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('briskers_document_detail_${business}_$invoice', jsonEncode(['unknown document work']));
    await db.customStatement("INSERT INTO local_financial_cache(business_id,cache_key,payload_json,updated_at) VALUES (?,'transactions_snapshot',?,0)",
      [business, jsonEncode('unknown financial work')]);
    await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: other, visibilityScope: 'restricted', readerScope: 'customer');
    final generation = await LocalJobDeletionV3.captureVisibilityGeneration(db, business);
    final cache = LocalDocumentDetailCache(database: db);
    expect(await cache.load(business, invoice), isNull);
    await expectLater(cache.save(business, invoice, {'id': invoice, 'kind': 'invoice'},
      visibilityGeneration: generation), throwsStateError);
    final financial = LocalFinancialCache(database: db);
    expect(await financial.loadTransactions(business), isEmpty);
    await expectLater(financial.saveTransactions(business, [{'id': transaction}],
      visibilityGeneration: generation), throwsStateError);
    expect(prefs.getString('briskers_document_detail_${business}_$invoice'), contains('unknown document work'));
    expect((await db.customSelect("SELECT payload_json FROM local_financial_cache").getSingle()).read<String>('payload_json'), contains('unknown financial work'));
  });
  test('generic replace-child sync cannot discard scope-dirty synced-looking child', () async {
    await db.customStatement('INSERT INTO local_job_visits(id,business_id,job_id,visit_number) VALUES (?,?,?,1)', [other, business, job]);
    await enqueue(db, 'job_visit_update', other, {'visit_id': other, 'notes': 'unconfirmed child edit'});
    await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: other, visibilityScope: 'changed-role', readerScope: 'staff');
    final generation = await LocalJobDeletionV3.captureVisibilityGeneration(db, business);
    await expectLater(db.transaction(() async {
      await LocalJobDeletionV3.authorizeScopedEntities(db, business, generation, [entity('job', job)]);
      await db.customStatement('DELETE FROM local_job_visits WHERE business_id=? AND job_id=?', [business, job]);
    }), throwsA(isA<Exception>()));
    expect(await count(db, 'local_job_visits'), 1);
    expect(await count(db, 'sync_outbox'), 1);
    expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
    // Replaceable clean scope rows still permit ordinary cache invalidation.
    await db.customStatement('DELETE FROM local_documents WHERE business_id=? AND id=?', [business, estimate]);
  });
  test('owned v3 trigger upgrade replaces draft guards without touching unrelated triggers', () async {
    await LocalJobDeletionV3.ensureSchema(db);
    await db.customStatement('DROP TRIGGER deletion_v3_local_documents_update');
    await db.customStatement("CREATE TRIGGER deletion_v3_local_documents_update BEFORE UPDATE ON local_documents BEGIN SELECT RAISE(ABORT,'obsolete draft guard'); END");
    await db.customStatement("CREATE TRIGGER unrelated_guard BEFORE DELETE ON local_customers BEGIN SELECT RAISE(ABORT,'unrelated protection'); END");
    await db.customStatement('UPDATE local_job_deletion_v3_schema SET version=2 WHERE singleton=1');
    await LocalJobDeletionV3.ensureSchema(db);
    await db.customStatement("UPDATE local_documents SET status='allowed replacement' WHERE id=?", [other]);
    await expectLater(db.customStatement('DELETE FROM local_customers WHERE business_id=?', [business]), throwsA(isA<Exception>()));
    expect((await db.customSelect('SELECT version FROM local_job_deletion_v3_schema').getSingle()).read<int>('version'), 4);
  });
  test('scope-dirty financial key rejects direct replace and update without identity fields', () async {
    await db.customStatement("INSERT INTO local_financial_cache(business_id,cache_key,payload_json,updated_at) VALUES (?,'unknown',?,0)", [business, jsonEncode('only unknown work')]);
    await LocalJobDeletionV3.invalidateVisibilityScope(db, businessId: business,
      actorId: other, visibilityScope: 'restricted', readerScope: 'customer');
    await expectLater(db.customStatement("INSERT OR REPLACE INTO local_financial_cache(business_id,cache_key,payload_json,updated_at) VALUES (?,'unknown','{}',0)", [business]), throwsA(isA<Exception>()));
    await expectLater(db.customStatement("UPDATE local_financial_cache SET cache_key='new-key',payload_json='{}' WHERE business_id=?", [business]), throwsA(isA<Exception>()));
    expect((await db.customSelect('SELECT payload_json FROM local_financial_cache').getSingle()).read<String>('payload_json'), contains('only unknown work'));
  });
}
