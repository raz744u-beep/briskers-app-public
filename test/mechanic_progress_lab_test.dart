import 'dart:io';
import 'package:briskers_app/tasks_lab/fixture.dart';
import 'package:briskers_app/services/local_job_tasks_lab_store.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Variable;
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

  test('Undo accidental Chris Done restores In Progress while Adam works',
      () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final store=LocalJobTasksLabStore(db);
    try {
      await store.reconcileDocument(
        businessId:shop,jobId:job,documentId:invoice,
        laborLines:LocalJobTasksLabStore.laborLines(BriskersLabFixture.invoice));
      await store.saveAllocations(businessId:shop,jobId:job,
        documentId:invoice,lineId:line,
        hoursByEmployee:{'lab-chris':1.0,'lab-adam':3.0});
      for(final employee in ['lab-chris','lab-adam']) {
        await store.setMechanicTaskProgress(
          businessId:shop,jobId:job,documentId:invoice,lineId:line,
          employeeId:employee,status:'in_progress');
      }
      await store.setMechanicTaskProgress(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris',status:'done');
      expect((await store.list(shop,job)).singleWhere(
        (t)=>t['line_id']==line)['status'],'in_progress');
      final before=await store.mechanicProgressForJob(shop,job);
      expect(before.singleWhere((t)=>t['employee_id']=='lab-adam')
        ['status'],'in_progress');
      expect(await store.undoAccidentalMechanicDone(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris'),'in_progress');
      final after=await store.mechanicProgressForJob(shop,job);
      expect(after.singleWhere((t)=>t['employee_id']=='lab-chris')
        ['status'],'in_progress');
      expect(after.singleWhere((t)=>t['employee_id']=='lab-chris')
        ['completed_at'],isNull);
      expect(after.singleWhere((t)=>t['employee_id']=='lab-adam')
        ['status'],'in_progress');
      expect((await store.list(shop,job)).singleWhere(
        (t)=>t['line_id']==line)['status'],'in_progress');
      expect((await store.completedWork(shop,job))
        .where((t)=>t['line_id']==line),isEmpty);
      expect(await store.payrollTestPayments(shop),isEmpty);
      final audit=await db.customSelect(
        'SELECT previous_status,restored_status FROM '
        'local_lab_task_progress_undo_audit WHERE business_id=?',
        variables:[const Variable<String>(shop)]).get();
      expect(audit,hasLength(1));
      expect(audit.single.read<String>('restored_status'),'in_progress');
      await expectLater(store.undoAccidentalMechanicDone(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris'),throwsStateError);
    } finally {await db.close();}
  });

  test('Direct Done from Not Started can undo to Not Started',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final store=LocalJobTasksLabStore(db);
    try {
      await store.reconcileDocument(businessId:shop,jobId:job,
        documentId:invoice,
        laborLines:LocalJobTasksLabStore.laborLines(BriskersLabFixture.invoice));
      await store.saveAllocations(businessId:shop,jobId:job,
        documentId:invoice,lineId:line,
        hoursByEmployee:{'lab-chris':1.0,'lab-adam':3.0});
      await store.setMechanicTaskProgress(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris',status:'done');
      expect(await store.undoAccidentalMechanicDone(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris'),'planned');
      final rows=await store.mechanicProgressForJob(shop,job);
      final chris=rows.singleWhere((r)=>r['employee_id']=='lab-chris');
      expect(chris['status'],'planned');
      expect(chris['started_at'],isNull);
      expect((await store.list(shop,job)).singleWhere(
        (t)=>t['line_id']==line)['status'],'planned');
      expect(await store.payrollTestPayments(shop),isEmpty);
    } finally {await db.close();}
  });

  test('Undo denied after full task completion and payroll frozen',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final store=LocalJobTasksLabStore(db);
    try {
      await store.reconcileDocument(businessId:shop,jobId:job,
        documentId:invoice,
        laborLines:LocalJobTasksLabStore.laborLines(BriskersLabFixture.invoice));
      await store.saveAllocations(businessId:shop,jobId:job,
        documentId:invoice,lineId:line,
        hoursByEmployee:{'lab-chris':1.0,'lab-adam':3.0});
      for (final name in ['lab-chris','lab-adam']) {
        await store.setMechanicTaskProgress(
          businessId:shop,jobId:job,documentId:invoice,lineId:line,
          employeeId:name,status:'done');
      }
      final frozen=(await store.completedWork(shop,job)).singleWhere(
        (r)=>r['line_id']==line);
      await expectLater(store.undoAccidentalMechanicDone(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris'),throwsStateError);
      expect((await store.completedWork(shop,job)).singleWhere(
        (r)=>r['line_id']==line)['completed_at'],frozen['completed_at']);
    } finally {await db.close();}
  });

  test('Paid Chris may undo progress on active shared task; no money changes',
      () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final store=LocalJobTasksLabStore(db);
    try {
      await store.reconcileDocument(
        businessId:shop,jobId:job,documentId:invoice,
        laborLines:LocalJobTasksLabStore.laborLines(BriskersLabFixture.invoice));
      await store.saveAllocations(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        hoursByEmployee:{'lab-chris':1.0,'lab-adam':3.0});
      for (final mechanic in ['lab-chris','lab-adam']) {
        await store.setMechanicTaskProgress(
          businessId:shop,jobId:job,documentId:invoice,lineId:line,
          employeeId:mechanic,status:'in_progress');
      }
      await store.setMechanicTaskProgress(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris',status:'done');
      // An existing TEST payroll payment is financially immutable even
      // when the mechanic's progress was marked Done accidentally.
      await db.customStatement('''
        CREATE TABLE lab_payroll_task_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
          document_id TEXT NOT NULL, line_id TEXT NOT NULL,
          hours REAL NOT NULL, cents INTEGER NOT NULL,
          method TEXT NOT NULL, paid_at INTEGER NOT NULL
        )
      ''');
      await db.customStatement(
        'INSERT INTO lab_payroll_task_payments '
        '(business_id,employee_id,document_id,line_id,hours,cents,'
        'method,paid_at) VALUES (?,?,?,?,?,?,?,?)',
        [shop,'lab-chris',invoice,line,0.5,1800,'cash',1761510000000]);
      final before=(await db.customSelect(
        'SELECT * FROM lab_payroll_task_payments').getSingle()).data;
      expect(await store.undoAccidentalMechanicDone(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris'),'in_progress');
      final progress=await store.mechanicProgressForJob(shop,job);
      expect(progress.singleWhere((r)=>r['employee_id']=='lab-chris')
        ['status'],'in_progress');
      expect(progress.singleWhere((r)=>r['employee_id']=='lab-adam')
        ['status'],'in_progress');
      expect((await store.list(shop,job)).singleWhere(
        (r)=>r['line_id']==line)['status'],'in_progress');
      final after=(await db.customSelect(
        'SELECT * FROM lab_payroll_task_payments').getSingle()).data;
      expect(after,before);
      final audit=(await db.customSelect(
        'SELECT * FROM local_lab_task_progress_undo_audit'
        ' WHERE business_id=?',variables:[const Variable<String>(shop)])
        .getSingle()).data;
      expect(audit['reason'],'Accidental Done corrected; paid hours preserved');
      // Repeating the Undo is not allowed, and does not change the money.
      await expectLater(store.undoAccidentalMechanicDone(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris'),throwsStateError);
      expect((await db.customSelect(
        'SELECT * FROM lab_payroll_task_payments').getSingle()).data,before);
      // Correction does not change the originally assigned mechanic hours.
      final allocations=await store.allocations(
        businessId:shop,jobId:job,documentId:invoice,lineId:line);
      expect({for(final row in allocations)
        row['employee_id']:row['hours']},{'lab-chris':1.0,'lab-adam':3.0});
    } finally {await db.close();}
  });

  test('Legacy Done without previous_status safely restores In Progress',
      () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final store=LocalJobTasksLabStore(db);
    try {
      await db.customStatement('''
        CREATE TABLE local_lab_mechanic_task_progress (
          business_id TEXT NOT NULL,job_id TEXT NOT NULL,
          document_id TEXT NOT NULL,line_id TEXT NOT NULL,
          employee_id TEXT NOT NULL,status TEXT NOT NULL,
          started_at INTEGER,completed_at INTEGER,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY(business_id,job_id,document_id,line_id,employee_id)
        )
      ''');
      await store.reconcileDocument(
        businessId:shop,jobId:job,documentId:invoice,
        laborLines:LocalJobTasksLabStore.laborLines(BriskersLabFixture.invoice));
      await store.saveAllocations(businessId:shop,jobId:job,
        documentId:invoice,lineId:line,
        hoursByEmployee:{'lab-chris':1.0,'lab-adam':3.0});
      await db.customStatement(
        'INSERT INTO local_lab_mechanic_task_progress '
        '(business_id,job_id,document_id,line_id,employee_id,status,'
        'started_at,completed_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
        [shop,job,invoice,line,'lab-chris','done',1761510000000,
          1761512000000,1761512000000]);
      await store.editTask(businessId:shop,jobId:job,
        documentId:invoice,lineId:line,status:'in_progress');
      expect(await store.undoAccidentalMechanicDone(
        businessId:shop,jobId:job,documentId:invoice,lineId:line,
        employeeId:'lab-chris'),'in_progress');
      final fields=await db.customSelect(
        'PRAGMA table_info(local_lab_mechanic_task_progress)').get();
      expect(fields.where((f)=>f.read<String>('name')=='previous_status'),
        hasLength(1));
      expect((await store.mechanicProgressForJob(shop,job)).single['status'],
        'in_progress');
    } finally {await db.close();}
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
    expect(main,contains("label:const Text('Undo Done'"));
    expect(main,contains("label:const Text('Mark Done'"));
    expect(main,contains("final statusLabel=current=="));
    expect(main,contains("mechanic-status-"));
    expect(main,contains('fontWeight:FontWeight.w700,color:statusColor'));
    expect(main,contains('_undoMechanicDone(task,mechanicId)'));
    expect(main,contains("title:const Text('Undo Done?')"));
    expect(main,contains("title:const Text('Finish entire task?')"));
    expect(main,contains('final lastMechanic='));
    expect(main,contains("child:const Text('Finish Task')"));


    final editor=main.split('Future<void> _editTask(').last
      .split('Future<void> _editEmployeeNames()').first;
    expect(editor,isNot(contains("labelText: 'Task status'")));
    expect(editor,isNot(contains('status: status,')));

    expect(main,isNot(contains('TextDecoration.lineThrough')));
  });
}
