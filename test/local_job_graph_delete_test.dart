import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_deletion_v3.dart';
import 'package:briskers_app/services/local_job_graph_delete.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _syntheticOwnerDeleteBuild = bool.fromEnvironment(
  'BRISKERS_SYNTHETIC_BUILD', defaultValue: false);

const business = '10000000-0000-4000-8000-000000000001';
const job = '10000000-0000-4000-8000-000000000002';
const invoice = '10000000-0000-4000-8000-000000000003';
const otherJob = '10000000-0000-4000-8000-000000000004';
const actor = '10000000-0000-4000-8000-000000000005';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late LocalJobGraphDelete deletion;

  setUp(() async {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    deletion = LocalJobGraphDelete(db,
      ownerIdentityProvider: () => {
        'actor_id': actor, 'business_id': business, 'role_code': 'owner',
      });
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

  test('production default must reject an Owner without verified enrollment', () async {
    final unauthenticated = LocalJobGraphDelete(db);
    await expectLater(
      unauthenticated.preview(businessId: business, jobId: job, actorId: actor),
      throwsStateError,
    );
    expect(await count('local_jobs'), 2);
    expect(await count('local_documents'), 1);
  });

  test('genuine queued payment cannot be silently discarded', () async {
    await db.customStatement(
      "INSERT INTO sync_outbox "
      "(business_id,entity_type,entity_id,operation,payload_json) "
      "VALUES (?,'invoice_payment_received',?,'record_received_payment',?)",
      [business, invoice,
        '{"invoice_id":"$invoice","amount_cents":20000,"method_name":"Cash"}'],
    );
    await expectLater(
      deletion.preview(businessId: business, jobId: job, actorId: actor),
      throwsStateError,
    );
    expect(await count('sync_outbox'), 1);
    expect(await count('local_jobs'), 2);
    expect(await count('local_documents'), 1);
  }, skip: _syntheticOwnerDeleteBuild);

  test('previously synced job deletes offline and records durable markers', () async {
    final review = await deletion.preview(businessId: business, jobId: job, actorId: actor);
    expect(review.map((e) => e['kind']), containsAll(['job', 'invoice']));
    await deletion.confirm(businessId: business, jobId: job, actorId: actor, reviewed: review);
    expect(await count('local_jobs'), 1);
    expect(await count('local_documents'), 0);
    expect(await LocalJobDeletionV3.blockedJobIds(db, business), contains(job));
    expect(await LocalJobDeletionV3.blockedDocumentIds(db, business), contains(invoice));
    expect(await count('sync_outbox'), 0);
  });

  test('deleted local identifiers remain fenced after app database restart', () async {
    final directory = await Directory.systemTemp.createTemp('briskers-purge-');
    final file = File('${directory.path}/briskers.sqlite');
    BriskersLocalDatabase? first;
    BriskersLocalDatabase? reopened;
    try {
      first = BriskersLocalDatabase(NativeDatabase(file));
      await first.customStatement(
        "INSERT INTO local_jobs (id,business_id,access_scope,title,status,sync_state) "
        "VALUES (?,?,'full','Restart sample','open','synced')",
        [job, business],
      );
      await first.customStatement(
        "INSERT INTO local_documents (id,business_id,job_id,kind,document_number,sync_state) "
        "VALUES (?,?,?,'invoice','TEST-8001','synced')",
        [invoice, business, job],
      );
      final engine = LocalJobGraphDelete(first, ownerIdentityProvider: () => {
        'actor_id': actor, 'business_id': business, 'role_code': 'owner',
      });
      final reviewed = await engine.preview(
        businessId: business, jobId: job, actorId: actor,
      );
      await engine.confirm(
        businessId: business, jobId: job,
        actorId: actor, reviewed: reviewed,
      );
      await first.close();
      first = null;

      reopened = BriskersLocalDatabase(NativeDatabase(file));
      expect(await LocalJobDeletionV3.blockedJobIds(reopened, business),
          contains(job));
      expect(await LocalJobDeletionV3.blockedDocumentIds(reopened, business),
          contains(invoice));
      final rows = await reopened.customSelect(
          'SELECT COUNT(*) AS n FROM local_jobs WHERE business_id=? AND id=?',
          variables: [Variable<String>(business), Variable<String>(job)]).getSingle();
      expect(rows.read<int>('n'), 0);
    } finally {
      if (first != null) await first.close();
      if (reopened != null) await reopened.close();
      await directory.delete(recursive: true);
    }
  });

  test('repeat delete cannot silently reassign a removed job identity', () async {
    final reviewed = await deletion.preview(
      businessId: business, jobId: job, actorId: actor);
    await deletion.confirm(
      businessId: business, jobId: job, actorId: actor, reviewed: reviewed);
    await expectLater(deletion.confirm(
      businessId: business, jobId: job, actorId: actor, reviewed: reviewed),
      throwsStateError);
    expect(await LocalJobDeletionV3.blockedJobIds(db, business), contains(job));
    expect(await count('local_jobs'), 1);
  });

  test('reviewed inventory change rolls back without deleting anything', () async {
    final review = await deletion.preview(businessId: business, jobId: job, actorId: actor);
    await db.customStatement(
      "INSERT INTO local_job_visits (id,business_id,job_id,visit_number,sync_state) "
      "VALUES ('visit-new',?,?,1,'synced')",
      [business, job],
    );
    await expectLater(deletion.confirm(
      businessId: business, jobId: job, actorId: actor, reviewed: review), throwsStateError);
    expect(await count('local_jobs'), 2);
    expect(await count('local_documents'), 1);
    expect(await count('local_offline_job_purge_entities'), 0);
  });

  test('Owner identity change before commit rolls back rows and markers', () async {
    final reviewed = await deletion.preview(
      businessId: business, jobId: job, actorId: actor);
    var checks = 0;
    final switchingOwner = LocalJobGraphDelete(db, ownerIdentityProvider: () {
      checks++;
      return checks < 4
          ? {'actor_id': actor, 'business_id': business, 'role_code': 'owner'}
          : null;
    });
    await expectLater(
      switchingOwner.confirm(businessId: business, jobId: job,
          actorId: actor, reviewed: reviewed),
      throwsStateError,
    );
    expect(await count('local_jobs'), 2);
    expect(await count('local_documents'), 1);
    expect(await count('local_offline_job_purge_entities'), 0);
  });

  test('different business Owner cannot preview a synced job', () async {
    final wrongOwner = LocalJobGraphDelete(db,
      ownerIdentityProvider: () => {
        'actor_id': actor,
        'business_id': otherJob,
        'role_code': 'owner',
      });
    await expectLater(wrongOwner.preview(
      businessId: business, jobId: job, actorId: actor), throwsStateError);
    expect(await count('local_jobs'), 2);
  });

  test('TEST-only simulated payment and audit delete atomically', () async {
    await db.customStatement(
      "INSERT INTO sync_outbox "
      "(business_id,entity_type,entity_id,operation,payload_json) "
      "VALUES (?,'invoice_payment_received',?,'record_received_payment',?)",
      [business, invoice,
        '{"synthetic_test_only":true,"invoice_id":"$invoice",'
        '"operation_id":"10000000-0000-4000-8000-000000000088",'
        '"amount_cents":20000,"method_name":"TEST cash"}'],
    );
    await db.customStatement(
      'INSERT INTO local_financial_cache '
      '(business_id,cache_key,payload_json) VALUES (?,?,?)',
      [business, 'synthetic_payment_audit:$job',
        '{"synthetic_test_only":true,"job_id":"$job",'
        '"invoice_id":"$invoice","action":"fake edit"}'],
    );
    final reviewed = await deletion.preview(
      businessId: business, jobId: job, actorId: actor);
    expect(reviewed.map((r) => r['kind']),
      containsAll(['job', 'invoice', 'payment', 'payment_edit_audit']));
    await deletion.confirm(
      businessId: business, jobId: job, actorId: actor, reviewed: reviewed);
    expect(await count('sync_outbox'), 0);
    expect(await count('local_financial_cache'), 0);
    expect(await count('local_documents'), 0);
    expect(await count('local_jobs'), 1);
  }, skip: !_syntheticOwnerDeleteBuild);

  test('linked financial payment cache blocks partial deletion', () async {
    await db.customStatement(
      'INSERT INTO local_financial_cache '
      '(business_id,cache_key,payload_json) VALUES (?,?,?)',
      [business, 'payments:invoice', '{"invoice_id":"$invoice","payments":[{"amount":3000}]}'],
    );
    await expectLater(
      deletion.preview(businessId: business, jobId: job, actorId: actor),
      throwsStateError,
    );
    expect(await count('local_jobs'), 2);
    expect(await count('local_documents'), 1);
    expect(await count('local_offline_job_purge_entities'), 0);
  });

  test('unrelated financial cache is preserved after local deletion', () async {
    await db.customStatement(
      'INSERT INTO local_financial_cache '
      '(business_id,cache_key,payload_json) VALUES (?,?,?)',
      [business, 'payments:other', '{"job_id":"$otherJob","amount":125}'],
    );
    final reviewed = await deletion.preview(
      businessId: business, jobId: job, actorId: actor);
    await deletion.confirm(businessId: business, jobId: job,
      actorId: actor, reviewed: reviewed);
    expect(await count('local_jobs'), 1);
    expect(await count('local_financial_cache'), 1);
  });

  test('rejects linked queued edits without erasing any rows', () async {
    await db.customStatement(
      "INSERT INTO sync_outbox (business_id,entity_type,entity_id,operation,payload_json) "
      "VALUES (?,'work_summary',?,'update',?)",
      [business, job, '{"job_id":"$job"}'],
    );
    await expectLater(
      deletion.preview(businessId: business, jobId: job, actorId: actor),
      throwsStateError,
    );
    expect(await count('local_jobs'), 2);
    expect(await count('local_documents'), 1);
  });
}
