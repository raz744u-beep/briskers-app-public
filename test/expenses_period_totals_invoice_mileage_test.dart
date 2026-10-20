import 'dart:io';

import 'package:briskers_app/services/expenses_period_totals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Totals use every posted transaction beyond the first visible 50', () async {
    final rows = <Map<String, dynamic>>[
      for (var i = 0; i < 235; i++)
        {
          'id': 'expense-$i',
          'direction': 'expense',
          'amount': '1.23',
          'reporting_status': 'verified',
        },
      {
        'id': 'payment',
        'direction': 'income',
        'amount': '100.00',
        'reporting_status': 'verified',
        'reporting_amount': '97.00',
      },
    ];
    final offsets = <int>[];
    final summary = await ExpensesPeriodTotals.calculate(
      pageSize: 200,
      readPage: (offset, count) async {
        offsets.add(offset);
        return rows.skip(offset).take(count).toList();
      },
    );
    expect(offsets, [0, 200]);
    expect(summary.transactions, 236);
    expect(summary.expenses, 289.05);
    expect(summary.income, 97.0);
    expect(summary.feesUnverified, false);
  });

  test('Different selected date periods yield different totals', () async {
    final rows = [
      {
        'id': 'recent',
        'direction': 'expense',
        'transaction_date': '2026-10-19',
        'amount': '12.00',
      },
      {
        'id': 'old',
        'direction': 'expense',
        'transaction_date': '2026-03-08',
        'amount': '88.00',
      },
    ];
    Future<ExpensesPeriodTotals> forStart(DateTime start) =>
        ExpensesPeriodTotals.calculate(
          readPage: (offset, count) async => rows.where((row) {
            final date = DateTime.parse(row['transaction_date']!.toString());
            return !date.isBefore(start);
          }).skip(offset).take(count).toList(),
        );
    final last30 = await forStart(DateTime(2026, 9, 21));
    final lastYear = await forStart(DateTime(2025, 10, 20));
    expect(last30.expenses, 12);
    expect(lastYear.expenses, 100);
  });

  test('Duplicate identities cannot double-count and unverified fees are flagged', () async {
    final totals = await ExpensesPeriodTotals.calculate(
      pageSize: 2,
      readPage: (offset, limit) async {
        if (offset == 0) {
          return [
            {'id': 'same', 'direction': 'income', 'amount': 50},
            {'id': 'same', 'direction': 'income', 'amount': 50},
          ];
        }
        return const [];
      },
    );
    expect(totals.transactions, 1);
    expect(totals.income, 50);
    expect(totals.feesUnverified, true);
  });

  test('Truncated, invalid, or superseded scope never publishes a total', () async {
    await expectLater(
      ExpensesPeriodTotals.calculate(
        pageSize: 2,
        maxPages: 1,
        readPage: (_, __) async => [
          {'id': 'a', 'direction': 'expense', 'amount': 1},
          {'id': 'b', 'direction': 'expense', 'amount': 1},
        ],
      ),
      throwsStateError,
    );
    var valid = true;
    await expectLater(
      ExpensesPeriodTotals.calculate(
        pageSize: 1,
        isCurrent: () => valid,
        readPage: (_, __) async {
          valid = false;
          return [{'id': 'a', 'direction': 'expense', 'amount': 1}];
        },
      ),
      throwsStateError,
    );
    await expectLater(
      ExpensesPeriodTotals.calculate(
        readPage: (_, __) async => [
          {'direction': 'income', 'amount': 5},
        ],
      ),
      throwsStateError,
    );
  });

  test('Expense summary never uses only currently visible list rows', () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    final start = source.indexOf('Widget build(BuildContext context)');
    final end = source.indexOf('return Scaffold(', start);
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final initial = source.substring(start, end);
    expect(initial, contains('InvoicePaymentFeed.combine('));
    expect(initial, isNot(contains('final income = _transactions')));
    expect(initial, isNot(contains('final expenses = _transactions')));
    expect(source, contains('ExpensesPeriodTotals.calculate('));
    expect(source, contains('startDate: startDate, endDate: endDate'));
    expect(source, contains('Calculating complete posted totals'));
    expect(source, contains('Complete totals are unavailable'));
  });

  test('Mileage in Notes is derived from header and not persisted as memo', () {
    final invoice = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final tab = invoice.substring(invoice.indexOf('Widget _notesTab()'));
    expect(tab, contains("savedMileage = _detail?['odometer_in']"));
    expect(tab, contains("ValueKey('invoice-notes-automatic-mileage')"));
    expect(tab, contains('Automatic from Invoice Details'));
    expect(tab, contains('_readOnly ? null : _editDocumentHeader'));
    expect(tab, isNot(contains("_notesController.text = savedMileage")));
    final pdf = File('lib/services/document_pdf_service.dart')
        .readAsStringSync();
    expect(pdf, contains("'Mileage: "));
    expect(pdf, contains('if (odometer.isNotEmpty)'));
  });
}
