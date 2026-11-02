import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/integrated_test_payroll.dart';
import 'package:briskers_app/tasks_payroll_integrated_main.dart';

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for(var i=0;i<150;i++) {
    await tester.pump();
    if(finder.evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds:20));
  }
  expect(finder,findsWidgets);
}
void main() {
  testWidgets('Employee profile has five agreed tabs and collapsed advances',(tester)async {
    await tester.runAsync(() async {
      final db=BriskersLocalDatabase(NativeDatabase.memory());final repo=IntegratedTestPayroll(db);
      try {
        await tester.pumpWidget(MaterialApp(home:IntegratedPayrollHome(repository:repo)));
        await waitFor(tester,find.text('Saved locally • financial posting and sync disabled'));
        await tester.tap(find.text('Employee / Payroll'));await tester.pumpAndSettle();
        for(final name in ['Details','Tasks','Payroll','Reports','Taxes & 1099']) {expect(find.text(name),findsOneWidget);}
        await tester.tap(find.text('Payroll'));await tester.pumpAndSettle();
        expect(find.text('Advances & Repayments • \$0.00 outstanding'),findsOneWidget);
        expect(find.text('Add TEST advance').hitTestable(),findsNothing);
      } finally {await tester.pumpWidget(const SizedBox());await db.close();}
    });
  });
  testWidgets('UI completes local work and verifies partial-job payroll',(tester)async {
    await tester.binding.setSurfaceSize(const Size(900,1400));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.runAsync(()async {
      final db=BriskersLocalDatabase(NativeDatabase.memory());final repo=IntegratedTestPayroll(db);
      try {
        await repo.initializeEmployees();await repo.createJob('ui-job','UI car');await repo.addLabor('ui-job','labor','UI repair',250);await repo.assign('ui-job/labor','chris');await repo.assign('ui-job/labor','kam');
        await tester.pumpWidget(MaterialApp(home:IntegratedPayrollHome(repository:repo)));
        await waitFor(tester,find.text('UI car'));
        await tester.tap(find.text('UI car'));await tester.pumpAndSettle();
        await tester.tap(find.text('Start').first);await tester.pumpAndSettle();
        await tester.tap(find.text('Save locally'));await tester.pumpAndSettle();
        await waitFor(tester,find.text('Done'));
        await tester.tap(find.text('Done').first);await tester.pumpAndSettle();
        await tester.tap(find.text('Save locally'));await tester.pumpAndSettle();
        await waitFor(tester,find.text('Reopen unpaid work'));
        expect((await repo.work(employee:'chris')).single['state'],'Done');
        await tester.tap(find.text('Employee / Payroll'));await tester.pumpAndSettle();
        await tester.tap(find.text('Payroll'));await tester.pumpAndSettle();
        await tester.tap(find.byType(CheckboxListTile));await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Review / Verify Payment'));await tester.tap(find.text('Review / Verify Payment'));await tester.pumpAndSettle();
        expect(find.textContaining('Gross: \$100.00'),findsOneWidget);
        await tester.tap(find.text('Verify Payment'));await tester.pumpAndSettle();
        for(var i=0;i<150 && (await repo.history('chris')).isEmpty;i++) {await tester.pump();await Future<void>.delayed(const Duration(milliseconds:20));}
        expect((await repo.history('chris')).single['gross'],10000);expect((await repo.jobs()).single['done'],0);
        await tester.tap(find.text('Reports'));await tester.pumpAndSettle();expect(find.textContaining('\$100.00 • Cash'),findsOneWidget);
      } finally {await tester.pumpWidget(const SizedBox());await db.close();}
    });
  });
}
