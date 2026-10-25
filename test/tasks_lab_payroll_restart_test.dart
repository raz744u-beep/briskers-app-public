import 'dart:io';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_tasks_lab_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
