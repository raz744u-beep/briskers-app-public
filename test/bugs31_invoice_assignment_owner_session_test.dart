import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_task_assignment_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local invoice labor allocation uses Owner identity, not payment grant',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
    });
    final currentOwner = ValueNotifier<bool>(true);
    final repo = LocalPayrollRepository(
      db, business: 'shop', owner: true,
      assertOwnerGrant: () {
        if (!currentOwner.value) throw StateError('Owner account changed');
      },
    );
    await repo.prepare();
    await LocalDocumentDetailCache.initialize(db);
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) "
      "VALUES('job','shop','owner','Synthetic repair','open','J-TEST')",
    );
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,kind,document_number) "
      "VALUES('invoice','shop','job','invoice','TEST-1')",
    );
    await LocalDocumentDetailCache(database: db).save(
      'shop', 'invoice',
      {
        'id': 'invoice', 'kind': 'invoice', 'job_id': 'job',
        'lines': [
          {
            'id': 'labor-1', 'line_kind': 'labor',
            'description': 'Inspect cooling system', 'quantity': 1,
          },
        ],
      },
    );
    final assignments = LocalTaskAssignmentStore(db);
    await db.transaction(() async {
      await assignments.linkEmployee('shop', 'job', 'mechanic', 'Chris');
      await repo.registerAssignedLabor(
        jobId: 'job', invoiceId: 'invoice', lineId: 'labor-1',
        employeeId: 'mechanic', employeeName: 'Chris', rateCents: 3500,
      );
      final task = (await repo.tasks()).singleWhere(
        (task) => task['source_line_id'] == 'labor-1',
      );
      await assignments.allocate(
        'shop', task['id'] as String, 'mechanic', inherited: false,
      );
    });
    final credits = await repo.work(employee: 'mechanic');
    expect(credits, hasLength(1));
    expect(credits.single['source_line_id'], 'labor-1');
    expect(credits.single['employee_id'], 'mechanic');
    expect(credits.single['paid_minutes'], 0);
    final outbox = await db.customSelect(
      "SELECT id FROM sync_outbox WHERE business_id='shop' AND entity_type='job_create'",
    ).get();
    expect(outbox, isEmpty);
  });

  test('Owner session revocation aborts invoice assignment without orphan work',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
    });
    var active = true;
    final repo = LocalPayrollRepository(
      db, business: 'shop', owner: true,
      assertOwnerGrant: () {
        if (!active) throw StateError('Owner session changed');
      },
    );
    await repo.prepare();
    await LocalDocumentDetailCache.initialize(db);
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) "
      "VALUES('job','shop','owner','Synthetic repair','open','J-TEST')",
    );
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,kind,document_number) "
      "VALUES('invoice','shop','job','invoice','TEST-1')",
    );
    await LocalDocumentDetailCache(database: db).save(
      'shop', 'invoice',
      {
        'id': 'invoice', 'kind': 'invoice', 'job_id': 'job',
        'lines': [
          {
            'id': 'labor-1', 'line_kind': 'labor',
            'description': 'Inspect cooling system', 'quantity': 1,
          },
        ],
      },
    );
    // Invoice cache hydration may create inherited assignments before this
    // attempt. A rejected edit must restore that exact baseline, not erase it.
    Future<List<Map<String, dynamic>>> snapshot(String table) async =>
        (await db.customSelect(
          "SELECT * FROM $table WHERE business_id='shop'",
        ).get()).map((row) => row.data).toList();
    final beforeAssignments =
        await snapshot('local_job_assignments');
    final beforeTasks =
        await snapshot('regular_payroll_tasks');
    final assignments = LocalTaskAssignmentStore(db);
    await expectLater(db.transaction(() async {
      await assignments.linkEmployee('shop', 'job', 'mechanic', 'Chris');
      await repo.registerAssignedLabor(
        jobId: 'job', invoiceId: 'invoice', lineId: 'labor-1',
        employeeId: 'mechanic', employeeName: 'Chris', rateCents: 3500,
        queueChange: () async { active = false; },
      );
    }), throwsStateError);
    expect(await snapshot('local_job_assignments'),
        beforeAssignments);
    expect(await snapshot('regular_payroll_tasks'), beforeTasks);
  });
}
