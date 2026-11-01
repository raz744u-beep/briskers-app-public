import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/core/shop_payroll_preview.dart';
import 'package:briskers_app/services/test_payroll_credit_repository.dart';
import 'package:briskers_app/services/test_mechanic_completion_bridge.dart';

void main() {
  test('completion bridge requires existing allocated work', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final credits = TestPayrollCreditRepository(database: db);
      final bridge = TestMechanicCompletionBridge(credits: credits);
      Future<bool> complete(String id) => bridge.completeSyntheticWork(
        businessId: 'test-shop', employeeId: 'chris', allocationId: id,
      );
      expect(await complete('missing'), isFalse);
      await credits.seedSyntheticCredit(
        businessId: 'test-shop',
        credit: const ShopPayrollAllocation(
          id: 'task-1/chris', employeeId: 'chris',
          hoursHundredths: 125, rateCentsPerHour: 4000,
          completed: false, alreadyPaid: false,
        ),
      );
      expect(await complete('task-1/chris'), isTrue);
      expect(await complete('task-1/chris'), isFalse);
      final available = await credits.completedUnpaid(
        businessId: 'test-shop', employeeId: 'chris',
      );
      expect(available, hasLength(1));
      expect(available.single.grossCents, 5000);
    } finally {
      await db.close();
    }
  });
}
