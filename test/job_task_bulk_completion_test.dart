import 'dart:convert';
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
    'general future reminders and zero-hour allocations are excluded; split task counted once',
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
      expect(plan.count, 6);
      expect(plan.labor, hasLength(6));
      expect(await bulk.complete(plan, now), 6);
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
        'Open',
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
}
