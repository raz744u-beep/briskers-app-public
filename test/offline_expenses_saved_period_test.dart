import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/screens/expenses_screen.dart';
import 'package:briskers_app/services/expenses_period_totals.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_financial_totals_journal.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('an incomplete ledger keeps the checked All Time expense total', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final mode = BriskersConnectionModeController.instance;
    await mode.setMode(BriskersConnectionMode.offline);
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    debugUseLocalDatabase(db);
    addTearDown(() async {
      debugUseLocalDatabase(null);
      await db.close();
      await mode.setMode(BriskersConnectionMode.auto);
    });
    await tester.runAsync(() async {
      await LocalFinancialCache(database: db).saveTransactions('shop', [
        {
          'id': 'recent-expense',
          'direction': 'expense',
          'counterparty': 'Local supplier',
          'amount': 21.25,
          'transaction_date': '2026-11-03',
        },
      ]);
      await LocalFinancialTotalsJournal(database: db).saveBaseline(
        'shop',
        ['shop', 'owner', ...List.filled(7, '')].join('|'),
        const ExpensesPeriodTotals(
          income: 0,
          expenses: 321.25,
          transactions: 2,
          feesUnverified: false,
        ),
        DateTime.now(),
      );
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: ExpensesScreen(businessId: 'shop', roleCode: 'owner'),
      ),
    );
    final coverage = find.textContaining(
      'some transaction details may be missing on this device',
    );
    for (
      var attempt = 0;
      attempt < 60 && coverage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(find.text(r'$321.25'), findsOneWidget);
    expect(coverage, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
