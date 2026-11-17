import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/local_expense_subtotal.dart';

void main() {
  Map<String,dynamic> row(String id, String direction, num amount,
      {String date='2026-11-07', String? category}) => {
    'id':id, 'direction':direction, 'amount':amount,
    'transaction_date':date,'counterparty':'Synthetic supplier',
    'category_id':category,
  };

  test('offline subtotal uses all saved unique IDs not first visible page',
      () async {
    final rows = <Map<String,dynamic>>[
      for(var i=0;i<70;i++)
        row('expense-$i','expense',10),
      row('income-1','income',383.09),
      row('income-1','income',383.09),
    ];
    final result=await LocalExpenseSubtotal.calculate(rows);
    expect(result, isNotNull);
    expect(result!.income, closeTo(383.09, 0.001));
    expect(result.expenses, closeTo(700, 0.001));
    expect(result.transactions, 71);
  });

  test('offline subtotal keeps date and direction filters and returns no fake zero',
      () async {
    final rows=[
      row('income-1','income',100,date:'2026-11-07'),
      row('expense-1','expense',15,date:'2026-10-01'),
    ];
    final nov=await LocalExpenseSubtotal.calculate(rows,
      startDate:DateTime(2026,11,1),endDate:DateTime(2026,11,30));
    expect(nov!.income,100);
    expect(nov.expenses,0);
    final expenses=await LocalExpenseSubtotal.calculate(rows,
      startDate:DateTime(2026,11,1),direction:'expense');
    expect(expenses,isNull);
  });

  test('invoice previews are not counted without a financial transaction ID',
      () async {
    final rows=[
      row('income-1','income',383.09),
      <String,dynamic>{'_invoice_receipt':true,'direction':'income',
        'amount':383.09,'transaction_date':'2026-11-07'},
    ];
    final totals=await LocalExpenseSubtotal.calculate(rows);
    expect(totals!.income,383.09);
    expect(totals.transactions,1);
  });

  test('All Time and Year to Date reconcile independently of six months', () async {
    final rows = [
      row('last-year', 'expense', 71.36, date: '2025-02-12'),
      row('january', 'expense', 175, date: '2026-01-01'),
      row('may', 'income', 120, date: '2026-05-15'),
      row('november', 'income', 1637.63, date: '2026-11-16'),
    ];
    final all = (await LocalExpenseSubtotal.calculate(rows))!;
    final year = (await LocalExpenseSubtotal.calculate(rows,
      startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 11, 16)))!;
    final sixMonths = (await LocalExpenseSubtotal.calculate(rows,
      startDate: DateTime(2026, 5, 16), endDate: DateTime(2026, 11, 16)))!;
    expect((all.transactions, all.income, all.expenses), (4, 1757.63, 246.36));
    expect((year.transactions, year.income, year.expenses), (3, 1757.63, 175));
    expect((sixMonths.transactions, sixMonths.income, sixMonths.expenses), (1, 1637.63, 0));
    expect(all.dailyBreakdown!['2025-02-12']!.expensesCents, 7136);
    expect(all.unverifiedIncomeReceipts, 2);
  });

}
