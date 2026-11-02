import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/integrated_test_payroll.dart';
import 'package:briskers_app/tasks_payroll_integrated_main.dart';
void main(){testWidgets('Employee profile has five agreed tabs and collapsed advances',(tester)async{
  final db=BriskersLocalDatabase(NativeDatabase.memory());final repo=IntegratedTestPayroll(db);
  await tester.pumpWidget(MaterialApp(home:IntegratedPayrollHome(repository:repo)));
  await tester.runAsync(()async{await Future<void>.delayed(const Duration(milliseconds:200));});await tester.pumpAndSettle();
  await tester.tap(find.text('Employee / Payroll'));await tester.pumpAndSettle();
  for(final name in ['Details','Tasks','Payroll','Reports','Taxes & 1099']){expect(find.text(name),findsOneWidget);}
  await tester.tap(find.text('Payroll'));await tester.pumpAndSettle();
  expect(find.text('Advances & Repayments • \$0.00 outstanding'),findsOneWidget);
  expect(find.text('Add TEST advance').hitTestable(),findsNothing);
  await tester.pumpWidget(const SizedBox());await db.close();
});}
