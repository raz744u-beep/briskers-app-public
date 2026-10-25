import 'dart:io';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_tasks_lab_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid payroll cannot be replayed after offline database restart', () async {
    final directory = await Directory.systemTemp.createTemp('briskers-paid-test-');
    final file = File('${directory.path}/paid.sqlite');
    const shop = 'synthetic-offline-paid';
    const employee = 'lab-chris';
    const week = '2026-10-19';
    try {
      final first = BriskersLocalDatabase(NativeDatabase(file));
      try {
        final store = LocalJobTasksLabStore(first);
        await LocalJobTasksLabStore.ensureTables(first);
        final job = await store.createSyntheticJobWithTask(
          businessId: shop, customerId: 'test-customer',
          vehicleId: 'test-car', description: 'Synthetic repair',
          hours: 2, employeeId: employee);
        final task = (await store.allTasks(shop)).single;
        await store.creditTestTaskHours(
          businessId: shop, employeeId: employee, jobId: job,
          documentId: task['document_id'].toString(),
          lineId: task['line_id'].toString(),
          weekStart: DateTime(2026, 10, 19),
          minutes: 120, totalEligibleMinutes: 120);
        await store.saveTestWeeklyPayrollDraft(
          businessId: shop, employeeId: employee,
          weekStart: week, selectedMinutes: 120);
        expect(await store.approveTestWeeklyPayroll(
          businessId: shop, employeeId: employee,
          weekStart: week, approvedBy: 'lab-owner'), isTrue);
        expect(await store.finalizeTestWeeklyPayrollPayment(
          businessId: shop, employeeId: employee,
          weekStart: week, cents: 8000, method: 'ach',
          paidAt: DateTime(2026, 10, 25), note: 'offline test'), isTrue);
      } finally {
        await first.close();
      }
      final reopened = BriskersLocalDatabase(NativeDatabase(file));
      try {
        final store = LocalJobTasksLabStore(reopened);
        final approvals = await store.testWeeklyPayrollApprovals(shop);
        expect(approvals.single['state'], 'paid');
        final payments = await store.payrollTestPayments(shop);
        expect(payments.length, 1);
        expect(payments.single['approval_week_start'], week);
        expect(payments.single['cents'], 8000);
        expect(payments.single['method'], 'ach');
        expect(await store.finalizeTestWeeklyPayrollPayment(
          businessId: shop, employeeId: employee,
          weekStart: week, cents: 8000, method: 'ach',
          paidAt: DateTime(2026, 10, 25), note: 'replay'), isFalse);
        expect((await store.payrollTestPayments(shop)).length, 1);
      } finally {
        await reopened.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('approved TEST payroll survives database close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp('briskers-payroll-test-');
    final file = File('${directory.path}/offline.sqlite');
    const shop = 'offline-test-only';
    const worker = 'lab-kam';
    try {
      final firstDb = BriskersLocalDatabase(NativeDatabase(file));
      try {
        final store = LocalJobTasksLabStore(firstDb);
        await LocalJobTasksLabStore.ensureTables(firstDb);
        await store.recordTestPayrollAdjustment(
          businessId: shop, employeeId: worker,
          weekStart: '2026-10-19', kind: 'bonus',
          signedCents: 1500, reason: 'Synthetic extra duty',
          approvedBy: 'lab-owner',
        );
        await store.recordTestPayrollAdjustment(
          businessId: shop, employeeId: worker,
          weekStart: '2026-10-19', kind: 'correction',
          signedCents: -200, reason: 'Synthetic correction',
          approvedBy: 'lab-owner',
        );
      } finally {
        await firstDb.close();
      }
      final reopenedDb = BriskersLocalDatabase(NativeDatabase(file));
      try {
        final store = LocalJobTasksLabStore(reopenedDb);
        final entries = await store.testPayrollAdjustments(shop);
        expect(entries.length, 2);
        expect(entries.fold<int>(
          0, (sum, entry) => sum + (entry['signed_cents'] as int)), 1300);
        expect(entries.every((entry) =>
          entry['approved_by'] == 'lab-owner'), isTrue);
        expect(await store.testPayrollAdjustments('another-shop'), isEmpty);
      } finally {
        await reopenedDb.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
