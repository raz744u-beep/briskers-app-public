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
      expect(valve['employee_id'], 'lab-kam');
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
