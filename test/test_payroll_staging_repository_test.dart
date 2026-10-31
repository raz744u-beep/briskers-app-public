import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/core/shop_payroll_preview.dart';
import 'package:briskers_app/services/test_payroll_staging_repository.dart';

void main() {
  test('two-credit staging rolls back if one credit is reserved', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final repository = TestPayrollStagingRepository(database: db);
      const first = ShopPayrollAllocation(
        id: 'a', employeeId: 'employee', hoursHundredths: 100,
        rateCentsPerHour: 4000, completed: true, alreadyPaid: false,
      );
      const second = ShopPayrollAllocation(
        id: 'b', employeeId: 'employee', hoursHundredths: 100,
        rateCentsPerHour: 4000, completed: true, alreadyPaid: false,
      );
      ShopPayrollPaymentProposal proposal(String op, List<String> ids, int gross) =>
          ShopPayrollPaymentProposal(
            operationId: op, employeeId: 'employee', allocationIds: ids,
            grossCents: gross, repaymentCents: 0, method: 'Zelle',
          );
      expect(await repository.stage(
        businessId: 'test-shop', proposal: proposal('first', ['b'], 4000),
        owner: true, credits: [second], outstandingAdvanceCents: 0,
      ), isTrue);
      await expectLater(repository.stage(
        businessId: 'test-shop',
        proposal: proposal('second', ['a', 'b'], 8000),
        owner: true, credits: [first, second], outstandingAdvanceCents: 0,
      ), throwsA(isA<Exception>()));
      final staged = await db.customSelect(
        'SELECT operation_id FROM test_payroll_staging',
      ).get();
      expect(staged, hasLength(1));
      final credits = await db.customSelect(
        'SELECT allocation_id FROM test_payroll_staged_credits',
      ).get();
      expect(credits, hasLength(1));
      expect(credits.single.read<String>('allocation_id'), 'b');
    } finally {
      await db.close();
    }
  });

  test('staging is atomic, exactly replayable and rejects conflicts', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final repository = TestPayrollStagingRepository(database: db);
      const credit = ShopPayrollAllocation(
        id: 'credit-a', employeeId: 'mechanic',
        hoursHundredths: 250, rateCentsPerHour: 4000,
        completed: true, alreadyPaid: false,
      );
      ShopPayrollPaymentProposal proposal({
        String operation = 'op1',
        String method = 'Zelle',
        List<String> ids = const ['credit-a'],
      }) => ShopPayrollPaymentProposal(
        operationId: operation, employeeId: 'mechanic',
        allocationIds: ids, grossCents: 10000,
        repaymentCents: 2000, method: method,
      );
      Future<bool> stage(ShopPayrollPaymentProposal item) =>
          repository.stage(
            businessId: 'test-shop', proposal: item, owner: true,
            credits: [credit], outstandingAdvanceCents: 3000,
          );
      expect(await stage(proposal()), isTrue);
      expect(await stage(proposal()), isFalse);
      await expectLater(stage(proposal(method: 'Cash')), throwsStateError);
      await expectLater(stage(proposal(operation: 'op2')), throwsA(isA<Exception>()));
      final operations = await db.customSelect(
        'SELECT operation_id FROM test_payroll_staging '
        "WHERE business_id = 'test-shop'",
      ).get();
      expect(operations, hasLength(1));
      final allocations = await db.customSelect(
        'SELECT allocation_id FROM test_payroll_staged_credits',
      ).get();
      expect(allocations, hasLength(1));
    } finally {
      await db.close();
    }
  });
}
