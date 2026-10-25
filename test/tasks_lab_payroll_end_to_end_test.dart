import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_tasks_lab_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline weekly payroll: task credit, approval and paid-once', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    const shop = 'isolated-test-only';
    const mechanic = 'lab-chris';
    final store = LocalJobTasksLabStore(db);
    try {
      final job = await store.createSyntheticJobWithTask(
        businessId: shop,
        customerId: 'synthetic-customer',
        vehicleId: 'synthetic-vehicle',
        description: 'Synthetic repair',
        hours: 3,
        employeeId: mechanic,
      );
      final tasks = await store.allTasks(shop);
      expect(tasks.length, 1);
      final task = tasks.single;
      expect(task['job_id'], job);
      final weekStart = DateTime(2026, 10, 19);
      await store.creditTestTaskHours(
        businessId: shop, employeeId: mechanic, jobId: job,
        documentId: task['document_id'].toString(),
        lineId: task['line_id'].toString(),
        weekStart: weekStart, minutes: 90, totalEligibleMinutes: 180,
      );
      expect(() => store.saveTestWeeklyPayrollDraft(
        businessId: shop, employeeId: mechanic,
        weekStart: '2026-10-19', selectedMinutes: 180,
      ), throwsStateError);
      await store.saveTestWeeklyPayrollDraft(
        businessId: shop, employeeId: mechanic,
        weekStart: '2026-10-19', selectedMinutes: 90,
      );
      expect(await store.approveTestWeeklyPayroll(
        businessId: shop, employeeId: mechanic,
        weekStart: '2026-10-19', approvedBy: 'test-owner',
      ), isTrue);
      expect(await store.approveTestWeeklyPayroll(
        businessId: shop, employeeId: mechanic,
        weekStart: '2026-10-19', approvedBy: 'test-owner',
      ), isFalse);
      expect(await store.finalizeTestWeeklyPayrollPayment(
        businessId: shop, employeeId: mechanic,
        weekStart: '2026-10-19', cents: 6000, method: 'zelle',
        paidAt: DateTime(2026, 10, 25), note: 'TEST',
      ), isTrue);
      expect(await store.finalizeTestWeeklyPayrollPayment(
        businessId: shop, employeeId: mechanic,
        weekStart: '2026-10-19', cents: 6000, method: 'zelle',
        paidAt: DateTime(2026, 10, 25), note: 'duplicate',
      ), isFalse);
      expect((await store.payrollTestPayments(shop)).length, 1);
      expect((await store.testWeeklyPayrollApprovals(shop)).single['state'], 'paid');
      expect((await store.testTaskHourCredits(shop)).single['paid_minutes'], 90);
      expect(await store.payrollTestPayments('other-shop'), isEmpty);
    } finally {
      await db.close();
    }
  });
}
