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
});
  testWidgets('UI completes real local work and verifies partial-job payroll',(tester)async{
    await tester.binding.setSurfaceSize(const Size(900,1400));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final db=BriskersLocalDatabase(NativeDatabase.memory());final repo=IntegratedTestPayroll(db);
    await repo.initializeEmployees();await repo.createJob('ui-job','UI car');await repo.addLabor('ui-job','labor','UI repair',250);await repo.assign('ui-job/labor','chris');await repo.assign('ui-job/labor','kam');
    Future<void> settle()async{await tester.runAsync(()async{await Future<void>.delayed(const Duration(milliseconds:150));});await tester.pumpAndSettle();}
    await tester.pumpWidget(MaterialApp(home:IntegratedPayrollHome(repository:repo)));await settle();
    await tester.tap(find.text('UI car'));await tester.pumpAndSettle();
    await tester.tap(find.text('Start').first);await tester.pumpAndSettle();
    await tester.tap(find.text('Save locally'));await tester.pumpAndSettle();await settle();
    await tester.tap(find.text('Done').first);await tester.pumpAndSettle();
    await tester.tap(find.text('Save locally'));await tester.pumpAndSettle();await settle();
    expect((await repo.work(employee:'chris')).single['state'],'Done');
    await tester.tap(find.text('Employee / Payroll'));await tester.pumpAndSettle();
    await tester.tap(find.text('Payroll'));await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review / Verify Payment'));await tester.tap(find.text('Review / Verify Payment'));await tester.pumpAndSettle();
    expect(find.textContaining('Gross: \$100.00'),findsOneWidget);
    await tester.tap(find.text('Verify Payment'));await settle();
    expect((await repo.history('chris')).single['gross'],10000);expect((await repo.jobs()).single['done'],0);
    await tester.tap(find.text('Reports'));await tester.pumpAndSettle();expect(find.textContaining('\$100.00 • Cash'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());await db.close();
  });
}
