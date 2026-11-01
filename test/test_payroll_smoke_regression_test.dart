import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/shop_payroll_preview.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/test_payroll_credit_repository.dart';
import 'package:briskers_app/services/test_payroll_staging_repository.dart';
import 'package:briskers_app/services/test_payroll_atomic_commit.dart';

void main() {
  const work = ShopPayrollAllocation(
    id: 'work', employeeId: 'employee',
    hoursHundredths: 250, rateCentsPerHour: 4000,
    completed: true, alreadyPaid: false,
  );

  test('late payment insert failure rolls back paid flags and advance deduction', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final credits = TestPayrollCreditRepository(database: db);
    final staging = TestPayrollStagingRepository(database: db);
    final settlement = TestPayrollAtomicCommit(database: db);
    await credits.seedSyntheticCredit(businessId: 'sandbox', credit: work);
    await staging.stage(
      businessId: 'sandbox', owner: true,
      proposal: ShopPayrollPaymentProposal(
        operationId: 'op', employeeId: 'employee', allocationIds: ['work'],
        grossCents: 10000, repaymentCents: 2000, method: 'Cash TEST',
      ), credits: [work], outstandingAdvanceCents: 3000,
    );
    // Prepare the settlement tables through a safely rejected invocation.
    await expectLater(settlement.finalizeSynthetic(
      businessId: 'sandbox', operationId: 'op', owner: true,
      syntheticTestMode: true,
    ), throwsStateError);
    await db.customStatement(
      "INSERT INTO test_payroll_advances VALUES ('sandbox', 'employee', 3000)",
    );
    await db.customStatement("""
      CREATE TRIGGER reject_test_payment BEFORE INSERT ON test_payroll_paid_operations
      BEGIN SELECT RAISE(ABORT, 'injected payment write failure'); END
    """);
    await expectLater(settlement.finalizeSynthetic(
      businessId: 'sandbox', operationId: 'op', owner: true,
      syntheticTestMode: true,
    ), throwsA(isA<Exception>()));
    expect(await credits.completedUnpaid(
      businessId: 'sandbox', employeeId: 'employee',
    ), hasLength(1));
    expect((await db.customSelect(
      'SELECT balance_cents FROM test_payroll_advances',
    ).get()).single.read<int>('balance_cents'), 3000);
    expect(await db.customSelect('SELECT * FROM test_payroll_paid_operations').get(), isEmpty);
    await db.customStatement('DROP TRIGGER reject_test_payment');
    expect(await settlement.finalizeSynthetic(
      businessId: 'sandbox', operationId: 'op', owner: true,
      syntheticTestMode: true,
    ), isTrue);
    expect(await settlement.finalizeSynthetic(
      businessId: 'sandbox', operationId: 'op', owner: true,
      syntheticTestMode: true,
    ), isFalse);
    expect((await db.customSelect(
      'SELECT net_cents FROM test_payroll_paid_operations',
    ).get()).single.read<int>('net_cents'), 8000);
  });

  test('standalone in-memory restart resets synthetic work without a disk database', () async {
    final first = BriskersLocalDatabase(NativeDatabase.memory());
    await TestPayrollCreditRepository(database: first)
        .seedSyntheticCredit(businessId: 'sandbox', credit: work);
    await first.close();
    final restarted = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(restarted.close);
    expect(await TestPayrollCreditRepository(database: restarted).completedUnpaid(
      businessId: 'sandbox', employeeId: 'employee',
    ), isEmpty);
  });
}
