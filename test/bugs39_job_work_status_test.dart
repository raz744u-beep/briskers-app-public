import 'support/empty_retirement_gateway.dart';

import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/job_sync_service.dart';
import 'package:briskers_app/services/test_job_cleanup_gateway.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/job_status_local_events.dart';
import 'package:briskers_app/services/job_task_bulk_completion.dart';
import 'package:briskers_app/services/local_document_identity.dart';
import 'package:briskers_app/services/local_job_core_projection.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/local_job_work_state.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:briskers_app/services/owner_job_work_status_repair.dart';
import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoCleanup extends TestJobCleanupGateway {
  @override
  Future<Map<String, dynamic>> tombstones(String business) async => {
    'schema_version': 1,
    'business_id': business,
    'deleted_job_ids': <String>[],
    'deleted_document_ids': <String>[],
  };
}

class _StaleJobs extends BriskersApi {
  @override
  Future<Map<String, dynamic>> syncPullJobsBootstrap(
    String business, {
    String? afterJobId,
    int limit = 25,
  }) async => {
    'mode': 'bootstrap',
    'bootstrap_cursor': 10,
    'has_more': false,
    'next_job_id': 'sync',
    'bundles': [
      {
        'job': {
          'id': 'sync',
          'business_id': business,
          'job_number': 'sync',
          'title': 'Server description',
          'status': 'open',
          'status_name': 'Open',
          'row_version': 8,
          'updated_at': '2020-01-01T00:00:00Z',
          'assignments': <dynamic>[],
          'visits': <dynamic>[],
          'capabilities': {'manage_job': true},
        },
        'pre_inspection': null,
        'findings': <dynamic>[],
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const business = LocalDocumentIdentity.gloriaBusiness;
  final now = DateTime(2026, 11, 17, 9);
  late Directory directory;
  late File file;
  late BriskersLocalDatabase db;
  late LocalPayrollRepository payroll;
  StreamSubscription<List<QueryRow>>? observer;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('job-work-status');
    file = File('${directory.path}/shop.sqlite');
    db = BriskersLocalDatabase(NativeDatabase(file));
    payroll = LocalPayrollRepository(db, business: business, owner: true);
    await payroll.prepare();
  });
  tearDown(() async {
    await observer?.cancel();
    observer = null;
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<void> job(
    String id, {
    String status = 'open',
    String? number,
    String customer = 'Customer',
    String? invoice,
  }) async {
    await db.customStatement(
      '''INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,customer_name,row_version)
      VALUES(?,?,'owner','Repair',?,?,?,7)''',
      [id, business, status, number ?? id, customer],
    );
    if (invoice != null) {
      await db.customStatement(
        "INSERT INTO local_documents(id,business_id,job_id,kind,document_number,status,document_date) VALUES(?,?,?,'invoice',?,'closed','2026-11-17')",
        ['invoice-$id', business, id, invoice],
      );
    }
    await payroll.setMainMechanic(id, 'kam', 'Kam');
  }

  Future<String> labor(String id, String operation) async {
    await payroll.createRecheck(
      operation: operation,
      job: id,
      description: 'Repair $operation',
      employee: 'kam',
      name: 'Kam',
      rate: 3500,
      estimatedMinutes: 120,
    );
    return (await payroll.work(job: id))
            .singleWhere((r) => r['description'] == 'Repair $operation')['id']
        as String;
  }

  Future<String> status(String id) async =>
      (await db
              .customSelect(
                'SELECT status FROM local_jobs WHERE business_id=? AND id=?',
                variables: [const Variable(business), Variable(id)],
              )
              .getSingle())
          .read<String>('status');
  Future<String> financial() async => jsonEncode([
    for (final table in [
      'local_documents',
      'regular_payroll_payments',
      'regular_payroll_work_coverage',
    ])
      (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
          .map((r) => r.data)
          .toList(),
  ]);
  Future<void> restart() async {
    await observer?.cancel();
    observer = null;
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(file));
    payroll = LocalPayrollRepository(db, business: business, owner: true);
    await payroll.prepare();
  }

  test('individual Start, partial and all Done persist In progress; payments and closed invoice unchanged', () async {
    await job('J-41', customer: 'Tyra Legard', invoice: '6360');
    final first = await labor('J-41', 'one'),
        second = await labor('J-41', 'two');
    final saved = await financial();
    expect(await status('J-41'), 'open');
    observer = await LocalJobWorkState.observe(db);
    final event = LocalJobStatusEvents.changes.firstWhere(
      (e) => e.jobId == 'J-41' && e.code == 'in_progress',
    );
    await payroll.recordAllocatedTime(first, 'In Progress', 0, 0, '2026-11-17');
    expect(
      (await event.timeout(const Duration(seconds: 2))).code,
      'in_progress',
    );
    expect(await status('J-41'), 'in_progress');
    await payroll.recordAllocatedTime(first, 'Done', 120, 120, '2026-11-17');
    expect(await status('J-41'), 'in_progress');
    await payroll.recordAllocatedTime(second, 'Done', 120, 120, '2026-11-17');
    final work = await payroll.work(job: 'J-41');
    expect(
      work.every(
        (r) =>
            r['state'] == 'Done' &&
            r['estimated_minutes'] == 120 &&
            r['actual_minutes'] == 120 &&
            r['paid_minutes'] == 0,
      ),
      isTrue,
    );
    expect(await status('J-41'), 'in_progress');
    expect(await financial(), saved);
    await restart();
    expect(await status('J-41'), 'in_progress');
    expect(await financial(), saved);
    await OfflineJobAdminService(database: db)
        .queueStatus(business, 'J-41', code: 'completed', name: 'Completed');
    await payroll.recordAllocatedTime(first, 'Open', 0, 0, '2026-11-17');
    expect(await status('J-41'), 'completed');
    expect(await financial(), saved);
  });

  test('Start All atomic local commit, one visible status and Finish All never completes job', () async {
    await job('bulk', invoice: '9000');
    await labor('bulk', 'one');
    await labor('bulk', 'two');
    final saved = await financial();
    observer = await LocalJobWorkState.observe(db);
    final events = <LocalJobStatusChanged>[];
    final subscription = LocalJobStatusEvents.changes
        .where((e) => e.jobId == 'bulk')
        .listen(events.add);
    addTearDown(subscription.cancel);
    final bulk = JobTaskBulkCompletion(payroll);
    final start = await bulk.plan('bulk', now, starting: true);
    expect(await bulk.start(start, now), 2);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events.map((e) => e.code), ['in_progress']);
    expect(await bulk.start(start, now), 0);
    expect(await bulk.complete(await bulk.plan('bulk', now), now), 2);
    expect(await status('bulk'), 'in_progress');
    expect(await financial(), saved);
    await restart();
    expect(await status('bulk'), 'in_progress');
    expect(
      await JobTaskBulkCompletion(
        payroll,
      ).complete(await JobTaskBulkCompletion(payroll).plan('bulk', now), now),
      0,
    );
  });

  test('failed task bulk write rolls back task, job, intent, queue and emits no status', () async {
    await job('rollback');
    await labor('rollback', 'one');
    await labor('rollback', 'two');
    final bulk = JobTaskBulkCompletion(payroll),
        plan = await bulk.plan('rollback', now, starting: true);
    observer = await LocalJobWorkState.observe(db);
    final events = <LocalJobStatusChanged>[];
    final subscription = LocalJobStatusEvents.changes
        .where((e) => e.jobId == 'rollback')
        .listen(events.add);
    addTearDown(subscription.cancel);
    final last = (plan.labor.last['id'] as String).replaceAll("'", "''");
    await db.customStatement(
      "CREATE TRIGGER fail_later BEFORE UPDATE ON regular_payroll_portions WHEN NEW.id='$last' BEGIN SELECT RAISE(ABORT,'test failure'); END",
    );
    final queue = jsonEncode(
      (await db.customSelect('SELECT * FROM sync_outbox').get())
          .map((r) => r.data)
          .toList(),
    );
    await expectLater(bulk.start(plan, now), throwsA(anything));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(await status('rollback'), 'open');
    expect(events, isEmpty);
    expect(
      (await payroll.work(job: 'rollback')).every((r) => r['state'] == 'Open'),
      isTrue,
    );
    expect(await LocalJobWorkState(db).retainedJobIds(business), isEmpty);
    expect(
      jsonEncode(
        (await db.customSelect('SELECT * FROM sync_outbox').get())
            .map((r) => r.data)
            .toList(),
      ),
      queue,
    );
  });

  test('stale history after acknowledged sync cannot revert started or completed job', () async {
    await job('sync');
    final id = await labor('sync', 'one');
    await payroll.recordAllocatedTime(id, 'In Progress', 0, 0, '2026-11-17');
    await db.customStatement(
      "DELETE FROM sync_outbox WHERE entity_type='job_admin'",
    );
    final remote = {
      'id': 'sync',
      'status': 'open',
      'status_name': 'Open',
      'row_version': 8,
      'updated_at': '2020-01-01T00:00:00Z',
    };
    expect(
      (await LocalJobCoreProjection.merge(db, business, remote))['status'],
      'in_progress',
    );
    // An unrelated newer server update is still not evidence work never started.
    expect(
      (await LocalJobCoreProjection.merge(db, business, {
        ...remote,
        'updated_at': '2099-01-01T00:00:00Z',
      }))['status'],
      'in_progress',
    );
    await OfflineJobAdminService(database: db)
        .queueStatus(business, 'sync', code: 'completed', name: 'Completed');
    expect(
      (await LocalJobCoreProjection.merge(db, business, remote))['status'],
      'completed',
    );
    await restart();
    expect(
      (await LocalJobCoreProjection.merge(db, business, remote))['status'],
      'completed',
    );
  });

  test('Owner J41 J56 J60 corrections use exact identity, persist once, preserve closed and payments', () async {
    for (final t in [
      ('J-41', '6360', 'Tyra Legard'),
      ('J-56', '6376', 'Terrance Sanders'),
      ('J-60', '6380', 'Glenn Smith'),
    ]) {
      await job(t.$1, number: t.$1, customer: t.$3, invoice: t.$2);
    }
    await job('closed', status: 'completed');
    await job('unknown-zero', status: 'in_progress');
    final saved = await financial();
    final repair = OwnerJobWorkStatusRepair(db);
    await repair.reconcile(business, isOwner: false);
    expect(await status('J-41'), 'open');
    await repair.reconcile(business, isOwner: true);
    expect(await status('J-41'), 'in_progress');
    expect(await status('J-56'), 'in_progress');
    expect(await status('J-60'), 'open');
    expect(await status('closed'), 'completed');
    expect(await status('unknown-zero'), 'in_progress');
    expect(await financial(), saved);
    await restart();
    await OwnerJobWorkStatusRepair(db).reconcile(business, isOwner: true);
    expect(
      (await db
              .customSelect('SELECT * FROM owner_job_work_status_repair_v1')
              .get())
          .length,
      3,
    );
    final id = await labor('J-60', 'start-after-repair');
    await payroll.recordAllocatedTime(id, 'In Progress', 0, 0, '2026-11-17');
    await OwnerJobWorkStatusRepair(db).reconcile(business, isOwner: true);
    expect(await status('J-60'), 'in_progress');
    expect(await financial(), saved);
  });

  test('repair skips ambiguous identities, newer task activity and already completed J41', () async {
    await job(
      'J-41',
      status: 'completed',
      number: 'J-41',
      customer: 'Tyra Legard',
      invoice: '6360',
    );
    await job(
      'J-56-a',
      number: 'J-56',
      customer: 'Terrance Sanders',
      invoice: '6376',
    );
    await job(
      'J-56-b',
      number: 'J-56',
      customer: 'Terrance Sanders',
      invoice: '6376',
    );
    await job('J-60', number: 'J-60', customer: 'Glenn Smith', invoice: '6380');
    final id = await labor('J-60', 'already-started');
    await payroll.recordAllocatedTime(id, 'In Progress', 0, 0, '2026-11-17');
    await OwnerJobWorkStatusRepair(db).reconcile(business, isOwner: true);
    expect(await status('J-41'), 'completed');
    expect(await status('J-56-a'), 'open');
    expect(await status('J-56-b'), 'open');
    expect(await status('J-60'), 'in_progress');
  });

  test('legacy reliable activity repairs Open; historical Done display and zero percent never infer status', () async {
    await job('active');
    final id = await labor('active', 'one');
    await payroll.recordAllocatedTime(id, 'In Progress', 0, 0, '2026-11-17');
    await db.customStatement('DELETE FROM local_job_task_activity_v1');
    await db.customStatement('DELETE FROM local_job_status_intent_v1');
    await db.customStatement(
      "UPDATE local_jobs SET status='open' WHERE id='active'",
    );
    await job('historic');
    final old = await labor('historic', 'old');
    await db.customStatement(
      "UPDATE regular_payroll_portions SET state='Done',completed_date=NULL WHERE id=?",
      [old],
    );
    await job('unstarted');
    await OfflineJobAdminService(database: db).reconcileWorkStatus(business);
    expect(await status('active'), 'in_progress');
    expect(await status('historic'), 'open');
    expect(await status('unstarted'), 'open');
    final repository = LocalJobRepository(database: db);
    await repository.jobCount(business);
    await repository.jobCount(business);
    expect(await status('active'), 'in_progress');
  });
  test(
    'mechanic Start and Finish update job locally without paying wages',
    () async {
      await job('mechanic');
      final id = await labor('mechanic', 'one');
      final mechanic = LocalPayrollRepository(
        db,
        business: business,
        owner: false,
      );
      var sessionChecks = 0;
      for (final state in ['In Progress', 'Done']) {
        final row = (await payroll.work(job: 'mechanic')).single;
        await mechanic.updateMechanicWork(
          job: 'mechanic',
          employee: 'kam',
          id: id,
          state: state,
          minutes: state == 'Done' ? 120 : 0,
          date: '2026-11-17',
          expectedRevision: row['version'] as int,
          assertSession: () => sessionChecks++,
        );
        expect(await status('mechanic'), 'in_progress');
      }
      expect(sessionChecks, greaterThan(0));
      expect((await payroll.work(job: 'mechanic')).single['paid_minutes'], 0);
    },
  );

  test('acknowledged task status survives actual full sync cache rebuild and restart', () async {
    await job('sync');
    final id = await labor('sync', 'one');
    await payroll.recordAllocatedTime(id, 'In Progress', 0, 0, '2026-11-17');
    await db.customStatement('DELETE FROM sync_outbox');
    await db.customStatement("UPDATE local_jobs SET sync_state='synced'");
    final saved = await financial();
    await JobSyncService(
      database: db,
      api: _StaleJobs(),
      cleanupGateway: _NoCleanup(),
      retirementGateway: const EmptyRetirementGateway(),
    ).pull(business);
    expect(await status('sync'), 'in_progress');
    expect(await financial(), saved);
    await restart();
    expect(await status('sync'), 'in_progress');
    expect((await payroll.work(job: 'sync')).single['state'], 'In Progress');
  });

  test('same creation remap preserves durable status evidence and pending status operation', () async {
    await job('local-job');
    await job('server-job');
    final id = await labor('local-job', 'one');
    await payroll.recordAllocatedTime(id, 'In Progress', 0, 0, '2026-11-17');
    await LocalJobRepository(database: db)
        .remapProvisionalJob(business, 'local-job', 'server-job');
    expect(await status('server-job'), 'in_progress');
    expect(await LocalJobWorkState(db).retainedJobIds(business), {
      'server-job',
    });
    final remote = {
      'id': 'server-job',
      'status': 'open',
      'row_version': 8,
      'updated_at': '2020-01-01T00:00:00Z',
    };
    expect(
      (await LocalJobCoreProjection.merge(db, business, remote))['status'],
      'in_progress',
    );
  });
}
