import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_mechanic_work_credit_repository.dart';

void main() {
  test('two mechanics finish independently; replay and tenant isolation', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final repo = LocalMechanicWorkCreditRepository(database: db);
      Future<bool> create(String id, String employee) =>
          repo.createAssignment(
            businessId: 'shop-a', allocationId: id, jobId: 'job-1',
            laborLineId: 'labor-1', taskId: 'task-1',
            employeeId: employee, actualMinutes: 150, rateCents: 4000,
          );
      expect(await create('credit-chris', 'chris'), isTrue);
      expect(await create('credit-chris', 'chris'), isFalse);
      expect(await create('credit-kam', 'kam'), isTrue);
      expect(await repo.markDone(businessId: 'shop-a',
        allocationId: 'credit-chris', employeeId: 'chris'), isTrue);
      expect(await repo.markDone(businessId: 'shop-a',
        allocationId: 'credit-chris', employeeId: 'chris'), isFalse);
      expect(await repo.completedUnpaid(businessId: 'shop-a',
        employeeId: 'chris'), hasLength(1));
      expect(await repo.completedUnpaid(businessId: 'shop-a',
        employeeId: 'kam'), isEmpty);
      expect(await repo.completedUnpaid(businessId: 'shop-b',
        employeeId: 'chris'), isEmpty);
      await expectLater(repo.createAssignment(
        businessId: 'shop-a', allocationId: 'credit-chris', jobId: 'job-2',
        laborLineId: 'labor-1', taskId: 'task-1',
        employeeId: 'chris', actualMinutes: 150, rateCents: 4000,
      ), throwsStateError);
    } finally {
      await db.close();
    }
  });

  test('existing paid work cannot be completed or selected again', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final repo = LocalMechanicWorkCreditRepository(database: db);
      await repo.createAssignment(
        businessId: 'shop-a', allocationId: 'credit-a', jobId: 'job-a',
        laborLineId: 'labor-a', taskId: 'task-a',
        employeeId: 'employee-a', actualMinutes: 60, rateCents: 4000,
      );
      await db.customStatement('''
        UPDATE local_mechanic_work_credits_v1
        SET completed = 1, paid_operation_id = 'historical-payment'
        WHERE business_id = 'shop-a' AND allocation_id = 'credit-a'
      ''');
      expect(await repo.markDone(businessId: 'shop-a',
        allocationId: 'credit-a', employeeId: 'employee-a'), isFalse);
      expect(await repo.completedUnpaid(businessId: 'shop-a',
        employeeId: 'employee-a'), isEmpty);
    } finally {
      await db.close();
    }
  });
}
