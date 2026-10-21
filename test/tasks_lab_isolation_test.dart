import 'dart:io';
import 'package:briskers_app/tasks_lab/fixture.dart';
import 'package:briskers_app/services/local_job_tasks_lab_store.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sanitized Richard fixture contains two cars and labor only', () {
    expect(BriskersLabFixture.customerName, 'Richard Goff');
    expect(BriskersLabFixture.vehicles.length, 2);
    expect(BriskersLabFixture.employees.any(
      (employee) => employee['role'] == 'secretary'), isTrue);
    expect(BriskersLabFixture.vehicles[0]['model'], 'Equus');
    expect(BriskersLabFixture.vehicles[1]['model'], 'Sonata');
    expect(BriskersLabFixture.invoiceNumber, '6342');
    final tasks = LocalJobTasksLabStore.laborLines(
      BriskersLabFixture.invoice);
    expect(tasks.length, 4);
    expect(tasks[0]['quantity'], 4.0);
    expect(tasks[1]['quantity'], 0.5);
    expect(tasks[2]['quantity'], 1.5);
    expect(tasks[3]['quantity'], 0.8);
    final text = File('lib/tasks_lab/fixture.dart').readAsStringSync();
    for (final forbidden in [
      'phone_raw', 'email', 'vin_raw', 'billing_address',
      'unit_price', 'payment_allocations',
      'coensavcnuwuqaeszohb',
    ]) {
      expect(text, isNot(contains(forbidden)));
    }
  });

  test('Test Android build has distinct package and offline entrypoint', () {
    // CI creates a generated Flutter shell one level below the checkout.
    // Local tests may also run directly from the repository root.
    final direct = File('.github/workflows/android-tasks-test.yml');
    final file = direct.existsSync()
        ? direct : File('../.github/workflows/android-tasks-test.yml');
    final workflow = file.readAsStringSync();
    expect(workflow, contains('applicationId = "com.briskers.tasks_lab"'));
    expect(workflow, contains('cp ../lib/tasks_lab_main.dart ./lib/main.dart'));
    expect(workflow, contains('Briskers Tasks TEST'));
    expect(workflow, contains('Verify APK is signed'));
    expect(workflow, contains('require_candidate_checks.py'));
    final main = File('lib/tasks_lab_main.dart').readAsStringSync();
    expect(main, isNot(contains('supabase_flutter')));
    expect(main, isNot(contains('BriskersApi')));
    expect(main, isNot(contains('Supabase.initialize')));
    expect(main, contains('LocalJobTasksLabStore'));
    expect(main, contains('bottomNavigationBar: _bottomNav()'));
    expect(main, contains('BriskersModuleDock('));
    expect(main, contains('onLongPressed: (index, globalPosition)'));
    expect(main, contains("if (index == 2 || index == 7) {"));
    expect(main, contains('jobDetailsOpen'));
    expect(main, contains('Assign main job mechanic'));
    expect(main, contains('Add Task · Not on Invoice'));
    expect(main, contains('Payroll hours can be adjusted independently.'));
    expect(main, isNot(contains('Assigned hours cannot exceed')));

    expect(main, contains('_addRecheckWork'));
    expect(main, contains('Record TEST payment / advance'));
    expect(main, contains('store.payrollTestPayments('));
    expect(main, contains('store.recordLabPayrollPayment('));
    expect(main, contains('earnedPayrollPreviewHours'));

    expect(main, contains('Mark all tasks Done'));
    // The bulk Done action belongs on Tasks, not as a duplicate Job Detail row.
    final jobDetailSection = main.split('Widget _jobPage() {').last
      .split('Widget _taskList({bool history = false})').first;
    final taskListSection = main.split('Widget _taskList({bool history = false})').last
      .split('Widget _payrollPage()').first;
    expect(jobDetailSection, isNot(contains("'Mark all tasks Done'")));
    expect(jobDetailSection, contains("'Tasks (TEST)'"));
    expect(jobDetailSection, contains("'Work Log'"));
    expect(taskListSection, contains("'Mark all tasks Done'"));
    expect(main, contains('Complete job J-24?'));
    expect(main, contains('_jobStatusControl()'));
    expect(main, contains('onSelected: _changeJobStatus'));
    expect(main, contains('All tasks are Done'));
    expect(main, contains("subtitle: 'Completion history · Read-only'"));
    // Font hierarchy: payroll hours are prominent; Work Log allocations
    // remain legible in the compact, read-only ledger.
    final payrollSection = main.split('Widget _payrollPage() {').last
      .split('Widget _settingsPage()').first;
    expect(payrollSection, contains('fontSize: 22'));
    expect(payrollSection, contains('fontWeight: FontWeight.w800'));
    final fullLogSection = main.split('Widget _workLogPage() {').last
      .split('Widget _taskList({bool history = false})').first;
    expect(fullLogSection, contains('fontSize: 14.5'));
    expect(fullLogSection, contains('fontWeight: FontWeight.w600'));
    expect(main, contains('Widget _workLogPage()'));
    // Work Log is a passive chronological ledger: no edit pencil, no onTap.
    final logSection = main.split('Widget _workLogPage() {').last
      .split('Widget _taskList({bool history = false})').first;
    expect(logSection, contains("DateFormat('yyyy-MM-dd')"));
    expect(logSection, contains("DateFormat('h:mm a')"));
    expect(logSection, contains('records.sort('));
    expect(logSection, contains('Previous completion'));
    expect(logSection, isNot(contains('Icons.edit_outlined')));
    expect(logSection, isNot(contains('onTap:')));
    expect(logSection, isNot(contains('_editTask(')));
    final taskCardSection = main.split('Widget _taskCard(').last
      .split('Future<void> _editTask(').first;
    expect(taskCardSection, contains('Icons.edit_outlined'));
    expect(taskCardSection, contains('onTap: () => _editTask(task)'));
    expect(main, contains('if (history) return _workLogPage();'));

    expect(main, contains('_confirmCompleteAllTasks'));
    expect(main, contains('completeConfirmedJobTasks('));
    expect(main, contains('Assign invoice labor'));
    expect(main, contains('onTap: () => _editInvoiceLabor(task)'));
    expect(main, contains('allocationsByLine'));

    expect(main, contains('_assignLeadMechanic'));
    expect(main, contains('Main job mechanic'));

    expect(main, contains('menuAnchorX - 90'));
    expect(main, contains("'Pre-inspection'"));
    expect(main, contains("'Customer Complaint'"));
    expect(main, contains("'Work Performed'"));
    expect(main, contains("'Tasks (TEST)'"));
    expect(main, contains("'New functions being tested'"));
    expect(main, contains("page == 0 ? null : AppBar("));
    expect(main, contains('_verticalMenu(int index)'));
    expect(main, contains('Edit employee names'));
    expect(main, contains("if (employee['role'] != 'secretary')"));
    expect(main, isNot(contains('_navRail()')));
    final dock = File('lib/widgets/briskers_module_dock.dart')
      .readAsStringSync();
    expect(dock, contains('this.onLongPressed,'));
    expect(dock, contains('onLongPressStart: widget.onLongPressed == null'));
    expect(dock, contains('details.globalPosition'));
  });

  test('Unbilled recheck task increases only new earned hours and not invoice',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    const shop = BriskersLabFixture.businessId;
    const job = BriskersLabFixture.jobId;
    const invoice = BriskersLabFixture.invoiceId;
    try {
      await store.reconcileDocument(
        businessId: shop, jobId: job, documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice));
      await store.saveLeadMechanic(shop, job, 'lab-kam');
      final originals = await store.list(shop, job);
      final identities = [for (final t in originals) {
        'document_id': t['document_id'].toString(),
        'line_id': t['line_id'].toString(),
      }];
      await store.changeJobStatus(
        businessId: shop, jobId: job, statusCode: 'completed',
        confirmedTasks: identities);
      await store.changeJobStatus(
        businessId: shop, jobId: job, statusCode: 'needs_recheck');
      final originalEarned = await store.earnedHoursPreview(shop, job);
      final line = await store.addRecheckTask(
        businessId: shop, jobId: job,
        description: 'Replace leaking connector again', hours: 1.5,
      );
      var extra = (await store.list(shop, job)).singleWhere(
        (t) => t['line_id'] == line);
      expect(extra['document_id'], LocalJobTasksLabStore.recheckDocumentId);
      expect(extra['employee_id'], 'lab-kam');
      expect(extra['status'], 'planned');
      expect(extra['source_invoice_hours'], 1.5);
      expect((await store.list(shop, job)).length, 5);
      await store.saveAllocations(
        businessId: shop, jobId: job,
        documentId: LocalJobTasksLabStore.recheckDocumentId,
        lineId: line,
        hoursByEmployee: {'lab-chris': 1.0, 'lab-kam': 0.5});
      // A recheck can also receive extra paid time beyond its initial 1.5.
      await store.saveAllocations(
        businessId: shop, jobId: job,
        documentId: LocalJobTasksLabStore.recheckDocumentId,
        lineId: line,
        hoursByEmployee: {'lab-chris': 1.3, 'lab-kam': 0.5});
      final extraAlloc = (await store.list(shop, job)).singleWhere(
        (t) => t['line_id'] == line);
      expect(extraAlloc['source_invoice_hours'], 1.5);
      expect(extraAlloc['payroll_hours'], 1.8);
      // Restore the initial allocation for later assertions.
      await store.saveAllocations(
        businessId: shop, jobId: job,
        documentId: LocalJobTasksLabStore.recheckDocumentId,
        lineId: line,
        hoursByEmployee: {'lab-chris': 1.0, 'lab-kam': 0.5});
      expect(await store.earnedHoursPreview(shop, job), originalEarned);
      await store.editTask(
        businessId: shop, jobId: job,
        documentId: LocalJobTasksLabStore.recheckDocumentId,
        lineId: line, status: 'done');
      final earned = await store.earnedHoursPreview(shop, job);
      expect(earned['lab-chris'], (originalEarned['lab-chris'] ?? 0) + 1.0);
      expect(earned['lab-kam'], (originalEarned['lab-kam'] ?? 0) + 0.5);
      expect((await store.list(shop, job)).where(
        (t) => t['document_id'] == invoice).length, 4);
      await store.reconcileDocument(
        businessId: shop, jobId: job, documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice));
      extra = (await store.list(shop, job)).singleWhere(
        (t) => t['line_id'] == line);
      expect(extra['status'], 'done');
      expect(extra['source_missing'], 0);
      expect((await store.priorCompletions(shop, job)).length, 4);
      expect(await store.list('production-company', job), isEmpty);
    } finally {
      await db.close();
    }
  });

  test('Test payroll rates, partial payments and advances persist separately',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    const shop = BriskersLabFixture.businessId;
    const job = BriskersLabFixture.jobId;
    const invoice = BriskersLabFixture.invoiceId;
    try {
      await store.reconcileDocument(
        businessId: shop, jobId: job, documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice));
      await store.saveLeadMechanic(shop, job, 'lab-chris');
      await store.setPayrollRate(
        businessId: shop, employeeId: 'lab-chris', centsPerHour: 4000);
      expect((await store.payrollRates(shop))['lab-chris'], 4000);
      final when = DateTime(2026, 10, 19);
      await store.recordLabPayrollPayment(
        businessId: shop, employeeId: 'lab-chris',
        cents: 5000, kind: 'advance', method: 'cash',
        note: 'Before job is done', paidAt: when);
      expect(await store.earnedHoursPreview(shop, job), isEmpty);
      var payments = await store.payrollTestPayments(shop);
      expect(payments.length, 1);
      expect(payments.single['kind'], 'advance');
      expect(payments.single['cents'], 5000);
      expect(payments.single['paid_at'], when.millisecondsSinceEpoch);

      await store.editTask(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-spark-plugs', status: 'done');
      final earned = await store.earnedHoursPreview(shop, job);
      expect(earned['lab-chris'], 0.5);
      await store.recordLabPayrollPayment(
        businessId: shop, employeeId: 'lab-chris',
        cents: 1500, kind: 'pay', method: 'check',
        note: 'Partial after completion', paidAt: when);
      payments = await store.payrollTestPayments(shop);
      expect(payments.length, 2);
      expect(payments.fold<int>(0,
        (sum, item) => sum + (item['cents'] as int)), 6500);
      expect((earned['lab-chris']! * 4000).round(), 2000);
      expect(await store.payrollTestPayments('production-company'), isEmpty);
      expect(await store.payrollRates('production-company'), isEmpty);
      await expectLater(store.recordLabPayrollPayment(
        businessId: shop, employeeId: 'lab-chris',
        cents: -2, kind: 'pay', method: 'cash', note: '', paidAt: when),
        throwsArgumentError);
    } finally {
      await db.close();
    }
  });

  test('Needs Recheck preserves initial payroll without double counting',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    const shop = BriskersLabFixture.businessId;
    const job = BriskersLabFixture.jobId;
    const invoice = BriskersLabFixture.invoiceId;
    try {
      final lines = LocalJobTasksLabStore.laborLines(BriskersLabFixture.invoice);
      await store.reconcileDocument(businessId: shop, jobId: job,
        documentId: invoice, laborLines: lines);
      await store.saveLeadMechanic(shop, job, 'lab-kam');
      await store.saveAllocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-transmission',
        hoursByEmployee: {'lab-chris': 1.0, 'lab-kam': 0.5},
      );
      await store.saveAllocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-differential',
        hoursByEmployee: {'lab-kam': 0.5, 'lab-raz': 0.3},
      );
      final ack = [
        for (final task in await store.list(shop, job))
          {
            'document_id': task['document_id'].toString(),
            'line_id': task['line_id'].toString(),
          },
      ];
      await store.changeJobStatus(businessId: shop, jobId: job,
        statusCode: 'completed', confirmedTasks: ack);
      final original = await store.earnedHoursPreview(shop, job);
      expect(original['lab-kam'], closeTo(5.5, 0.000001));
      expect(original['lab-chris'], closeTo(1.0, 0.000001));
      expect(original['lab-raz'], closeTo(0.3, 0.000001));

      await store.changeJobStatus(
        businessId: shop, jobId: job, statusCode: 'needs_recheck');
      expect(await store.jobStatus(shop, job), 'needs_recheck');
      expect((await store.list(shop, job)).every((t) =>
        t['status'] == 'in_progress'), isTrue);
      expect(await store.earnedHoursPreview(shop, job), original);
      final frozen = await store.preservedPayrollPreview(shop, job);
      expect(frozen.taskKeys.length, 4);
      expect(frozen.hoursByMechanic, original);

      // Editing and re-completing the SAME task is not new payroll.
      await store.saveAllocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-transmission',
        hoursByEmployee: {'lab-raz': 1.5},
      );
      await store.editTask(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-transmission', status: 'done',
      );
      expect(await store.earnedHoursPreview(shop, job), original);
      await store.changeJobStatus(businessId: shop, jobId: job,
        statusCode: 'completed', confirmedTasks: ack);
      await store.changeJobStatus(businessId: shop, jobId: job,
        statusCode: 'in_progress');
      expect(await store.earnedHoursPreview(shop, job), original);
      expect((await store.priorCompletions(shop, job)).length, 8);

      // Separate new recheck work can earn a distinct, additional credit.
      await store.reconcileDocument(businessId: shop, jobId: job,
        documentId: invoice, laborLines: [
          ...lines,
          {'id': 'lab-new-recheck', 'line_kind': 'item', 'name': 'Labor',
           'description': 'Additional recheck work', 'quantity': 0.4},
        ]);
      await store.saveAllocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-new-recheck',
        hoursByEmployee: {'lab-chris': 0.4},
      );
      await store.editTask(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-new-recheck', status: 'done',
      );
      final withRecheck = await store.earnedHoursPreview(shop, job);
      expect(withRecheck['lab-kam'], closeTo(5.5, 0.000001));
      expect(withRecheck['lab-raz'], closeTo(0.3, 0.000001));
      expect(withRecheck['lab-chris'], closeTo(1.4, 0.000001));
      expect(await store.earnedHoursPreview('another-shop', job), isEmpty);
    } finally {
      await db.close();
    }
  });

  test('Earlier test Work Log completions migrate to preserved payroll',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    const shop = BriskersLabFixture.businessId;
    const job = BriskersLabFixture.jobId;
    const invoice = BriskersLabFixture.invoiceId;
    try {
      await store.reconcileDocument(
        businessId: shop, jobId: job, documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice));
      await db.customStatement('''
        INSERT INTO local_task_completion_history_lab
          (business_id, job_id, document_id, line_id, description,
           employee_id, payroll_hours, assignment_summary,
           completed_at, reopened_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [shop, job, invoice, 'lab-differential',
        'Replace rear differential fluid', null, 0.9,
        'lab-kam: 0.5 hrs, lab-raz: 0.4 hrs',
        1761000000000, 1761000100000]);
      final before = await store.earnedHoursPreview(shop, job);
      expect(before['lab-kam'], closeTo(0.5, 0.000001));
      expect(before['lab-raz'], closeTo(0.4, 0.000001));
      expect((await store.preservedPayrollPreview(shop, job)).taskKeys.length, 1);
      // Later recheck snapshots cannot overwrite the first completed work.
      await db.customStatement('''
        INSERT INTO local_task_completion_history_lab
          (business_id, job_id, document_id, line_id, description,
           employee_id, payroll_hours, assignment_summary,
           completed_at, reopened_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [shop, job, invoice, 'lab-differential',
        'Replace rear differential fluid', 'lab-chris', 0.8,
        'lab-chris: 0.8 hrs', 1761000500000, 1761000600000]);
      expect(await store.earnedHoursPreview(shop, job), before);
    } finally {
      await db.close();
    }
  });

  test('Job status and task transitions share one persisted workflow',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    const shop = BriskersLabFixture.businessId;
    const job = BriskersLabFixture.jobId;
    const invoice = BriskersLabFixture.invoiceId;
    List<Map<String, String>> confirmations(List<Map<String, dynamic>> rows) =>
        [for (final task in rows) {
          'document_id': task['document_id'].toString(),
          'line_id': task['line_id'].toString(),
        }];
    try {
      await store.reconcileDocument(
        businessId: shop, jobId: job, documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice),
      );
      expect(await store.jobStatus(shop, job), 'open');
      await store.saveLeadMechanic(shop, job, 'lab-kam');
      await store.editTask(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-valve-covers', status: 'in_progress',
      );
      expect(await store.jobStatus(shop, job), 'in_progress');

      await store.changeJobStatus(
        businessId: shop, jobId: job, statusCode: 'pending_approval');
      await store.editTask(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-spark-plugs', status: 'in_progress');
      expect(await store.jobStatus(shop, job), 'pending_approval');
      await store.changeJobStatus(
        businessId: shop, jobId: job, statusCode: 'waiting_parts');
      await store.editTask(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-valve-covers', status: 'done');
      expect(await store.jobStatus(shop, job), 'waiting_parts');
      await store.changeJobStatus(
        businessId: shop, jobId: job, statusCode: 'needs_recheck');
      await store.editTask(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-differential', status: 'in_progress');
      expect(await store.jobStatus(shop, job), 'needs_recheck');

      final active = await store.list(shop, job);
      await expectLater(
        store.changeJobStatus(
          businessId: shop, jobId: job, statusCode: 'completed',
          confirmedTasks: confirmations(active).take(2).toList(),
        ),
        throwsStateError,
      );
      expect(await store.jobStatus(shop, job), 'needs_recheck');
      expect((await store.list(shop, job)).where(
        (task) => task['status'] == 'done').length, 1);

      final previouslyDone = active.singleWhere(
        (task) => task['line_id'] == 'lab-valve-covers');
      final earlierTime = previouslyDone['completed_at'];
      await store.saveAllocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-transmission',
        hoursByEmployee: {'lab-kam': 1.0, 'lab-chris': 0.5},
      );
      final changed = await store.changeJobStatus(
        businessId: shop, jobId: job, statusCode: 'completed',
        confirmedTasks: confirmations(active),
      );
      expect(changed, 3);
      expect(await store.jobStatus(shop, job), 'completed');
      final done = await store.list(shop, job);
      expect(done.every((task) => task['status'] == 'done'), isTrue);
      expect(done.singleWhere(
        (task) => task['line_id'] == 'lab-valve-covers')['completed_at'],
        earlierTime);
      await expectLater(
        store.editTask(
          businessId: shop, jobId: job, documentId: invoice,
          lineId: 'lab-spark-plugs', status: 'in_progress',
        ),
        throwsStateError,
      );

      final reopened = await store.changeJobStatus(
        businessId: shop, jobId: job, statusCode: 'in_progress');
      expect(reopened, 4);
      expect(await store.jobStatus(shop, job), 'in_progress');
      final pending = await store.list(shop, job);
      expect(pending.every((task) => task['status'] == 'in_progress'), isTrue);
      expect(pending.every((task) => task['completed_at'] == null), isTrue);
      final archive = await store.priorCompletions(shop, job);
      expect(archive.length, 4);
      expect(archive.singleWhere(
        (task) => task['line_id'] == 'lab-valve-covers')['completed_at'],
        earlierTime);
      expect(archive.singleWhere(
        (task) => task['line_id'] == 'lab-transmission')
          ['assignment_summary'].toString(), contains('lab-chris'));
      expect((await store.allocations(businessId: shop, jobId: job,
        documentId: invoice, lineId: 'lab-transmission')).length, 2);
      expect(await store.leadMechanic(shop, job), 'lab-kam');
      expect(await store.jobStatus('another-shop', job), 'open');
      expect(await store.priorCompletions('another-shop', job), isEmpty);
    } finally {
      await db.close();
    }
  });

  test('Job lead auto-fills unassigned tasks and preserves labor overrides',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    const shop = BriskersLabFixture.businessId;
    const job = BriskersLabFixture.jobId;
    const invoice = BriskersLabFixture.invoiceId;
    try {
      await store.reconcileDocument(businessId: shop, jobId: job,
        documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice));
      await store.saveLeadMechanic(shop, job, 'lab-kam');
      var tasks = await store.list(shop, job);
      expect(tasks.every((row) => row['employee_id'] == 'lab-kam'), isTrue);
      await store.saveAllocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-transmission',
        hoursByEmployee: {'lab-chris': 1.5},
      );
      await store.saveLeadMechanic(shop, job, 'lab-chris');
      tasks = await store.list(shop, job);
      expect(tasks.singleWhere((row) => row['line_id'] == 'lab-valve-covers')
        ['employee_id'], 'lab-chris');
      expect((await store.allocations(businessId: shop, jobId: job,
        documentId: invoice, lineId: 'lab-transmission'))
        .single['employee_id'], 'lab-chris');
      await store.reconcileDocument(businessId: shop, jobId: job,
        documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice));
      expect((await store.allocations(businessId: shop, jobId: job,
        documentId: invoice, lineId: 'lab-transmission')).length, 1);
      expect(await store.leadMechanic('another-shop', job), isNull);
    } finally {
      await db.close();
    }
  });

  test('Book time defaults payroll but permits owner-paid extra hours',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    const shop = BriskersLabFixture.businessId;
    const job = BriskersLabFixture.jobId;
    const invoice = BriskersLabFixture.invoiceId;
    const line = 'lab-differential'; // Source billed quantity is 0.8 hr.
    try {
      await store.reconcileDocument(
        businessId: shop, jobId: job, documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice),
      );
      final initially = (await store.list(shop, job))
          .singleWhere((row) => row['line_id'] == line);
      expect(initially['source_invoice_hours'], 0.8);
      expect(initially['payroll_hours'], 0.8); // Default equality.

      await store.saveAllocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: line,
        hoursByEmployee: {'lab-kam': 0.5, 'lab-raz': 0.2},
      );
      final partial = await store.allocations(
        businessId: shop, jobId: job, documentId: invoice, lineId: line);
      expect(partial.fold<double>(0,
          (sum, item) => sum + (item['hours'] as num).toDouble()), 0.7);

      // Owner can voluntarily pay more than the billed 0.8 hours.
      await store.saveAllocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: line,
        hoursByEmployee: {'lab-kam': 0.9, 'lab-raz': 0.5},
      );
      final extra = await store.allocations(
        businessId: shop, jobId: job, documentId: invoice, lineId: line);
      expect(extra.length, 2);
      expect(extra.fold<double>(0,
          (sum, item) => sum + (item['hours'] as num).toDouble()), 1.4);
      final withExtra = (await store.list(shop, job))
          .singleWhere((row) => row['line_id'] == line);
      expect(withExtra['source_invoice_hours'], 0.8);
      expect(withExtra['payroll_hours'], 1.4);

      // Validate input safety, not a fabricated book-time cap.
      await expectLater(
        store.saveAllocations(
          businessId: shop, jobId: job, documentId: invoice,
          lineId: line,
          hoursByEmployee: {'lab-kam': -0.1},
        ),
        throwsArgumentError,
      );
      await expectLater(
        store.saveAllocations(
          businessId: shop, jobId: job, documentId: invoice,
          lineId: line,
          hoursByEmployee: {'lab-kam': double.infinity},
        ),
        throwsArgumentError,
      );

      await store.editTask(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: line, status: 'done',
      );
      final earned = await store.earnedHoursPreview(shop, job);
      expect(earned['lab-kam'], 0.9);
      expect(earned['lab-raz'], 0.5);

      // Invoice reconciliation must not recalculate or erase payroll bonus.
      await store.reconcileDocument(
        businessId: shop, jobId: job, documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice),
      );
      final afterReconcile = (await store.list(shop, job))
          .singleWhere((row) => row['line_id'] == line);
      expect(afterReconcile['source_invoice_hours'], 0.8);
      expect(afterReconcile['payroll_hours'], 1.4);
      expect(await store.earnedHoursPreview(shop, job), earned);
    } finally {
      await db.close();
    }
  });

  test('Existing test-phone task table gains billed-hours column safely',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    try {
      // Emulate the prior installed table schema without the new column.
      await db.customStatement('''
        CREATE TABLE local_job_tasks_lab (
          business_id TEXT NOT NULL, job_id TEXT NOT NULL,
          document_id TEXT NOT NULL, line_id TEXT NOT NULL,
          source_description TEXT NOT NULL, custom_description TEXT,
          employee_id TEXT, payroll_hours REAL,
          status TEXT NOT NULL DEFAULT 'planned',
          completed_at INTEGER, source_missing INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY(business_id, job_id, document_id, line_id)
        )
      ''');
      await store.reconcileDocument(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        documentId: BriskersLabFixture.invoiceId,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice),
      );
      final rows = await store.list(
        BriskersLabFixture.businessId, BriskersLabFixture.jobId);
      expect(rows.length, 4);
      expect(rows.first['source_invoice_hours'], isNotNull);
    } finally {
      await db.close();
    }
  });

  test('Confirming all tasks Done preserves earlier Done and split payroll',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    const shop = BriskersLabFixture.businessId;
    const job = BriskersLabFixture.jobId;
    const invoice = BriskersLabFixture.invoiceId;
    try {
      await store.reconcileDocument(
        businessId: shop, jobId: job, documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice),
      );
      await store.saveLeadMechanic(shop, job, 'lab-kam');
      await store.editTask(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-valve-covers', status: 'done',
      );
      final firstDone = (await store.list(shop, job)).singleWhere(
        (task) => task['line_id'] == 'lab-valve-covers');
      final initialStamp = firstDone['completed_at'];
      expect(initialStamp, isA<int>());
      await store.saveAllocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-transmission',
        hoursByEmployee: {'lab-chris': 1.0, 'lab-kam': 0.5},
      );
      final original = await store.list(shop, job);
      final ids = [
        for (final task in original)
          {
            'document_id': task['document_id'].toString(),
            'line_id': task['line_id'].toString(),
          },
      ];
      // A stale/incomplete confirmation must not change any row.
      await expectLater(
        store.completeConfirmedJobTasks(
          businessId: shop, jobId: job,
          confirmedTasks: ids.take(2).toList(),
        ),
        throwsStateError,
      );
      expect((await store.list(shop, job)).where(
        (task) => task['status'] == 'done').length, 1);

      final count = await store.completeConfirmedJobTasks(
        businessId: shop, jobId: job, confirmedTasks: ids);
      expect(count, 3);
      final finished = await store.list(shop, job);
      expect(finished.length, 4);
      expect(finished.every((task) => task['status'] == 'done'), isTrue);
      expect(finished.every((task) => task['completed_at'] is int), isTrue);
      expect(finished.singleWhere(
        (task) => task['line_id'] == 'lab-valve-covers')['completed_at'],
        initialStamp);
      expect((await store.allocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-transmission')).length, 2);
      expect(await store.leadMechanic(shop, job), 'lab-kam');
      expect(await store.completeConfirmedJobTasks(
        businessId: shop, jobId: job, confirmedTasks: ids), 0);
      final persisted = await store.list(shop, job);
      expect(persisted.singleWhere(
        (task) => task['line_id'] == 'lab-valve-covers')['completed_at'],
        initialStamp);
      expect(await store.list('production-company', job), isEmpty);
    } finally {
      await db.close();
    }
  });

  test('Task assignments and nicknames persist in a local SQLite test DB',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    try {
      await store.reconcileDocument(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        documentId: BriskersLabFixture.invoiceId,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice),
      );
      expect((await store.list(BriskersLabFixture.businessId,
          BriskersLabFixture.jobId)).length, 4);
      await store.editTask(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        documentId: BriskersLabFixture.invoiceId,
        lineId: 'lab-valve-covers',
        employeeId: 'lab-kam', editEmployee: true,
        status: 'done', description: 'Finished valve covers',
        editDescription: true, hours: 4, editHours: true,
      );
      await store.editTask(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        documentId: BriskersLabFixture.invoiceId,
        lineId: 'lab-transmission',
        employeeId: 'lab-chris', editEmployee: true,
        hours: 1.5, editHours: true,
      );
      await store.saveAllocations(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        documentId: BriskersLabFixture.invoiceId,
        lineId: 'lab-transmission',
        hoursByEmployee: {'lab-chris': 1.0, 'lab-kam': 0.5},
      );
      final split = await store.allocations(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        documentId: BriskersLabFixture.invoiceId,
        lineId: 'lab-transmission',
      );
      expect(split.length, 2);
      expect(split.fold<double>(0, (n, a) => n + (a['hours'] as num).toDouble()), 1.5);
      final splitTask = (await store.list(
        BriskersLabFixture.businessId, BriskersLabFixture.jobId))
        .singleWhere((task) => task['line_id'] == 'lab-transmission');
      expect(splitTask['employee_id'], isNull);
      expect(splitTask['payroll_hours'], 1.5);
      await store.saveAllocations(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        documentId: BriskersLabFixture.invoiceId,
        lineId: 'lab-transmission',
        hoursByEmployee: {'lab-chris': 1.5},
      );
      expect((await store.allocations(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        documentId: BriskersLabFixture.invoiceId,
        lineId: 'lab-transmission')).length, 1);
      await store.saveLeadMechanic(
        BriskersLabFixture.businessId, BriskersLabFixture.jobId, 'lab-kam');
      expect(await store.leadMechanic(
        BriskersLabFixture.businessId, BriskersLabFixture.jobId),
        'lab-kam');
      // Reassigning the job lead must never rewrite labor-line mechanics.
      await store.saveLeadMechanic(
        BriskersLabFixture.businessId, BriskersLabFixture.jobId, 'lab-chris');
      expect(await store.leadMechanic(
        BriskersLabFixture.businessId, BriskersLabFixture.jobId),
        'lab-chris');
      expect(await store.leadMechanic(
        'another-test-shop', BriskersLabFixture.jobId), isNull);
      await store.saveNickname(
        BriskersLabFixture.businessId, 'lab-kam', 'Kam');
      await store.saveEmployeeProfile(
        businessId: BriskersLabFixture.businessId,
        employeeId: 'lab-secretary',
        fullName: 'Front Desk Assistant',
        displayName: 'Front Desk',
      );
      final rows = await store.list(
          BriskersLabFixture.businessId, BriskersLabFixture.jobId);
      final valve = rows.singleWhere((r) =>
          r['line_id'] == 'lab-valve-covers');
      final trans = rows.singleWhere((r) =>
          r['line_id'] == 'lab-transmission');
      expect(valve['employee_id'], 'lab-chris');
      expect(valve['custom_description'], 'Finished valve covers');
      expect(valve['status'], 'done');
      expect(valve['completed_at'], isA<int>());
      expect(trans['employee_id'], 'lab-chris');
      expect((await store.nicknames(
          BriskersLabFixture.businessId))['lab-kam'], 'Kam');
      expect((await store.nicknames(
          BriskersLabFixture.businessId))['lab-secretary'], 'Front Desk');
      expect((await store.fullNames(
          BriskersLabFixture.businessId))['lab-secretary'],
          'Front Desk Assistant');
      expect(await store.list('production-company',
          BriskersLabFixture.jobId), isEmpty);
    } finally {
      await db.close();
    }
  });
}
