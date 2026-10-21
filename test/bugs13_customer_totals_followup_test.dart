import 'dart:io';

import 'package:briskers_app/services/expenses_period_totals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Small 30-day totals use one page without surplus requests', () async {
    final offsets = <int>[];
    final result = await ExpensesPeriodTotals.calculate(
      readPage: (offset, limit) async {
        offsets.add(offset);
        return [
          {'id': 'first', 'direction': 'expense', 'amount': 24.50},
          {'id': 'second', 'direction': 'income', 'amount': 16.25},
        ];
      },
    );
    expect(offsets, [0]);
    expect(result.expenses, 24.50);
    expect(result.income, 16.25);
  });

  test('Large annual totals read follow-up pages concurrently and completely',
      () async {
    final calls = <int>[];
    var inFlight = 0;
    var peakInFlight = 0;
    final result = await ExpensesPeriodTotals.calculate(
      pageSize: 200,
      readPage: (offset, count) async {
        calls.add(offset);
        inFlight++;
        if (inFlight > peakInFlight) peakInFlight = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        inFlight--;
        final items = offset == 600 ? 44 : 200;
        return [
          for (var i = 0; i < items; i++)
            {'id': 'id-${offset + i}', 'direction': 'expense',
              'amount': 1.00},
        ];
      },
    );
    expect(calls, [0, 200, 400, 600]);
    expect(peakInFlight, 3);
    expect(result.transactions, 644);
    expect(result.expenses, 644);
  });

  test('A page failure never returns a misleading partial annual total',
      () async {
    await expectLater(
      ExpensesPeriodTotals.calculate(
        pageSize: 2,
        readPage: (offset, count) async {
          if (offset == 0) {
            return [
              {'id': '1', 'direction': 'expense', 'amount': 4},
              {'id': '2', 'direction': 'expense', 'amount': 5},
            ];
          }
          if (offset == 2) throw StateError('Network page unavailable');
          return const [];
        },
      ),
      throwsStateError,
    );
  });

  test('Customer cache banner cannot change list height on online refresh', () {
    final source = File('lib/screens/customers/customers_screen.dart')
        .readAsStringSync();
    expect(source, contains('bool _refreshFailed = false'));
    expect(source, contains('Tooltip('));
    expect(source, contains('Customer refresh needs attention'));
    expect(source, contains('BriskersConnectionModeController.instance.forceOffline'));
    final header = source.substring(
      source.indexOf('Widget build(BuildContext context)'));
    expect(header, isNot(contains('if (_showingLocal)\n          Container(')));
    expect(header, contains('Expanded(\n          child: _rows == null'));
    expect(header, contains('totalCustomers'),
      reason: 'Status stays inline with the existing fixed header');
  });

  test('Owner-only financial totals skip calculations for secretary', () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(source, contains('bool get _showFinancialSummary => _owner;'));
    final begin = source.indexOf('Future<void> _refreshPeriodTotals(');
    final end = source.indexOf('Future<void> _hydrateFinancialHistory(', begin);
    final method = source.substring(begin, end);
    expect(method, contains('if (!_showFinancialSummary || !mounted) return;'));
    expect(method, contains('const Duration(seconds: 45)'));
    expect(method, contains('if (fresh && !force) return;'));
    expect(method, contains('if (_pendingPeriodScope == scope) return;'));
    expect(method, contains('if (!sameScope) _periodTotals = null;'));
    expect(method, contains('Showing last verified totals; refresh failed.'));
    expect(source, contains('onRefresh: () => _load(forceTotals: true)'));
  });
}
