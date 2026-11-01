import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/shop_payroll_preview.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/test_payroll_credit_repository.dart';

void main() {
  test('Only completed unpaid TEST credits appear for matching employee/shop',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final repo = TestPayrollCreditRepository(database: db);
      Future<void> seed(String id, String employee, bool completed,
          bool paid) => repo.seedSyntheticCredit(
        businessId: 'shop-a',
        credit: ShopPayrollAllocation(
          id: id, employeeId: employee, hoursHundredths: 250,
          rateCentsPerHour: 4000, completed: completed, alreadyPaid: paid,
        ),
      );
      await seed('ready', 'chris', true, false);
      await seed('not-done', 'chris', false, false);
      await seed('paid', 'chris', true, true);
      await seed('other-mechanic', 'kam', true, false);
      final result = await repo.completedUnpaid(
        businessId: 'shop-a', employeeId: 'chris',
      );
      expect(result.map((x) => x.id), ['ready']);
      expect(result.single.grossCents, 10000);
      expect(await repo.completedUnpaid(
        businessId: 'shop-b', employeeId: 'chris',
      ), isEmpty);
      await expectLater(seed('ready', 'chris', true, false),
          throwsA(isA<Exception>()));
    } finally {
      await db.close();
    }
  });
}
