import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/shop_payroll_preview.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/test_payroll_staging_repository.dart';
import 'package:briskers_app/widgets/test_employee_payroll_staging_panel.dart';

void main() {
  testWidgets('Other employee and business see no staged payroll', (tester) async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TestPayrollStagingRepository(database: db);
    const credit = ShopPayrollAllocation(
      id: 'credit-2', employeeId: 'mechanic',
      hoursHundredths: 100, rateCentsPerHour: 4000,
      completed: true, alreadyPaid: false,
    );
    await repo.stage(
      businessId: 'test-shop',
      proposal: ShopPayrollPaymentProposal(
        operationId: 'op-2', employeeId: 'mechanic',
        allocationIds: ['credit-2'], grossCents: 4000,
        repaymentCents: 0, method: 'Cash',
      ),
      owner: true, credits: [credit], outstandingAdvanceCents: 0,
    );
    Future<void> show(String business, String employee) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        TestEmployeePayrollStagingPanel(
          key: ValueKey('$business/$employee'),
          businessId: business, employeeId: employee, repository: repo,
        ),
      )));
      await tester.pumpAndSettle();
    }
    await show('test-shop', 'other-employee');
    expect(find.text('No staged payroll proposals'), findsOneWidget);
    expect(find.textContaining('40.00 net'), findsNothing);
    await show('other-shop', 'mechanic');
    expect(find.text('No staged payroll proposals'), findsOneWidget);
    expect(find.textContaining('40.00 net'), findsNothing);
    await show('test-shop', 'mechanic');
    expect(find.textContaining('40.00 net'), findsOneWidget);
  });

  testWidgets('Employee TEST payroll shows staged, never paid', (tester) async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TestPayrollStagingRepository(database: db);
    const credit = ShopPayrollAllocation(
      id: 'credit-1', employeeId: 'mechanic',
      hoursHundredths: 250, rateCentsPerHour: 4000,
      completed: true, alreadyPaid: false,
    );
    final proposal = ShopPayrollPaymentProposal(
      operationId: 'op-1', employeeId: 'mechanic',
      allocationIds: ['credit-1'], grossCents: 10000,
      repaymentCents: 2000, method: 'Zelle',
    );
    await repo.stage(
      businessId: 'test-shop', proposal: proposal, owner: true,
      credits: [credit], outstandingAdvanceCents: 3000,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      TestEmployeePayrollStagingPanel(
        businessId: 'test-shop', employeeId: 'mechanic', repository: repo,
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('not paid'), findsOneWidget);
    expect(find.textContaining('80.00 net'), findsOneWidget);
    expect(find.textContaining('100.00'), findsOneWidget);
    expect(find.textContaining('Zelle'), findsOneWidget);
    expect(find.textContaining('Verify Payment'), findsNothing);
  });
}
