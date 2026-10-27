import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/expenses_period_totals.dart';
import 'package:briskers_app/services/local_financial_totals_journal.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';

Map<String, dynamic> row(String id, String direction, num amount,
        String date) =>
    {'id': id, 'direction': direction, 'amount': amount,
      'transaction_date': date};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const old = ExpensesPeriodTotals(
      income: 20000, expenses: 1000,
      transactions: 11, feesUnverified: false);

  test('new local income immediately updates saved totals before sync', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final journal = LocalFinancialTotalsJournal(database: db);
    try {
      await journal.record('shop', 'transaction:local-a',
          after: row('local-a', 'income', 750, '2026-10-26'));
      final shown = await journal.apply('shop', old,
          startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 10, 31));
      expect(shown.income, 20750);
      expect(shown.expenses, 1000);
      expect(await journal.pendingCount('shop'), 1);
      expect((await LocalFinancialTotalsJournal(database: db)
          .apply('shop', old)).income, 20750,
          reason: 'Restart must restore the durable local delta');
    } finally { await db.close(); }
  });

  test('editing reverses the original contribution, then applies new value once',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final journal = LocalFinancialTotalsJournal(database: db);
    try {
      final previous = row('server-expense', 'expense', 300, '2026-10-25');
      await journal.record('shop', 'transaction:server-expense',
          before: previous,
          after: row('server-expense', 'expense', 400, '2026-10-26'));
      await journal.record('shop', 'transaction:server-expense',
          before: row('server-expense', 'expense', 400, '2026-10-26'),
          after: row('server-expense', 'expense', 450, '2026-10-26'));
      expect((await journal.apply('shop', old)).expenses, 1150);
      expect((await journal.apply('shop', old,
          startDate: DateTime(2026, 10, 26),
          endDate: DateTime(2026, 10, 26))).expenses, 1450);
      expect((await journal.apply('shop', old,
          startDate: DateTime(2026, 10, 25),
          endDate: DateTime(2026, 10, 25))).expenses, 700);
    } finally { await db.close(); }
  });

  test('server ID remapping preserves the amount exactly once', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final journal = LocalFinancialTotalsJournal(database: db);
    try {
      await journal.record('shop', 'transaction:local-1',
          after: row('local-1', 'income', 750, '2026-10-26'));
      await journal.remap('shop', 'transaction:local-1',
          'transaction:server-1', newTransactionId: 'server-1');
      expect((await journal.apply('shop', old)).income, 20750);
      await journal.reconcile('shop', [
        row('server-1', 'income', 750, '2026-10-26'),
      ]);
      expect(await journal.pendingCount('shop'), 0);
      // New server baseline now contains this exact acknowledged transaction.
      const updatedServer = ExpensesPeriodTotals(
          income: 20750, expenses: 1000,
          transactions: 12, feesUnverified: false);
      expect((await journal.apply('shop', updatedServer)).income, 20750);
    } finally { await db.close(); }
  });

  test('unsynced received invoice payment contributes; edit and delete reverse it',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final ledger = OfflineInvoicePaymentLedger(database: db);
    final journal = LocalFinancialTotalsJournal(database: db);
    try {
      final op = await ledger.recordReceivedPayment(
        'shop', 'invoice-1', amount: 750,
        remainingBeforePaymentCents: 90000,
        methodId: 'method-1', methodName: 'Cash',
        paymentDate: DateTime.now().toIso8601String().split('T').first,
      );
      expect((await journal.apply('shop', old)).income, 20750);
      await ledger.editNeverSubmittedPayment('shop', 'invoice-1', op,
        amount: 700, maximumAllowedCents: 90000,
        methodId: 'method-1', methodName: 'Cash',
        paymentDate: DateTime.now().toIso8601String().split('T').first,
      );
      expect((await journal.apply('shop', old)).income, 20700);
      await ledger.deleteNeverSubmittedPayment('shop', 'invoice-1', op);
      expect((await journal.apply('shop', old)).income, 20000);
      expect(await journal.pendingCount('shop'), 0);
    } finally { await db.close(); }
  });

  test('SQLite rollback reverses local projection with failed outbox write',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final journal = LocalFinancialTotalsJournal(database: db);
    try {
      await expectLater(db.transaction(() async {
        await journal.record('shop', 'transaction:fail',
          after: row('fail', 'expense', 99, '2026-10-26'));
        throw StateError('Simulated commit failure');
      }), throwsStateError);
      expect(await journal.pendingCount('shop'), 0);
    } finally { await db.close(); }
  });

  test('receipt reconciliation never uses amount-only matching', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final journal = LocalFinancialTotalsJournal(database: db);
    try {
      await journal.record('shop', 'invoice-payment:op1',
        after: row('invoice-payment:op1', 'income', 750, '2026-10-26'));
      await journal.reconcile('shop', [
        row('unrelated', 'income', 750, '2026-10-26'),
      ]);
      expect(await journal.pendingCount('shop'), 1);
      await journal.reconcile('shop', [
        row('posted-txn', 'income', 750, '2026-10-26'),
      ], receipts: [
        {'operation_id': 'op1', 'transaction_id': 'posted-txn',
          'receipt_state': 'posted'},
      ]);
      expect(await journal.pendingCount('shop'), 0);
    } finally { await db.close(); }
  });

  test('Expenses first frame uses saved totals and never partial page sums', () {
    final code = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(code, contains('LocalFinancialTotalsJournal()'));
    expect(code, contains('final sqliteSaved = await journal.loadBaseline(businessId, scope)'));
    expect(code, contains('await journal.apply('));
    expect(code, contains('await journal.reconcileAndSaveBaseline('));
    expect(code, contains('const Duration(minutes: 30)'));
    expect(code, isNot(contains('final income = _transactions.fold(')));
  });
}
