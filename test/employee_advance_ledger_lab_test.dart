import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/tasks_lab/employee_advance_ledger.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Opening, repayments, full repayment and no overpayment', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final ledger = LabAdvanceLedger(db);
    try {
      await ledger.setOpening(
        businessId: 'shop-test', employeeId: 'chris-test',
        openingCents: 200000,
      );
      await ledger.repay(
        businessId: 'shop-test', employeeId: 'chris-test',
        cents: 20000, method: 'Payroll deduction',
        date: DateTime(2026, 10, 25),
      );
      final first = await ledger.read('shop-test', 'chris-test');
      expect(first.openingCents, 200000);
      expect(first.remainingCents, 180000);
      expect(first.repayments.single['remaining_after_cents'], 180000);
      await expectLater(ledger.repay(
        businessId: 'shop-test', employeeId: 'chris-test',
        cents: 180001, method: 'Cash', date: DateTime(2026, 10, 25),
      ), throwsStateError);
      await expectLater(ledger.setOpening(
        businessId: 'shop-test', employeeId: 'chris-test',
        openingCents: 250000,
      ), throwsStateError);
      await ledger.repay(
        businessId: 'shop-test', employeeId: 'chris-test',
        cents: 180000, method: 'Zelle', date: DateTime(2026, 10, 26),
      );
      expect((await ledger.read('shop-test', 'chris-test')).remainingCents, 0);
      await expectLater(ledger.repay(
        businessId: 'shop-test', employeeId: 'chris-test',
        cents: 1, method: 'Zelle', date: DateTime(2026, 10, 26),
      ), throwsStateError);
    } finally {
      await db.close();
    }
  });

  test('Repayment ledger is isolated per shop and employee', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final ledger = LabAdvanceLedger(db);
    try {
      await ledger.setOpening(
        businessId: 'shop-a', employeeId: 'chris',
        openingCents: 15000,
      );
      expect((await ledger.read('shop-a', 'kam')).remainingCents, 0);
      expect((await ledger.read('shop-b', 'chris')).remainingCents, 0);
      await expectLater(ledger.repay(
        businessId: 'shop-b', employeeId: 'chris',
        cents: 100, method: 'Cash', date: DateTime(2026, 10, 25),
      ), throwsStateError);
      await expectLater(ledger.repay(
        businessId: 'shop-a', employeeId: 'chris',
        cents: 100, method: 'Wire', date: DateTime(2026, 10, 25),
      ), throwsArgumentError);
    } finally {
      await db.close();
    }
  });
}
