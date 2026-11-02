import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/services/expenses_period_totals.dart';
import 'package:briskers_app/services/verified_expense_totals_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('verified totals survive a new cache instance and require exact scope', () async {
    final at = DateTime.now().subtract(const Duration(minutes: 5));
    await const VerifiedExpenseTotalsCache().save('shop|owner|September',
      const ExpensesPeriodTotals(income: 123, expenses: 45, transactions: 6, feesUnverified: true), at);
    final saved = await const VerifiedExpenseTotalsCache().load('shop|owner|September');
    expect(saved!.totals.income, 123);
    expect(saved.totals.expenses, 45);
    expect(saved.totals.feesUnverified, true);
    expect(saved.at.toUtc(), at.toUtc());
    expect(await const VerifiedExpenseTotalsCache().load('other|owner|September'), isNull);
    expect(await const VerifiedExpenseTotalsCache().load('shop|office|September'), isNull);
    expect(await const VerifiedExpenseTotalsCache().load('shop|owner|October'), isNull);
  });
  test('same-scope verified totals survive refresh failure without being overwritten', () async {
    const scope = 'shop|owner|2026-10-01|2026-10-24|all';
    final verifiedAt = DateTime.now().subtract(const Duration(minutes: 20));
    const known = ExpensesPeriodTotals(
      income: 1250.50, expenses: 300.25,
      transactions: 9, feesUnverified: false,
    );
    const cache = VerifiedExpenseTotalsCache();
    await cache.save(scope, known, verifiedAt);
    await expectLater(
      ExpensesPeriodTotals.calculate(
        readPage: (_, _) async => throw StateError('Network timeout'),
      ),
      throwsStateError,
    );
    final restored = await const VerifiedExpenseTotalsCache().load(scope);
    expect(restored, isNotNull);
    expect(restored!.totals.income, 1250.50);
    expect(restored.totals.expenses, 300.25);
    expect(restored.at.toUtc(), verifiedAt.toUtc());
    expect(await cache.load('shop|owner|2026-10-02|2026-10-24|all'), isNull);
  });

  test('an interrupted complete-total scan cannot save a partial figure', () async {
    var calls = 0;
    await expectLater(ExpensesPeriodTotals.calculate(pageSize: 1, readPage: (_, _) async {
      if (++calls > 1) throw StateError('Interrupted download');
      return [{'id': 'one', 'amount': 100, 'direction': 'income'}];
    }), throwsStateError);
    expect(await const VerifiedExpenseTotalsCache().load('shop'), isNull);
  });
}
