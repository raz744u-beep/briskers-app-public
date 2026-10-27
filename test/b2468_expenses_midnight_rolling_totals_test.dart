import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/expenses_period_totals.dart';
import 'package:briskers_app/services/local_financial_totals_journal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row(String id, String day, String direction, num amount,
    {bool verified = false, num? reportingAmount}) => {
  'id': id,
  'transaction_date': day,
  'direction': direction,
  'amount': amount,
  'reporting_status': verified ? 'verified' : 'unverified',
  if (reportingAmount != null) 'reporting_amount': reportingAmount,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Complete period stores exact per-day retained receipts and fees',
      () async {
    final rows = [
      row('payment', '2026-10-26', 'income', 100,
          verified: true, reportingAmount: 97),
      row('cash', '2026-10-26', 'income', 25, verified: true),
      row('expense', '2026-10-25', 'expense', 12),
    ];
    final totals = await ExpensesPeriodTotals.calculate(
      readPage: (offset, count) async =>
          rows.skip(offset).take(count).toList(),
    );
    expect(totals.income, 122);
    expect(totals.expenses, 12);
    expect(totals.dailyBreakdown, isNotNull);
    expect(totals.dailyBreakdown!['2026-10-26']!.incomeCents, 12200);
    expect(totals.dailyBreakdown!['2026-10-26']!.transactions, 2);
    expect(totals.dailyBreakdown!['2026-10-25']!.expensesCents, 1200);
  });

  test('Midnight 30-day rollover uses verified overlapping days and local delta',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final journal = LocalFinancialTotalsJournal(database: db);
    try {
      const yesterdayScope =
          'shop|owner|2026-09-27T00:00:00.000|2026-10-26T00:00:00.000|||||';
      const todayScope =
          'shop|owner|2026-09-28T00:00:00.000|2026-10-27T00:00:00.000|||||';
      final old = await ExpensesPeriodTotals.calculate(
        readPage: (offset, count) async => [
          row('old-day', '2026-09-27', 'expense', 10),
          row('still-in-range', '2026-10-26', 'income', 500, verified: true),
          row('expense', '2026-10-26', 'expense', 50),
        ].skip(offset).take(count).toList(),
      );
      final verifiedAt = DateTime.now().subtract(const Duration(minutes: 3));
      await journal.reconcileAndSaveBaseline(
        'shop', yesterdayScope, old, verifiedAt, const [],
      );
      await journal.record('shop', 'transaction:today',
        after: row('today', '2026-10-27', 'income', 20));
      final next = await journal.loadRollingBaseline(
        'shop', todayScope,
        startDate: DateTime(2026, 9, 28),
        endDate: DateTime(2026, 10, 27),
      );
      expect(next, isNotNull, reason: 'Midnight must not drop saved totals');
      expect(next!.totals.income, 500);
      expect(next.totals.expenses, 50);
      expect(next.verifiedThrough, DateTime(2026, 10, 26));
      final displayed = await journal.apply('shop', next.totals,
        startDate: DateTime(2026, 9, 28),
        endDate: DateTime(2026, 10, 27));
      expect(displayed.income, 520);
      expect(displayed.expenses, 50);
      expect(await journal.pendingCount('shop'), 1);
      // Scoped receipts belong to this shop+owner+filter only.
      expect(await journal.loadRollingBaseline(
        'other', todayScope,
        startDate: DateTime(2026, 9, 28),
        endDate: DateTime(2026, 10, 27),
      ), isNull);
      expect(await journal.loadRollingBaseline(
        'shop',
        'shop|office|2026-09-28T00:00:00.000|2026-10-27T00:00:00.000|||||',
        startDate: DateTime(2026, 9, 28),
        endDate: DateTime(2026, 10, 27),
      ), isNull);
      expect(await journal.loadRollingBaseline(
        'shop',
        'shop|owner|2026-09-28T00:00:00.000|2026-10-27T00:00:00.000||income||||',
        startDate: DateTime(2026, 9, 28),
        endDate: DateTime(2026, 10, 27),
      ), isNull);
    } finally {
      await db.close();
    }
  });

  test('Missing historic day coverage never invents a verified amount',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final journal = LocalFinancialTotalsJournal(database: db);
    try {
      const sourceScope =
          'shop|owner|2026-10-25T00:00:00.000|2026-10-26T00:00:00.000|||||';
      final totals = await ExpensesPeriodTotals.calculate(
        readPage: (offset, count) async => [
          row('one', '2026-10-26', 'expense', 11),
        ].skip(offset).take(count).toList(),
      );
      await journal.reconcileAndSaveBaseline(
        'shop', sourceScope, totals,
        DateTime.now().subtract(const Duration(minutes: 1)), const [],
      );
      expect(await journal.loadRollingBaseline(
        'shop',
        'shop|owner|2026-10-24T00:00:00.000|2026-10-27T00:00:00.000|||||',
        startDate: DateTime(2026, 10, 24),
        endDate: DateTime(2026, 10, 27),
      ), isNull);
    } finally {
      await db.close();
    }
  });

  test('Calendar-date windows remain exactly 30 days across fall DST', () {
    final sundayAfterFallback = DateTime(2026, 11, 2);
    final start = DateTime(
      sundayAfterFallback.year,
      sundayAfterFallback.month,
      sundayAfterFallback.day - 29,
    );
    expect(start.year, 2026);
    expect(start.month, 10);
    expect(start.day, 4);
    expect(DateTime.utc(2026, 11, 2).difference(
        DateTime.utc(start.year, start.month, start.day)).inDays, 29);
    final code = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(code, contains(
        'DateTime(today.year, today.month, today.day - 29)'));
    expect(code, isNot(contains(
        'today.subtract(const Duration(days: 29))')));
  });

  test('Date change is not allowed to show Calculating when daily baseline exists', () {
    final code = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(code, contains('journal.loadRollingBaseline('));
    expect(code, contains('final rolloverPending ='));
    expect(code, contains('today not yet verified'));
    expect(code, contains('if (offline || (fresh && !force))'));
  });
}
