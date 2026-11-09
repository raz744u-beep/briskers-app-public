import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_financial_totals_journal.dart';
import 'package:briskers_app/services/local_expense_subtotal.dart';

void main() {
  test('partial offline subtotal overlays edits, deletions, new records once',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final journal=LocalFinancialTotalsJournal(database:db);
    Map<String,dynamic> row(String id,String direction,num amount)=> {
      'id':id,'direction':direction,'amount':amount,
      'transaction_date':'2026-11-07',
    };
    final before=row('expense-a','expense',30);
    final updated=row('expense-a','expense',20);
    final deleted=row('expense-b','expense',15);
    final added=row('income-new','income',383.09);
    await journal.record('shop','edit-a',before:before,after:updated);
    await journal.record('shop','delete-b',before:deleted,after:null);
    await journal.record('shop','add-income',after:added);
    final rows=await journal.overlayCachedRows('shop',[
      before,deleted,row('expense-c','expense',5),added,
    ]);
    final totals=await LocalExpenseSubtotal.calculate(rows);
    expect(totals!.expenses,25);
    expect(totals.income,closeTo(383.09,0.001));
    expect(totals.transactions,3);
  });
}
