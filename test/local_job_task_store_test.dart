import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_job_task_store.dart';

void main() {
  test('v22 task tables are created without invoice edits', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name IN ('local_job_tasks','local_job_task_assignees')",
      ).get();
      expect(tables.map((r) => r.read<String>('name')).toSet(),
          containsAll(['local_job_tasks', 'local_job_task_assignees']));
    } finally {
      await db.close();
    }
  });

  test('replaying a labor line preserves existing task payroll hours', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = LocalJobTaskStore(db);
      await store.createIfMissing(
        id: 'task-1', businessId: 'shop-1', jobId: 'job-12',
        description: 'Replace oil pan', sourceLineId: 'line-1',
        billedHours: 2, payrollHours: 2,
      );
      await store.createIfMissing(
        id: 'task-retry', businessId: 'shop-1', jobId: 'job-12',
        description: 'Changed description', sourceLineId: 'line-1',
        billedHours: 5, payrollHours: 5,
      );
      final tasks = await store.listForJob('shop-1', 'job-12');
      expect(tasks, hasLength(1));
      expect(tasks.single['id'], 'task-1');
      expect(tasks.single['payroll_hours'], 2);
      expect(tasks.single['description'], 'Replace oil pan');
      expect(await store.listForJob('another-shop', 'job-12'), isEmpty);
    } finally {
      await db.close();
    }
  });
  test('mechanic allocation splits hours without changing invoice hours', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = LocalJobTaskStore(db);
      await store.createIfMissing(
        id:'task-2', businessId:'shop-1', jobId:'job-12',
        description:'Replace oil pan', sourceLineId:'line-2',
        billedHours:4, payrollHours:4,
      );
      await store.replaceLocalAssignees(
        businessId:'shop-1', jobId:'job-12', taskId:'task-2',
        hoursByEmployeeId:{'kam':2.5,'chris':1.5},
      );
      expect(await store.assigneesForTask(
        businessId:'shop-1', jobId:'job-12', taskId:'task-2',
      ), {'kam':2.5,'chris':1.5});
      final task = (await store.listForJob('shop-1','job-12')).single;
      expect(task['billed_hours'],4);
      expect(task['payroll_hours'],4);
      await expectLater(
        store.replaceLocalAssignees(
          businessId:'other-shop', jobId:'job-12', taskId:'task-2',
          hoursByEmployeeId:{'outsider':9},
        ),
        throwsStateError,
      );
      expect(await store.assigneesForTask(
        businessId:'shop-1', jobId:'job-12', taskId:'task-2',
      ), {'kam':2.5,'chris':1.5});
    } finally {
      await db.close();
    }
  });

}
