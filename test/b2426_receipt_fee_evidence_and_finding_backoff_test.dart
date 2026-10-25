import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/services/expenses_period_totals.dart';
import 'package:briskers_app/services/verified_expense_totals_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Complete period separates posted income from unverified fee evidence',
      () async {
    final result = await ExpensesPeriodTotals.calculate(
      readPage: (offset, limit) async => [
        {
          'id': 'verified-income', 'direction': 'income', 'amount': 103.00,
          'reporting_status': 'verified', 'reporting_amount': 100.00,
        },
        {
          'id': 'unknown-income', 'direction': 'income', 'amount': 65.25,
          'reporting_status': 'unverified',
        },
        {'id': 'parts-expense', 'direction': 'expense', 'amount': 20.00},
      ],
    );
    expect(result.income, 165.25);
    expect(result.expenses, 20.00);
    expect(result.transactions, 3);
    expect(result.feesUnverified, isTrue);
    expect(result.unverifiedIncomeReceipts, 1);
  });

  test('Verified totals cache preserves new count for same exact scope',
      () async {
    SharedPreferences.setMockInitialValues({});
    const cache = VerifiedExpenseTotalsCache();
    final time = DateTime.now().subtract(const Duration(minutes: 1));
    const totals = ExpensesPeriodTotals(
      income: 165.25, expenses: 20, transactions: 3,
      feesUnverified: true, unverifiedIncomeReceipts: 1,
    );
    await cache.save('shopA|owner|30d', totals, time);
    final saved = await cache.load('shopA|owner|30d');
    expect(saved, isNotNull);
    expect(saved!.totals.unverifiedIncomeReceipts, 1);
    expect(saved.totals.feesUnverified, isTrue);
    expect(await cache.load('shopB|owner|30d'), isNull);
  });

  test('Older complete totals snapshots remain readable but count unknown',
      () async {
    const scope = 'shopA|owner|historic';
    SharedPreferences.setMockInitialValues({
      'briskers_verified_totals_v1_$scope': jsonEncode({
        'income': 200, 'expenses': 30, 'transactions': 8,
        'feesUnverified': true,
        'verifiedAt': DateTime.now()
            .subtract(const Duration(minutes: 2)).toUtc().toIso8601String(),
      }),
    });
    final saved = await const VerifiedExpenseTotalsCache().load(scope);
    expect(saved, isNotNull);
    expect(saved!.totals.unverifiedIncomeReceipts, isNull);
    expect(saved.totals.income, 200);
  });

  test('Expense banner does not accuse unknown receipts of processor fees',
      () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(source, contains('unverifiedIncomeReceipts'));
    expect(source, contains('no processing fee is assumed'));
    expect(source, isNot(contains(
        'Processor fees are unverified for some receipts.')));
    expect(source, contains('VerifiedExpenseTotalsCache().save('));
  });

  test('Uncertain Findings replay preserves outbox with bounded backoff', () {
    final source = File('lib/services/vehicle_finding_actions_service.dart')
        .readAsStringSync();
    expect(source, contains('attempts >= 2 && lastAttempt != null'));
    expect(source, contains('nowSeconds - lastAttempt < delaySeconds'));
    expect(source, contains('no duplicate change was sent'));
    expect(source, contains('server is not resolved'));
    expect(source, contains('resolved Job differs'));
    expect(source, contains('LocalJobQuarantine.assertReplayAllowed('));
  });
}
