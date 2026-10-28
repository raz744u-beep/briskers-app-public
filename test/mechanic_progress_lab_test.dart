import 'dart:io';
import 'package:briskers_app/tasks_lab/fixture.dart';
import 'package:briskers_app/services/local_job_tasks_lab_store.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const shop = BriskersLabFixture.businessId;
  const job = BriskersLabFixture.jobId;
  const invoice = BriskersLabFixture.invoiceId;
  const line = 'lab-differential';

  test('Two mechanics finish independently; task Done only after both', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final store=LocalJobTasksLabStore(db);
    try {
      await store.reconcileDocument(
        businessId:shop,jobId:job,documentId:invoice,
        laborLines:LocalJobTasksLabStore.laborLines(BriskersLabFixture.invoice));
      await store.saveAllocations(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        hoursByEmployee:{'lab-chris':0.5,'lab-adam':0.3});
      expect(await store.jobStatus(shop,job),'open');
      expect(await store.setMechanicTaskProgress(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris',status:'in_progress'),'in_progress');
      expect(await store.jobStatus(shop,job),'in_progress');
      expect(await store.setMechanicTaskProgress(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris',status:'done'),'in_progress');
      var current=(await store.list(shop,job)).singleWhere(
        (t)=>t['line_id']==line);
      expect(current['status'],'in_progress');
      expect(current['completed_at'],isNull);
      expect((await store.completedWork(shop,job)).where(
        (t)=>t['line_id']==line),isEmpty);
      await expectLater(store.saveAllocations(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        hoursByEmployee:{'lab-adam':0.8}),throwsStateError);
      final before=await store.mechanicProgressForJob(shop,job);
      expect(before.singleWhere((r)=>r['employee_id']=='lab-chris')
        ['status'],'done');
      expect(before.any((r)=>r['employee_id']=='lab-adam'),isFalse);
      expect(await store.setMechanicTaskProgress(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-adam',status:'done'),'done');
      current=(await store.list(shop,job)).singleWhere(
        (t)=>t['line_id']==line);
      expect(current['status'],'done');
      expect(current['completed_at'],isA<int>());
      final ledger=(await store.completedWork(shop,job)).singleWhere(
        (t)=>t['line_id']==line);
      final covered=(ledger['payroll_allocations'] as List).cast<Map<String,dynamic>>();
      expect({for(final p in covered) p['employee_id']:p['hours']},
        {'lab-adam':0.3,'lab-chris':0.5});
      expect(await store.jobStatus(shop,job),'in_progress');
      expect(await store.payrollTestPayments(shop),isEmpty);
      final reload=LocalJobTasksLabStore(db);
      final progress=await reload.mechanicProgressForJob(shop,job);
      expect(progress.where((p)=>p['line_id']==line &&
        p['status']=='done'),hasLength(2));
      await expectLater(store.setMechanicTaskProgress(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris',status:'in_progress'),throwsStateError);
    } finally {
      await db.close();
    }
  });

  test('A single mechanic may tap Done directly without Start', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final store=LocalJobTasksLabStore(db);
    try {
      await store.reconcileDocument(
        businessId:shop,jobId:job,documentId:invoice,
        laborLines:LocalJobTasksLabStore.laborLines(BriskersLabFixture.invoice));
      await store.saveAllocations(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        hoursByEmployee:{'lab-chris':0.8});
      expect(await store.setMechanicTaskProgress(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris',status:'done'),'done');
      final entry=(await store.mechanicProgressForJob(shop,job)).single;
      expect(entry['started_at'],isA<int>());
      expect(entry['completed_at'],isA<int>());
      expect((await store.list(shop,job)).singleWhere(
        (t)=>t['line_id']==line)['status'],'done');
      await expectLater(store.setMechanicTaskProgress(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-adam',status:'in_progress'),throwsStateError);
    } finally {
      await db.close();
    }
  });

  test('Waiting for Parts holds are not overridden by mechanic Start/Done',
      () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final store=LocalJobTasksLabStore(db);
    try {
      await store.reconcileDocument(
        businessId:shop,jobId:job,documentId:invoice,
        laborLines:LocalJobTasksLabStore.laborLines(BriskersLabFixture.invoice));
      await store.saveAllocations(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        hoursByEmployee:{'lab-adam':0.8});
      await store.changeJobStatus(
        businessId:shop,jobId:job,statusCode:'waiting_parts');
      await store.setMechanicTaskProgress(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-adam',status:'in_progress');
      expect(await store.jobStatus(shop,job),'waiting_parts');
      await store.setMechanicTaskProgress(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-adam',status:'done');
      expect(await store.jobStatus(shop,job),'waiting_parts');
    } finally {
      await db.close();
    }
  });

  test('UI offers per-mechanic start/done and uses a green check, not strike',
      () {
    // Source contract: same compact card is rendered from the job detail
    // and Service Tasks workspace, without duplicated task records.
    final main=File('lib/tasks_lab_main.dart').readAsStringSync();
    expect(main,contains('_mechanicProgressControls(task,completeTask:done)'));
    expect(main,contains('Icons.check_circle'));
    expect(main,contains("'done'"));
    expect(main,contains("'in_progress'"));
    expect(main,contains('setMechanicTaskProgress('));
    final editor=main.split('Future<void> _editTask(').last
      .split('Future<void> _editEmployeeNames()').first;
    expect(editor,isNot(contains("labelText: 'Task status'")));
    expect(editor,isNot(contains('status: status,')));

    expect(main,isNot(contains('TextDecoration.lineThrough')));
  });
}
