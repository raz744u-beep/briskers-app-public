import 'dart:convert';
import 'package:briskers_app/services/job_task_summary.dart';
import 'package:briskers_app/services/local_task_assignment_store.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'dart:io';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/job_task_bulk_completion.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 12, 8);
  late Directory directory;
  late File file;
  late BriskersLocalDatabase db;
  late LocalPayrollRepository repo;
  late JobTaskBulkCompletion bulk;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('bulk-done');
    file = File('${directory.path}/shop.sqlite');
    db = BriskersLocalDatabase(NativeDatabase(file));
    repo = LocalPayrollRepository(db, business: 'shop', owner: true);
    bulk = JobTaskBulkCompletion(repo);
    await repo.prepare();
    await LocalDocumentDetailCache.initialize(db);
    await repo.saveEmployeeCompensation(
      employee: 'kam',
      name: 'Kam',
      rate: 3500,
      weeklyBase: false,
    );
    for (final job in ['J-53', 'old', 'other']) {
      await db.customStatement(
        "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,customer_name) VALUES(?,'shop','owner','Repair','open',?,'Damien Hester')",
        [job, job],
      );
      await db.customStatement(
        "INSERT INTO local_documents(id,business_id,job_id,kind,document_date,status) VALUES(?,'shop',?,'invoice',?,'paid')",
        [job, job, job == 'old' ? '2026-11-08' : '2026-11-11'],
      );
      await LocalDocumentDetailCache(database: db).save('shop', job, {
        'id': job,
        'kind': 'invoice',
        'job_id': job,
        'status': 'paid',
        'total_amount': 100,
        'paid_amount': 100,
        'pending_payment': 0,
        'lines': [
          for (var i = 0; i < (job == 'J-53' ? 6 : 1); i++)
            {
              'id': 'line-$i',
              'line_kind': 'labor',
              'description': 'Repair $i',
              'quantity': i == 5 ? 1.5 : 2,
            },
        ],
      });
      await repo.setMainMechanic(job, 'kam', 'Kam');
    }
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
    LocalDocumentDetailCache.sqliteWritesEnabled = false;
  });
  Future<String> snapshot() async => jsonEncode([
    for (final table in [
      'regular_payroll_portions',
      'local_mechanic_work_credits_v1',
      'regular_payroll_actual_time',
      'regular_payroll_payments',
      'regular_payroll_work_coverage',
    ])
      (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
          .map((r) => r.data)
          .toList(),
  ]);
  test(
    'Start All persists offline, preserves hours, and Finish All credits once',
    () async {
      await repo.addShopTask(
        'kam',
        'Due now',
        'General',
        job: 'J-53',
        due: now,
      );
      await repo.addShopTask(
        'kam',
        'Future reminder',
        'General',
        job: 'J-53',
        due: now.add(const Duration(days: 1)),
      );
      final before = await repo.work(job: 'J-53');
      final plan = await bulk.plan('J-53', now, starting: true);
      expect(plan.count, 7);
      expect(await bulk.start(plan, now), 7);
      final started = await repo.work(job: 'J-53');
      expect(started.every((r) => r['state'] == 'In Progress'), isTrue);
      expect(
        started.map((r) => r['estimated_minutes']),
        before.map((r) => r['estimated_minutes']),
      );
      expect(started.every((r) => r['actual_minutes'] == 0), isTrue);
      expect(await repo.historyWithWork('kam'), isEmpty);
      final progress = await JobTaskSummary(db).progress('shop', 'J-53');
      expect(progress.started, 7);
      expect(progress.done, 0);
      final saved = await snapshot();
      expect(await bulk.start(plan, now), 0);
      expect(await snapshot(), saved);
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      repo = LocalPayrollRepository(db, business: 'shop', owner: true);
      bulk = JobTaskBulkCompletion(repo);
      expect(await bulk.start(plan, now), 0);
      final finish = await bulk.plan('J-53', now);
      expect(await bulk.complete(finish, now), 7);
      final finished = await repo.work(job: 'J-53');
      expect(
        finished.fold<int>(0, (n, r) => n + (r['actual_minutes'] as int)),
        690,
      );
      expect(finished.every((r) => r['paid_minutes'] == 0), isTrue);
      expect(await bulk.complete(finish, now), 0);
      final general = await repo.shopTasks();
      expect(
        general.singleWhere((r) => r['description'] == 'Due now')['status'],
        'done',
      );
      expect(
        general.singleWhere(
          (r) => r['description'] == 'Future reminder',
        )['status'],
        'planned',
      );
      expect((await repo.work(job: 'other')).single['state'], 'Open');
      expect((await bulk.plan('old', now, starting: true)).count, 0);
    },
  );

  test('Start All rejects changed hours and rolls back a failed later task', () async {
    final stale = await bulk.plan('J-53', now, starting: true);
    await repo.setEstimatedMinutes(
      stale.labor.first['task_id'] as String,
      'kam',
      123,
    );
    final before = await snapshot();
    await expectLater(bulk.start(stale, now), throwsStateError);
    expect(await snapshot(), before);
    final plan = await bulk.plan('J-53', now, starting: true);
    await db.customStatement(
      "CREATE TRIGGER simulated_start_failure BEFORE UPDATE ON regular_payroll_portions "
      "WHEN NEW.id='${(plan.labor.last['id'] as String).replaceAll("'", "''")}' "
      "BEGIN SELECT RAISE(ABORT,'Synthetic write failure'); END",
    );
    await expectLater(bulk.start(plan, now), throwsA(anything));
    expect(await snapshot(), before);
  });

  test(
    'six Kam tasks complete offline once with exact 11.5 hours; Paid invoice never pays wages',
    () async {
      final plan = await bulk.plan('J-53', now);
      expect(plan.count, 6);
      final before = await repo.work(job: 'J-53');
      expect(await bulk.complete(plan, now), 6);
      final after = await repo.work(job: 'J-53');
      expect(
        after.every(
          (r) =>
              r['state'] == 'Done' &&
              r['employee_id'] == 'kam' &&
              r['paid_minutes'] == 0,
        ),
        isTrue,
      );
      expect(
        after.fold<int>(0, (n, r) => n + (r['actual_minutes'] as int)),
        690,
      );
      expect(
        after.map((r) => r['estimated_minutes']),
        before.map((r) => r['estimated_minutes']),
      );
      expect(await repo.historyWithWork('kam'), isEmpty);
      final saved = await snapshot();
      expect(await bulk.complete(plan, now), 0);
      expect(await snapshot(), saved);
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      repo = LocalPayrollRepository(db, business: 'shop', owner: true);
      bulk = JobTaskBulkCompletion(repo);
      expect(await bulk.complete(plan, now), 0);
      expect(await snapshot(), saved);
      expect((await repo.work(job: 'other')).single['state'], 'Open');
      expect((await repo.work(job: 'old')).single['actual_minutes'], 0);
      expect((await bulk.plan('old', now)).count, 0);
    },
  );
  test(
    'Finish All completes zero-hour labor, preserves scheduled reminders and counts split tasks once',
    () async {
      await repo.assignExistingService(
        job: 'J-53',
        invoice: 'J-53',
        line: 'line-0',
        employee: 'chris',
        name: 'Chris',
        rate: 3500,
        minutes: 30,
      );
      final row = (await repo.work(
        job: 'J-53',
      )).firstWhere((r) => r['source_line_id'] == 'line-1');
      await repo.setEstimatedMinutes(row['task_id'] as String, 'kam', 0);
      await repo.addShopTask(
        'kam',
        'Due now',
        'General',
        job: 'J-53',
        due: now,
      );
      await repo.addShopTask(
        'kam',
        'Future reminder',
        'General',
        job: 'J-53',
        due: now.add(const Duration(days: 1)),
      );
      await repo.addShopTask('kam', 'Other job', 'General', job: 'other');
      final plan = await bulk.plan('J-53', now);
      expect(plan.count, 7);
      expect(plan.labor, hasLength(7));
      expect(await bulk.complete(plan, now), 7);
      final general = await repo.shopTasks();
      expect(
        general.singleWhere((r) => r['description'] == 'Due now')['status'],
        'done',
      );
      expect(
        general.singleWhere(
          (r) => r['description'] == 'Future reminder',
        )['status'],
        'planned',
      );
      expect(
        general.singleWhere((r) => r['description'] == 'Other job')['status'],
        'planned',
      );
      expect(
        (await repo.work(
          job: 'J-53',
        )).singleWhere((r) => r['id'] == row['id'])['state'],
        'Done',
      );
    },
  );
  test(
    'changed assigned hours require reconfirmation without completing any task',
    () async {
      final plan = await bulk.plan('J-53', now);
      await repo.setEstimatedMinutes(
        plan.labor.first['task_id'] as String,
        'kam',
        123,
      );
      final before = await snapshot();
      await expectLater(bulk.complete(plan, now), throwsStateError);
      expect(await snapshot(), before);
    },
  );
  test(
    'failure on later credit rolls back earlier completions and general tasks',
    () async {
      final plan = await bulk.plan('J-53', now);
      await db.customStatement(
        "CREATE TRIGGER simulated_failure BEFORE UPDATE ON regular_payroll_portions WHEN NEW.id='${(plan.labor.last['id'] as String).replaceAll("'", "''")}' BEGIN SELECT RAISE(ABORT,'Synthetic write failure'); END",
      );
      final before = await snapshot();
      await expectLater(bulk.complete(plan, now), throwsA(anything));
      expect(await snapshot(), before);
      await db.customStatement('DROP TRIGGER simulated_failure');
      expect(await bulk.complete(plan, now), 6);
    },
  );
  test('non-Owner cannot preview or complete a job', () async {
    final plan = await bulk.plan('J-53', now);
    final denied = JobTaskBulkCompletion(
      LocalPayrollRepository(db, business: 'shop', owner: false),
    );
    await expectLater(denied.complete(plan, now), throwsStateError);
    expect(
      (await repo.work(job: 'J-53')).every((r) => r['state'] == 'Open'),
      isTrue,
    );
  });
  test('Glenn-shaped job finishes two positive labor tasks plus a zero-hour diagnostic atomically offline', () async {
    final before=(await repo.work(job:'J-53'));
    // Use three existing invoice labor identities, preserving their assignments.
    for(final row in before.where((r)=>r['source_line_id']!='line-0' && r['source_line_id']!='line-1' && r['source_line_id']!='line-2')) {
      await repo.recordAllocatedTime(row['id'] as String,'Done',row['estimated_minutes'] as int,row['estimated_minutes'] as int,'2026-11-12');
    }
    final diagnostic=before.singleWhere((r)=>r['source_line_id']=='line-0');
    final pump=before.singleWhere((r)=>r['source_line_id']=='line-1');
    final thermostat=before.singleWhere((r)=>r['source_line_id']=='line-2');
    await repo.setEstimatedMinutes(diagnostic['task_id'] as String,'kam',0);
    await repo.setEstimatedMinutes(pump['task_id'] as String,'kam',150);
    await repo.setEstimatedMinutes(thermostat['task_id'] as String,'kam',120);
    await repo.recordAllocatedTime(diagnostic['id'] as String,'In Progress',0,0,'2026-11-12');
    final plan=await bulk.plan('J-53',now);
    expect(plan.count,3);
    expect(await bulk.complete(plan,now),3);
    final done=await repo.work(job:'J-53');
    expect(done.every((r)=>r['state']=='Done'),true);
    expect(done.singleWhere((r)=>r['id']==diagnostic['id'])['actual_minutes'],0);
    expect(done.singleWhere((r)=>r['id']==pump['id'])['actual_minutes'],150);
    expect(done.singleWhere((r)=>r['id']==thermostat['id'])['actual_minutes'],120);
    expect(done.every((r)=>r['paid_minutes']==0),true);
    expect((await repo.historyWithWork('kam')),isEmpty);
    final saved=await snapshot(); expect(await bulk.complete(plan,now),0);
    expect(await snapshot(),saved);
    await db.close(); db=BriskersLocalDatabase(NativeDatabase(file));
    repo=LocalPayrollRepository(db,business:'shop',owner:true);
    expect((await repo.work(job:'J-53')).every((r)=>r['state']=='Done'),true);
  });

  test('explicitly reviewed historical carry can Finish All just as it can finish individually', () async {
    final old=(await repo.work(job:'old')).single;
    await repo.reviewUnpaidCarry('kam',old['id'] as String);
    final plan=await bulk.plan('old',now);
    expect(plan.count,1);
    expect(await bulk.complete(plan,now),1);
    expect((await repo.work(job:'old')).single['state'],'Done');
    expect((await repo.work(job:'old')).single['paid_minutes'],0);
  });

  test('Finish from job list hydrates all three saved labor allocations before planning', () async {
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,status) VALUES('glenn','shop','owner','J-60','Cooling repair','in_progress')");
    await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,kind,document_date,status) VALUES('6380','shop','glenn','invoice','2026-11-17','issued')");
    await LocalDocumentDetailCache(database:db).save('shop','6380',{
      'id':'6380','kind':'invoice','job_id':'glenn','document_date':'2026-11-17','status':'issued',
      'lines':[
        {'id':'diagnostic','line_kind':'labor','name':'Diagnostic. Pressure test cooling system','quantity':0},
        {'id':'pump','line_kind':'labor','name':'Replace water pump','quantity':2.5},
        {'id':'thermostat','line_kind':'labor','name':'Replace thermostat','quantity':2},
      ],
    });
    await OfflineJobAdminService(database:db).queueMainMechanic('shop','glenn',employeeId:'kam',employeeName:'Kam');
    final tasks=(await repo.tasks()).where((r)=>r['job_id']=='glenn').toList();
    expect(tasks,hasLength(3));
    final pump=tasks.singleWhere((r)=>r['source_line_id']=='pump');
    await LocalTaskAssignmentStore(db).allocate('shop',pump['id'] as String,'kam',inherited:true);
    expect(await repo.work(job:'glenn'),hasLength(1));
    final plan=await bulk.plan('glenn',DateTime(2026,11,19));
    expect(plan.count,3);
    expect(await bulk.complete(plan,DateTime(2026,11,19)),3);
    final done=await repo.work(job:'glenn');
    expect(done,hasLength(3)); expect(done.every((r)=>r['state']=='Done'),true);
    expect(done.fold<int>(0,(n,r)=>n+(r['actual_minutes'] as int)),270);
    expect(done.every((r)=>r['paid_minutes']==0),true);
    final progress=await JobTaskSummary(db).progress('shop','glenn');
    expect(progress.done,3);expect(progress.total,3);
    final saved=await snapshot(); expect(await bulk.complete(plan,DateTime(2026,11,19)),0);
    expect(await snapshot(),saved);
  });

}
