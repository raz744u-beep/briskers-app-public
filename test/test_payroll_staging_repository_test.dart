import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/core/shop_payroll_preview.dart';
import 'package:briskers_app/services/test_payroll_staging_repository.dart';

void main() {
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
