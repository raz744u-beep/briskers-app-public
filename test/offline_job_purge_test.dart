import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_deletion_v3.dart';
import 'package:briskers_app/services/offline_job_purge.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const business = '10000000-0000-4000-8000-000000000001';
const job = '10000000-0000-4000-8000-000000000002';
const actor = '10000000-0000-4000-8000-000000000003';
const operation = '10000000-0000-4000-8000-000000000004';
const quick = '10000000-0000-4000-8000-000000000005';
const other = '10000000-0000-4000-8000-000000000006';

Future<int> enqueue(BriskersLocalDatabase db, String type, String id,
    Map<String, dynamic> payload, {String action = 'create'}) async {
  await db.customStatement('INSERT INTO sync_outbox '
      '(business_id,entity_type,entity_id,operation,payload_json) VALUES (?,?,?,?,?)',
      [business, type, id, action, jsonEncode(payload)]);
  return (await db.customSelect('SELECT MAX(id) AS id FROM sync_outbox').getSingle()).read<int>('id');
}
Future<int> seed(BriskersLocalDatabase db, {bool authored = true}) async {
  if (authored) await OfflineJobPurge.recordNewIntent(db, business, [job, 'job-create-$job']);
  await db.customStatement("INSERT INTO local_jobs (id,business_id,access_scope,title,status,sync_state) VALUES (?,?,'full','Never uploaded','open','pending')", [job, business]);
  return enqueue(db, 'job_create', job, {'job_id': job, 'operation_id': 'job-create-$job', 'title': 'Never uploaded'});
}
Future<OfflineJobPurgePreview> preview(BriskersLocalDatabase db, {String id = job, bool owner = true}) => OfflineJobPurge.preview(db,
    businessId: business, jobId: id, actorId: actor, isOwner: owner);
Future<int> count(BriskersLocalDatabase db, String table) async =>
    (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle()).read<int>('n');
Future<String> seedStandaloneConversion(BriskersLocalDatabase db) async {
  const root = 'local-conversion-job-$quick';
  const invoice = 'local-invoice-$quick';
  const source = 'local-estimate-$other';
  await OfflineJobPurge.recordNewIntent(db,business,[root,invoice,source,quick,other]);
  await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status,sync_state) VALUES (?,?,'full','Converted repair','open','pending')",[root,business]);
  await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,kind,row_version,sync_state) VALUES (?,?,NULL,'estimate',1,'pending')",[source,business]);
  await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,kind,row_version,sync_state) VALUES (?,?,?,'invoice',1,'pending')",[invoice,business,root]);
  await enqueue(db,'document_draft_create',source,{'local_id':source,'kind':'estimate','operation_id':other},action:'create_estimate');
  await enqueue(db,'document_draft_create',invoice,{'local_id':invoice,'kind':'convert_invoice','estimate_id':source,'operation_id':quick,'provisional_job_id':root},action:'convert_estimate');
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('briskers_document_detail_${business}_$source',jsonEncode({'id':source,'kind':'estimate','job_id':null,'converted':true,'converted_invoice_id':invoice,'sync_state':'pending'}));
  return root;
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalJobDeletionV3.currentActorIdProvider = null;
    db = BriskersLocalDatabase(NativeDatabase.memory());
    await LocalJobDeletionV3.ensureSchema(db);
    await OfflineJobPurge.ensureSchema(db);
  });
  tearDown(() async { await db.close(); LocalJobDeletionV3.currentActorIdProvider = null; });

  test('never-dispatched original root cancels atomically and leaves minimal registration', () async {
    final queueId = await seed(db);
    final review = await preview(db);
    final result = await OfflineJobPurge.confirm(db, review,
        operationId: operation, actorId: actor, isOwner: true);
    expect(result.completed, isTrue);
    expect(await count(db, 'local_jobs'), 0);
    expect(await count(db, 'sync_outbox'), 0);
    expect(await LocalJobDeletionV3.blockedJobIds(db, business), contains(job));
    final pending = await OfflineJobPurge.pendingRegistrations(db, business, actor);
    expect(pending.single['confirmation']['root_origin'], 'job_create');
    // A lost registration ACK changes nothing locally: exact same operation
    // and minimal confirmation must be retried, never a fresh delete intent.
    expect(await OfflineJobPurge.pendingRegistrations(db,business,actor), pending);
    expect(jsonEncode(pending), isNot(contains('Never uploaded')));
    await expectLater(OfflineJobPurge.recordDispatch(db, business, outboxId: queueId), throwsA(anything));
    await expectLater(db.customStatement("INSERT INTO local_jobs (id,business_id,access_scope,title,status) VALUES (?,?,'full','Resurrection','open')", [job, business]), throwsA(anything));
  });

  test('legacy root with zero attempts is unknown, not positive provenance', () async {
    await seed(db, authored: false);
    await expectLater(preview(db), throwsA(isA<OfflineJobPurgeNeedsReconciliation>()));
    expect(await count(db, 'local_jobs'), 1);
  });

  test('pre-dispatch claim and lost ACK block cancellation even after retry resets', () async {
    final id = await seed(db);
    await OfflineJobPurge.recordDispatch(db, business, outboxId: id);
    await db.customStatement("UPDATE sync_outbox SET state='pending',attempt_count=0,last_attempt_at=NULL WHERE id=?", [id]);
    await expectLater(preview(db), throwsA(isA<OfflineJobPurgeNeedsReconciliation>()));
    expect(await count(db, 'local_jobs'), 1);
  });

  test('restore under a new queue ID cannot erase old dispatch evidence', () async {
    final id = await seed(db);
    await OfflineJobPurge.recordDispatch(db, business, outboxId: id);
    await db.customStatement('DELETE FROM sync_outbox WHERE id=?', [id]);
    await enqueue(db, 'job_create', job, {'job_id': job, 'operation_id': 'job-create-$job'});
    await expectLater(preview(db), throwsA(isA<OfflineJobPurgeNeedsReconciliation>()));
  });

  test('attempt evidence is monotonic even if legacy retry resets counters', () async {
    final id = await seed(db);
    await db.customStatement('UPDATE sync_outbox SET attempt_count=1 WHERE id=?', [id]);
    await db.customStatement('UPDATE sync_outbox SET attempt_count=0,last_attempt_at=NULL WHERE id=?', [id]);
    await expectLater(preview(db), throwsA(isA<OfflineJobPurgeNeedsReconciliation>()));
    await expectLater(db.customStatement('UPDATE local_offline_dispatch_proof SET dispatched=0'), throwsA(anything));
    await expectLater(db.customStatement('INSERT OR REPLACE INTO local_offline_dispatch_proof VALUES (?,?,0)', [business,id]), throwsA(anything));
  });

  test('send racing after consent invalidates cancellation before any erase', () async {
    final id = await seed(db);
    final review = await preview(db);
    await OfflineJobPurge.recordDispatch(db, business, outboxId: id);
    await expectLater(OfflineJobPurge.confirm(db, review,
        operationId: operation, actorId: actor, isOwner: true), throwsA(anything));
    expect(await count(db, 'local_jobs'), 1);
    expect(await count(db, 'local_offline_job_purge_requests'), 0);
  });

  test('graph edit after review requires a new itemized confirmation', () async {
    await seed(db);
    final review = await preview(db);
    await db.customStatement("UPDATE local_jobs SET title='Changed' WHERE id=?", [job]);
    await expectLater(OfflineJobPurge.confirm(db, review,
        operationId: operation, actorId: actor, isOwner: true), throwsStateError);
    expect(await count(db, 'sync_outbox'), 1);
    expect(() => review.items.single['label'] = 'Hide edit', throwsUnsupportedError);
    expect(() => review.counts['job'] = 0, throwsUnsupportedError);
  });

  test('Owner authorization is enforced at both entry points', () async {
    await seed(db);
    await expectLater(preview(db, owner: false), throwsStateError);
    final review = await preview(db);
    await expectLater(OfflineJobPurge.confirm(db, review,
        operationId: operation, actorId: actor, isOwner: false), throwsStateError);
    expect(await count(db, 'local_jobs'), 1);
  });

  test('nested cross-job financial allocation blocks the entire cancellation', () async {
    await seed(db);
    await OfflineJobPurge.recordNewIntent(db, business, ['local-transaction-x','financial-create-x']);
    await enqueue(db, 'financial_create', 'local-transaction-x', {
      'operation_id': 'financial-create-x', 'job_id': job, 'amount': 20,
      'allocations': [{'job_id': other, 'amount': 10}],
    });
    await expectLater(preview(db), throwsA(isA<OfflineJobPurgeNeedsReconciliation>()));
    expect(await count(db, 'sync_outbox'), 2);
  });

  test('a pending related row without original creation proof is retained', () async {
    await seed(db);
    await db.customStatement("INSERT INTO local_pre_inspections (id,business_id,job_id,sync_state) VALUES ('legacy-inspection',?,?,'pending')", [business, job]);
    await expectLater(preview(db), throwsA(isA<OfflineJobPurgeNeedsReconciliation>()));
    expect(await count(db, 'local_pre_inspections'), 1);
  });

  test('quick invoice local aliases register only canonical UUID and operation key', () async {
    const localJob = 'local-job-$quick';
    const invoice = 'local-invoice-$quick';
    const visit = 'local-visit-$quick';
    await OfflineJobPurge.recordNewIntent(db, business, [localJob, invoice, visit, quick]);
    await db.customStatement("INSERT INTO local_jobs (id,business_id,access_scope,title,status,sync_state) VALUES (?,?,'full','Invoice','open','pending')", [localJob,business]);
    await db.customStatement("INSERT INTO local_documents (id,business_id,job_id,kind,row_version,sync_state) VALUES (?,?,?,'invoice',1,'pending')", [invoice,business,localJob]);
    await db.customStatement("INSERT INTO local_job_visits (id,business_id,job_id,visit_number,sync_state) VALUES (?,?,?,1,'pending')", [visit,business,localJob]);
    await enqueue(db, 'document_draft_create', invoice, {'operation_id': quick, 'provisional_job_id': localJob, 'local_id': invoice}, action:'create_quick_invoice');
    final review = await preview(db, id: localJob);
    await OfflineJobPurge.confirm(db, review, operationId: operation, actorId: actor, isOwner: true);
    final pending = (await OfflineJobPurge.pendingRegistrations(db, business, actor)).single;
    expect(pending['job_id'], quick);
    expect(pending['local_job_id'], localJob);
    final wire = pending['confirmation'] as Map;
    expect(wire['root_origin'], 'quick_invoice');
    expect(jsonEncode(wire), isNot(contains('local-job-')));
    expect(jsonEncode(wire), contains('quick_invoice/$quick'));
    expect((wire['deleted_entities'] as List).length, 2);
  });
  test('uncorrelated earlier write does not poison future newly authored Jobs', () async {
    await OfflineJobPurge.recordDispatch(db, business);
    await seed(db);
    expect((await preview(db)).jobId, job);
    await OfflineJobPurge.recordDispatch(db, business);
    await expectLater(preview(db), throwsA(isA<OfflineJobPurgeNeedsReconciliation>()));
  });

  test('unknown selected financial cache blocks erasure', () async {
    await seed(db);
    await db.customStatement('INSERT INTO local_financial_cache (business_id,cache_key,payload_json) VALUES (?,?,?)',
        [business, 'transaction_detail_unknown', '{broken']);
    await expectLater(preview(db), throwsA(isA<OfflineJobPurgeNeedsReconciliation>()));
    expect(await count(db, 'local_jobs'), 1);
  });

  test('actor switch while confirmation is executing rolls back all changes', () async {
    await seed(db);
    final review = await preview(db);
    // These checks run within confirmation before and after discovery and at
    // commit. Switch only on the final boundary, after marker/data mutations.
    var checks = 0;
    LocalJobDeletionV3.currentActorIdProvider = () => ++checks < 7 ? actor : other;
    await db.customStatement("INSERT INTO local_job_deletion_v3_scope (business_id,actor_id,visibility_scope,reader_scope,generation,state) VALUES (?,?,'owner','all',0,'active')", [business,actor]);
    await expectLater(OfflineJobPurge.confirm(db, review,
        operationId: operation, actorId: actor, isOwner: true), throwsStateError);
    expect(await count(db, 'local_jobs'), 1);
    expect(await count(db, 'local_offline_job_purge_requests'), 0);
  });

  test('exact pending payment amount and method are included in immutable consent', () async {
    await seed(db);
    const estimate = 'local-estimate-new';
    const invoice = 'local-invoice-new';
    await OfflineJobPurge.recordNewIntent(db, business, [estimate, invoice, quick, other]);
    for (final pair in [[estimate,'estimate'],[invoice,'invoice']]) {
      await db.customStatement("INSERT INTO local_documents (id,business_id,job_id,kind,row_version,sync_state) VALUES (?,?,?,?,1,'pending')", [pair[0], business, job, pair[1]]);
    }
    await enqueue(db, 'document_draft_create', estimate, {'local_id': estimate, 'job_id': job}, action:'create_estimate');
    await enqueue(db, 'document_draft_create', invoice, {'local_id': invoice, 'estimate_id': estimate, 'operation_id': quick}, action:'convert_estimate');
    await enqueue(db, 'invoice_payment_received', invoice, {'invoice_id': invoice, 'operation_id': other, 'amount_cents':12345, 'method_name':'Cash', 'method_id':'cash'}, action:'record_received_payment');
    final review = await preview(db);
    final payment = review.items.singleWhere((i) => i['kind']=='payment');
    expect(payment['amount_cents'], 12345);
    expect(payment['method_name'], 'Cash');
    await OfflineJobPurge.confirm(db, review, operationId: operation, actorId: actor, isOwner: true);
    expect(await count(db, 'local_documents'), 0);
    expect(await count(db, 'sync_outbox'), 0);
    expect(jsonEncode((await OfflineJobPurge.pendingRegistrations(db,business,actor)).single['confirmation']), isNot(contains('12345')));
  });

  test('malformed network payload cannot dispatch or poison future fresh roots', () async {
    final id = await enqueue(db,'unknown','old',{});
    await db.customStatement("UPDATE sync_outbox SET payload_json='{broken' WHERE id=?",[id]);
    await expectLater(OfflineJobPurge.recordDispatch(db,business,outboxId:id), throwsA(anything));
    expect(await count(db,'local_offline_dispatch_ids'),0);
    await db.customStatement('DELETE FROM sync_outbox WHERE id=?',[id]);
    await seed(db);
    expect((await preview(db)).jobId,job);
  });

  test('wholly local standalone conversion includes source ID and true replay key', () async {
    final root = await seedStandaloneConversion(db);
    final review = await preview(db,id:root);
    expect(review.items.where((r)=>r['document_kind']=='estimate').length,1);
    await OfflineJobPurge.confirm(db,review,operationId:operation,actorId:actor,isOwner:true);
    expect(await count(db,'local_jobs'),0);
    expect(await count(db,'local_documents'),0);
    final wire = (await OfflineJobPurge.pendingRegistrations(db,business,actor)).single['confirmation'] as Map;
    expect(wire['root_origin'],'standalone_estimate_conversion');
    expect(wire['job_id'],quick);
    expect(wire['deleted_entities'],contains(equals({'entity_kind':'estimate','entity_id':other})));
    expect(wire['deleted_entities'],contains(equals({'entity_kind':'operation','entity_id':'standalone_estimate/$other'})));
    expect(jsonEncode(wire),isNot(contains('local-conversion-job')));
  });

  test('another conversion consuming the standalone source blocks all erasure', () async {
    final root = await seedStandaloneConversion(db);
    await enqueue(db,'document_draft_create','another-invoice',{'estimate_id':'local-estimate-$other','kind':'convert_invoice','operation_id':operation},action:'convert_estimate');
    await expectLater(preview(db,id:root),throwsA(isA<OfflineJobPurgeNeedsReconciliation>()));
    expect(await count(db,'local_documents'),2);
    expect(await count(db,'sync_outbox'),3);
  });

  test('shared account lookup is not dispatch evidence for a different new Job', () async {
    final old = await enqueue(db,'financial_create','old-transaction',{
      'operation_id':'old-operation','job_id':'old-job','account_id':'shared-account','category_id':'shared-category'});
    await OfflineJobPurge.recordDispatch(db,business,outboxId:old);
    await db.customStatement('DELETE FROM sync_outbox WHERE id=?',[old]);
    await seed(db);
    await OfflineJobPurge.recordNewIntent(db,business,['new-transaction','new-operation']);
    await enqueue(db,'financial_create','new-transaction',{'operation_id':'new-operation','job_id':job,
      'account_id':'shared-account','category_id':'shared-category','amount':25});
    expect((await preview(db)).jobId,job);
  });

}
