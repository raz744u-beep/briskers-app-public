import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_deletion_v3.dart';
import 'package:briskers_app/services/local_job_graph_delete.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const business = '10000000-0000-4000-8000-000000000001';
const job = '10000000-0000-4000-8000-000000000002';
const invoice = '10000000-0000-4000-8000-000000000003';
const otherJob = '10000000-0000-4000-8000-000000000004';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late LocalJobGraphDelete deletion;

  setUp(() async {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    deletion = LocalJobGraphDelete(db);
    await db.customStatement(
      "INSERT INTO local_jobs (id,business_id,access_scope,title,status,sync_state) "
      "VALUES (?,?,'full','Synced repair','open','synced')",
      [job, business],
    );
    await db.customStatement(
      "INSERT INTO local_jobs (id,business_id,access_scope,title,status,sync_state) "
      "VALUES (?,?,'full','Unrelated repair','open','synced')",
      [otherJob, business],
    );
    await db.customStatement(
      "INSERT INTO local_documents (id,business_id,job_id,kind,document_number,sync_state) "
      "VALUES (?,?,?,'invoice','6345','synced')",
      [invoice, business, job],
    );
  });
  tearDown(() async => db.close());

  Future<int> count(String table) async =>
    (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
      .read<int>('n');

  test('previously synced job deletes offline and records durable markers', () async {
    final review = await deletion.preview(businessId: business, jobId: job);
    expect(review.map((e) => e['kind']), containsAll(['job', 'invoice']));
    await deletion.confirm(businessId: business, jobId: job, reviewed: review);
    expect(await count('local_jobs'), 1);
    expect(await count('local_documents'), 0);
    expect(await LocalJobDeletionV3.blockedJobIds(db, business), contains(job));
    expect(await LocalJobDeletionV3.blockedDocumentIds(db, business), contains(invoice));
    expect(await count('sync_outbox'), 0);
  });

  test('reviewed inventory change rolls back without deleting anything', () async {
    final review = await deletion.preview(businessId: business, jobId: job);
    await db.customStatement(
      "INSERT INTO local_job_visits (id,business_id,job_id,visit_number,sync_state) "
      "VALUES ('visit-new',?,?,1,'synced')",
      [business, job],
    );
    await expectLater(deletion.confirm(
      businessId: business, jobId: job, reviewed: review), throwsStateError);
    expect(await count('local_jobs'), 2);
    expect(await count('local_documents'), 1);
    expect(await count('local_offline_job_purge_entities'), 0);
  });

  test('rejects linked queued edits without erasing any rows', () async {
    await db.customStatement(
      "INSERT INTO sync_outbox (business_id,entity_type,entity_id,operation,payload_json) "
      "VALUES (?,'work_summary',?,'update',?)",
      [business, job, '{"job_id":"$job"}'],
    );
    await expectLater(
      deletion.preview(businessId: business, jobId: job),
      throwsStateError,
    );
    expect(await count('local_jobs'), 2);
    expect(await count('local_documents'), 1);
  });
}
