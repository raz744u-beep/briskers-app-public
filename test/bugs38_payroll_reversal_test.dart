import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _ExpenseSync extends BriskersApi {
  final reversals = <String>[];

  @override
  Future<Map<String, dynamic>> syncCreateManualTransaction(
    String businessId, {
    required String operationId,
    required String direction,
    required String accountId,
    required String categoryId,
    required num amount,
    required DateTime date,
    String? jobId,
    String? documentId,
    String? counterpartyId,
    String? counterpartyName,
    String? remarks,
  }) async => {'transaction_id': 'canonical-expense'};

  @override
  Future<void> syncPayrollExpenseReversal(
    String businessId, {
    required String operation,
    required String transactionId,
    required num amount,
    required String date,
  }) async =>
      reversals.add('$businessId/$operation/$transactionId/$amount/$date');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Owner reversal restores an advance and syncs just the linked expense',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LocalPayrollRepository(
        db,
        business: 'shop',
        owner: true,
        deviceId: 'trusted',
        assertOwnerGrant: () {},
      );
      await repo.bindPaymentAuthority(
        writerDeviceId: 'trusted',
        assertVerifiedPairing: () {},
      );
      await repo.saveEmployeeCompensation(
        employee: 'employee',
        name: 'Fixture',
        rate: 0,
        weeklyBase: true,
      );
      await repo.recordOpeningAdvance('employee', 20000);

      Future<bool> settle(String operation) => repo.verify(
        operation: operation,
        employee: 'employee',
        date: '2026-11-13',
        week: '2026-11-09',
        selected: [],
        method: 'Cash',
        base: 50000,
        hourlyAdjustment: 0,
        adjustmentReason: '',
        repayment: 10000,
        confirmedNet: 40000,
      );

      expect(await settle('original'), isTrue);
      expect(await repo.advance('employee'), 10000);
      final cache = LocalFinancialCache(database: db);
      await cache.saveOptions('shop', {
        'accounts': [
          {'id': 'checking', 'name': 'Business Checking - 9858'},
        ],
        'categories': [
          {'id': 'payroll', 'name': 'Payroll', 'normal_direction': 'expense'},
        ],
      });
      final api = _ExpenseSync();
      final expenses = OfflineFinancialWriteService(
        database: db,
        cache: cache,
        api: api,
      );
      await expenses.materializePendingPayrollExpenses('shop');
      await expenses.flush('shop');
      final serverExpense = (await cache.loadTransactions('shop')).single;
      expect(serverExpense['id'], 'canonical-expense');
      expect(serverExpense['amount'], 400);

      final unauthorized = LocalPayrollRepository(
        db,
        business: 'shop',
        owner: false,
      );
      await expectLater(
        unauthorized.reversePayment(
          operation: 'original',
          employee: 'employee',
          actorId: 'other',
          reason: 'Fixture',
        ),
        throwsStateError,
      );
      Future<bool> reverse() => repo.reversePayment(
        operation: 'original',
        employee: 'employee',
        actorId: 'owner',
        reason: 'Duplicate entry',
      );
      expect(await reverse(), isTrue);
      expect(await reverse(), isFalse);
      expect(await repo.advance('employee'), 20000);
      expect((await repo.history('employee')).single['net'], 40000);
      expect(
        (await repo.history('employee')).single['reversal_reason'],
        'Duplicate entry',
      );
      expect(await cache.loadTransactions('shop'), isEmpty);
      await cache.mergeServerTransactions('shop', [serverExpense]);
      expect(await cache.loadTransactions('shop'), isEmpty);
      expect(
        (await cache.loadTransactionDetail(
          'shop',
          'canonical-expense',
        ))?['status'],
        'void',
      );
      await expenses.flush('shop');
      await expenses.flush('shop');
      expect(api.reversals, [
        'shop/original/canonical-expense/400.0/2026-11-13',
      ]);
      expect(await settle('original'), isFalse);
      expect(await settle('replacement'), isTrue);
      expect(await repo.advance('employee'), 10000);
    },
  );
}
