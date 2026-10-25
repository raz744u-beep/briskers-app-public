import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_tasks_lab_store.dart';
import 'package:briskers_app/tasks_lab/fixture.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('weekly multi-select edits draft hours without paying money',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    const shop = BriskersLabFixture.businessId;
    const job = BriskersLabFixture.jobId;
    const invoice = BriskersLabFixture.invoiceId;
    const employee = 'lab-chris';
    final week = DateTime(2026, 10, 19);
    final laterWeek = DateTime(2026, 10, 26);
    try {
      await store.reconcileDocument(
        businessId: shop, jobId: job, documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice));
      await store.saveAllocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-transmission',
        hoursByEmployee: {employee: 1.5});
      await store.saveAllocations(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-differential',
        hoursByEmployee: {employee: 0.8});
      // Select two tasks in the same atomic operation.
      final firstTotal = await store.saveTestWeeklyTaskSelection(
        businessId: shop, employeeId: employee, weekStart: week,
        selections: [
          (jobId: job, documentId: invoice, lineId: 'lab-transmission',
            minutes: 60, eligibleMinutes: 90),
          (jobId: job, documentId: invoice, lineId: 'lab-differential',
            minutes: 30, eligibleMinutes: 48),
        ]);
      expect(firstTotal, 90);
      expect((await store.testTaskHourCredits(shop)).length, 2);
      // Edit the draft: reduce one task and deselect the other.
      final changed = await store.saveTestWeeklyTaskSelection(
        businessId: shop, employeeId: employee, weekStart: week,
        selections: [
          (jobId: job, documentId: invoice, lineId: 'lab-transmission',
            minutes: 30, eligibleMinutes: 90),
        ]);
      expect(changed, 30);
      var credits = await store.testTaskHourCredits(shop);
      expect(credits.length, 1);
      expect(credits.single['paid_minutes'], 30);
      // Unselected hours carry to the following week.
      await store.saveTestWeeklyTaskSelection(
        businessId: shop, employeeId: employee, weekStart: laterWeek,
        selections: [
          (jobId: job, documentId: invoice, lineId: 'lab-transmission',
            minutes: 60, eligibleMinutes: 90),
        ]);
      // No over-crediting across weeks.
      await expectLater(store.saveTestWeeklyTaskSelection(
        businessId: shop, employeeId: employee, weekStart: laterWeek,
        selections: [
          (jobId: job, documentId: invoice, lineId: 'lab-transmission',
            minutes: 61, eligibleMinutes: 90),
        ]), throwsStateError);
      expect((await store.testTaskHourCredits(shop)).length, 2);
      await store.saveTestWeeklyPayrollDraft(
        businessId: shop, employeeId: employee, weekStart: '2026-10-19',
        selectedMinutes: 30);
      expect(await store.approveTestWeeklyPayroll(
        businessId: shop, employeeId: employee, weekStart: '2026-10-19',
        approvedBy: 'lab-owner'), isTrue);
      await expectLater(store.saveTestWeeklyTaskSelection(
        businessId: shop, employeeId: employee, weekStart: week,
        selections: []), throwsStateError);
      credits = await store.testTaskHourCredits(shop);
      expect(credits.where((c) => c['week_start'] == '2026-10-19')
        .single['paid_minutes'], 30);
      expect(await store.payrollTestPayments(shop), isEmpty);
    } finally {
      await db.close();
    }
  });
}
