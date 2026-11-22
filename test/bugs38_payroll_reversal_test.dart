import 'dart:io';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ExpenseSync extends BriskersApi {
  final reversals = <String>[];
  final creates = <num>[];
  final corrections = <(num, num, int)>[];

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
  }) async {
    creates.add(amount);
    return {'transaction_id': 'canonical-expense'};
  }

  @override
  Future<void> syncPayrollExpenseAmount(
    String businessId, {
    required String operation,
    required String transactionId,
    required num previous,
    required num amount,
    required String date,
    required int revision,
  }) async {
    expect(operation, 'original');
    expect(transactionId, 'canonical-expense');
    expect(date, '2026-11-13');
    corrections.add((previous, amount, revision));
  }

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
  SharedPreferences.setMockInitialValues({});

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
  test(
    'Owner corrects a linked amount offline, through restart, sync and deletion',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'briskers-payment-edit-',
      );
      final file = File('${dir.path}/fixture.sqlite');
      var db = BriskersLocalDatabase(NativeDatabase(file));
      final mode = BriskersConnectionModeController.instance;
      await mode.setMode(BriskersConnectionMode.offline);
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
        await mode.setMode(BriskersConnectionMode.auto);
      });

      var mayEdit = true;
      LocalPayrollRepository ledger({bool owner = true}) =>
          LocalPayrollRepository(
            db,
            business: 'shop',
            owner: owner,
            deviceId: 'trusted',
            assertOwnerGrant: () {
              if (!mayEdit) throw StateError('Owner signed out');
            },
          );
      var repo = ledger();
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
      await repo.verify(
        operation: 'original',
        employee: 'employee',
        date: '2026-11-13',
        week: '2026-11-09',
        selected: [],
        method: 'Zelle',
        base: 50000,
        hourlyAdjustment: 0,
        adjustmentReason: '',
        repayment: 10000,
        confirmedNet: 40000,
      );
      var cache = LocalFinancialCache(database: db);
      await cache.saveOptions('shop', {
        'accounts': [
          {'id': 'checking', 'name': 'Business Checking - 9858'},
        ],
        'categories': [
          {'id': 'payroll', 'name': 'Payroll', 'normal_direction': 'expense'},
        ],
      });
      final api = _ExpenseSync();
      OfflineFinancialWriteService financial() =>
          OfflineFinancialWriteService(database: db, api: api);
      await financial().materializePendingPayrollExpenses('shop');
      final original = (await cache.loadTransactions('shop')).single;
      final id = original['id'] as String;
      final detail = (await cache.loadTransactionDetail('shop', id))!;
      await cache.saveTransactionDetail('shop', id, {
        ...detail,
        'attachments': [
          {'id': 'original-photo'},
        ],
      });
      Future<bool> edit(int revision, int amount, {bool owner = true, String? reason}) =>
          ledger(owner: owner).editPaymentAmount(
            operation: 'original',
            employee: 'employee',
            actorId: 'owner',
            expectedRevision: revision,
            net: amount,
            adjustmentReason: reason,
          );
      await expectLater(edit(0, 35000, owner: false), throwsStateError);
      mayEdit = false;
      await expectLater(edit(0, 35000), throwsStateError);
      mayEdit = true;
      expect(await edit(0, 35000, reason: 'Corrected adjustment'), isTrue);
      expect(await edit(0, 35000, reason: 'Corrected adjustment'), isFalse);
      await expectLater(edit(0, 35000, reason: 'Stale reason'), throwsStateError);
      final corrected = (await repo.history('employee')).single;
      expect(corrected['effective_adjustment'], -5000);
      expect(corrected['adjustment_reason'], 'Corrected adjustment');
      await expectLater(edit(0, 36000), throwsStateError);
      expect((await cache.loadTransactions('shop')).single['amount'], 350);
      expect((await cache.loadTransactions('shop')).single['signed_amount'], -350);
      expect((await repo.history('employee')).single['gross'], 45000);
      expect((await repo.history('employee')).single['original_net'], 40000);
      expect(await repo.advance('employee'), 10000);
      expect(
        (await repo.verifiedPayrollWeeks('employee'))['2026-11-09']?.netCents,
        35000,
      );
      expect(
        (await repo.verifiedPayrollWeeks('employee'))['2026-11-16'],
        isNull,
      );
      await financial().flush('shop');
      expect(api.creates, isEmpty);

      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      cache = LocalFinancialCache(database: db);
      repo = ledger();
      final linkedPayment = (await repo.paymentForExpense(id))!;
      expect(linkedPayment['net'], 35000);
      expect(linkedPayment['adjustment_reason'], 'Corrected adjustment');
      expect((await cache.loadTransactionDetail('shop', id))!['attachments'], [
        {'id': 'original-photo'},
      ]);
      await mode.setMode(BriskersConnectionMode.auto);
      await financial().flush('shop');
      expect(api.creates, [350]);
      final canonical = (await cache.loadTransactions('shop')).single;
      expect(canonical['id'], 'canonical-expense');
      await mode.setMode(BriskersConnectionMode.offline);
      expect(await edit(1, 37500), isTrue);
      await cache.mergeServerTransactions('shop', [canonical]);
      expect((await cache.loadTransactions('shop')).single['amount'], 375);
      expect((await repo.history('employee')).single['adjustment_reason'],
        'Corrected adjustment');
      expect(await edit(2, 37500, reason: 'Clarified adjustment'), isTrue);
      expect((await repo.history('employee')).single['adjustment_reason'],
        'Clarified adjustment');
      expect((await cache.loadTransactions('shop')).single['amount'], 375);

      await repo.reversePayment(
        operation: 'original',
        employee: 'employee',
        actorId: 'owner',
        expectedRevision: 3,
        reason: 'Fixture deletion',
      );
      await expectLater(edit(3, 37500, reason: 'After reversal'), throwsStateError);
      expect(await cache.loadTransactions('shop'), isEmpty);
      expect(await repo.advance('employee'), 20000);
      expect(await repo.verifiedPayrollWeeks('employee'), isEmpty);
      expect(
        (await repo.history('employee')).single['reversal_reason'],
        'Fixture deletion',
      );
      expect(
        (await db
                .customSelect('SELECT net FROM regular_payroll_payments')
                .getSingle())
            .read<int>('net'),
        40000,
      );
      await mode.setMode(BriskersConnectionMode.auto);
      await financial().flush('shop');
      await financial().flush('shop');
      expect(api.corrections, [(350, 375, 2)]);
      expect(api.reversals, [
        'shop/original/canonical-expense/375.0/2026-11-13',
      ]);
      expect(await cache.loadTransactions('shop'), isEmpty);
      expect(
        (await cache.loadTransactionDetail(
          'shop',
          'canonical-expense',
        ))!['status'],
        'void',
      );
    },
  );
}
