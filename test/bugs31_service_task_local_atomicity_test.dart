import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_task_assignment_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TEST Service Task creates on an existing Job with no financial write',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalPayrollRepository(db, business: 'shop', owner: true);
    await repo.prepare();
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) "
      "VALUES('existing','shop','full','Synthetic repair','open','J-TEST')",
    );
    await db.transaction(() async {
      await LocalTaskAssignmentStore(db)
          .linkEmployee('shop', 'existing', 'mechanic', 'Chris');
      await repo.createRecheck(
        operation: 'test-existing-task-1',
        job: 'existing',
        description: 'Inspect intake system',
        employee: 'mechanic',
        name: 'Chris',
        rate: 3500,
        estimatedMinutes: 45,
        kind: 'job',
      );
    });
    final jobs = await db.customSelect(
      "SELECT id FROM local_jobs WHERE business_id='shop'",
    ).get();
    expect(jobs, hasLength(1));
    final tasks = await repo.tasks();
    expect(tasks.where((t) => t['job_id'] == 'existing'), hasLength(1));
    expect(tasks.single['description'], 'Inspect intake system');
    final outbox = await db.customSelect(
      "SELECT id FROM sync_outbox WHERE business_id='shop' AND entity_type='job_create'",
    ).get();
    expect(outbox, isEmpty);
  });

  test('TEST task-first new Job and queued identity roll back together on failure',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalPayrollRepository(db, business: 'shop', owner: true);
    await repo.prepare();
    final service = OfflineJobAdminService(database: db);
    final assignments = LocalTaskAssignmentStore(db);

    Future<void> create({required bool fail}) async {
      await db.transaction(() async {
        final job = await service.queueJobCreate(
          'shop',
          customerId: 'synthetic-customer',
          customerName: 'Synthetic Customer',
          title: 'Synthetic task-first repair',
        );
        await assignments.linkEmployee('shop', job, 'mechanic', 'Chris');
        await repo.createRecheck(
          operation: fail ? 'failed-task' : 'successful-task',
          job: job,
          description: 'Inspect vehicle',
          employee: 'mechanic',
          name: 'Chris',
          rate: 3500,
          estimatedMinutes: 60,
          kind: 'job',
        );
        if (fail) throw StateError('Simulated task creation failure');
      });
    }

    await expectLater(create(fail: true), throwsStateError);
    Future<int> count(String table) async {
      final rows = await db.customSelect(
        'SELECT COUNT(*) AS n FROM $table WHERE business_id=?',
        variables: [const Variable<String>('shop')],
      ).getSingle();
      return rows.read<int>('n');
    }
    expect(await count('local_jobs'), 0);
    expect(await count('local_job_assignments'), 0);
    expect(await count('regular_payroll_tasks'), 0);
    expect(await count('sync_outbox'), 0);

    await create(fail: false);
    expect(await count('local_jobs'), 1);
    expect(await count('local_job_assignments'), 1);
    expect(await count('regular_payroll_tasks'), 1);
    expect(await count('sync_outbox'), 1);
    final jobRow = await db.customSelect(
      "SELECT id,job_number,sync_state FROM local_jobs WHERE business_id='shop'",
    ).getSingle();
    expect(jobRow.read<String>('job_number'), startsWith('J-'));
    expect(jobRow.read<String>('sync_state'), 'pending');
    final task = (await repo.tasks()).single;
    expect(task['job_id'], jobRow.read<String>('id'));
  });
  test('Owner identity revocation rolls back task, Job and pending outbox',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var ownerActive = true;
    final repo = LocalPayrollRepository(
      db, business: 'shop', owner: true,
      assertOwnerGrant: () {
        if (!ownerActive) throw StateError('Owner session changed');
      },
    );
    await repo.prepare();

    await expectLater(db.transaction(() async {
      final job = await OfflineJobAdminService(database: db).queueJobCreate(
        'shop',
        customerId: 'synthetic-customer',
        customerName: 'Test Customer',
        title: 'Pending task',
      );
      await LocalTaskAssignmentStore(db)
          .linkEmployee('shop', job, 'mechanic', 'Chris');
      await repo.createRecheck(
        operation: 'revoked-task',
        job: job,
        description: 'Inspect brakes',
        employee: 'mechanic',
        name: 'Chris',
        rate: 3500,
        estimatedMinutes: 45,
        kind: 'job',
        queueChange: () async {
          ownerActive = false; // Identity changes before commit.
        },
      );
    }), throwsStateError);

    for (final table in [
      'local_jobs',
      'local_job_assignments',
      'regular_payroll_tasks',
      'sync_outbox',
    ]) {
      final rows = await db.customSelect(
        'SELECT COUNT(*) AS n FROM $table WHERE business_id=?',
        variables: [const Variable<String>('shop')],
      ).getSingle();
      expect(rows.read<int>('n'), 0, reason: table);
    }
  });

}
