import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/shop_payroll_preview.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/test_payroll_credit_repository.dart';
import 'package:briskers_app/services/test_payroll_staging_repository.dart';
import 'package:briskers_app/services/test_payroll_atomic_commit.dart';

void main() {
  test('changed reserved credit ID rejects settlement even at same gross', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final credits = TestPayrollCreditRepository(database: db);
      final staging = TestPayrollStagingRepository(database: db);
      final settlement = TestPayrollAtomicCommit(database: db);
      for (final id in ['a', 'b']) {
        await credits.seedSyntheticCredit(
          businessId: 'sandbox',
          credit: ShopPayrollAllocation(
            id: id, employeeId: 'employee-1',
            hoursHundredths: 100, rateCentsPerHour: 4000,
            completed: true, alreadyPaid: false,
          ),
        );
      }
      const original = ShopPayrollAllocation(
        id: 'a', employeeId: 'employee-1',
        hoursHundredths: 100, rateCentsPerHour: 4000,
        completed: true, alreadyPaid: false,
      );
      await staging.stage(
        businessId: 'sandbox', owner: true,
        proposal: ShopPayrollPaymentProposal(
          operationId: 'op-a', employeeId: 'employee-1',
          allocationIds: ['a'], grossCents: 4000,
          repaymentCents: 0, method: 'Cash',
        ),
        credits: [original], outstandingAdvanceCents: 0,
      );
      await db.customStatement(
        "UPDATE test_payroll_staged_credits SET allocation_id = 'b' "
        "WHERE business_id = 'sandbox' AND operation_id = 'op-a'",
      );
      await expectLater(settlement.finalizeSynthetic(
        businessId: 'sandbox', operationId: 'op-a', owner: true,
      ), throwsStateError);
      final paid = await db.customSelect(
        'SELECT operation_id FROM test_payroll_paid_operations',
      ).get();
      expect(paid, isEmpty);
      expect(await credits.completedUnpaid(
        businessId: 'sandbox', employeeId: 'employee-1',
      ), hasLength(2));
    } finally {
      await db.close();
    }
  });

  test('TEST-only atomic settlement and idempotent replay', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final credits = TestPayrollCreditRepository(database: db);
      final staging = TestPayrollStagingRepository(database: db);
      final settlement = TestPayrollAtomicCommit(database: db);
      const work = ShopPayrollAllocation(
        id: 'work-1', employeeId: 'employee-1',
        hoursHundredths: 250, rateCentsPerHour: 4000,
        completed: true, alreadyPaid: false,
      );
      await credits.seedSyntheticCredit(businessId: 'sandbox', credit: work);
      await staging.stage(
        businessId: 'sandbox', owner: true,
        proposal: ShopPayrollPaymentProposal(
          operationId: 'op-1', employeeId: 'employee-1',
          allocationIds: ['work-1'], grossCents: 10000,
          repaymentCents: 2000, method: 'Zelle',
        ),
        credits: [work], outstandingAdvanceCents: 3000,
      );
      await expectLater(settlement.finalizeSynthetic(
        businessId: 'sandbox', operationId: 'op-1', owner: true),
        throwsStateError);
      await db.customStatement(
        'INSERT INTO test_payroll_advances '
        '(business_id, employee_id, balance_cents) VALUES (?, ?, ?)',
        ['sandbox', 'employee-1', 3000],
      );
      expect(await settlement.finalizeSynthetic(
        businessId: 'sandbox', operationId: 'op-1', owner: true), isTrue);
      expect(await settlement.finalizeSynthetic(
        businessId: 'sandbox', operationId: 'op-1', owner: true), isFalse);
      expect(await credits.completedUnpaid(
        businessId: 'sandbox', employeeId: 'employee-1'), isEmpty);
      final balance = await db.customSelect(
        'SELECT balance_cents FROM test_payroll_advances',
      ).get();
      expect(balance.single.read<int>('balance_cents'), 1000);
      final paid = await db.customSelect(
        'SELECT net_cents FROM test_payroll_paid_operations',
      ).get();
      expect(paid, hasLength(1));
      expect(paid.single.read<int>('net_cents'), 8000);
    } finally {
      await db.close();
    }
  });

  test('missing advance rolls back all synthetic paid flags', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final credits = TestPayrollCreditRepository(database: db);
      final staging = TestPayrollStagingRepository(database: db);
      final settlement = TestPayrollAtomicCommit(database: db);
      const work = ShopPayrollAllocation(
        id: 'work-1', employeeId: 'employee-1',
        hoursHundredths: 100, rateCentsPerHour: 4000,
        completed: true, alreadyPaid: false,
      );
      await credits.seedSyntheticCredit(businessId: 'sandbox', credit: work);
      await staging.stage(
        businessId: 'sandbox', owner: true,
        proposal: ShopPayrollPaymentProposal(
          operationId: 'op-2', employeeId: 'employee-1',
          allocationIds: ['work-1'], grossCents: 4000,
          repaymentCents: 1000, method: 'Cash',
        ),
        credits: [work], outstandingAdvanceCents: 1000,
      );
      await expectLater(settlement.finalizeSynthetic(
        businessId: 'sandbox', operationId: 'op-2', owner: true),
        throwsStateError);
      expect(await credits.completedUnpaid(
        businessId: 'sandbox', employeeId: 'employee-1'), hasLength(1));
      final paid = await db.customSelect(
        'SELECT operation_id FROM test_payroll_paid_operations',
      ).get();
      expect(paid, isEmpty);
    } finally {
      await db.close();
    }
  });
}
