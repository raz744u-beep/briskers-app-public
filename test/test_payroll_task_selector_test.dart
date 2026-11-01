import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/shop_payroll_preview.dart';
import 'package:briskers_app/widgets/test_payroll_task_selector.dart';

void main() {
  const ready = ShopPayrollAllocation(
    id: 'credit-ready', employeeId: 'chris',
    hoursHundredths: 250, rateCentsPerHour: 4000,
    completed: true, alreadyPaid: false,
  );
  const paid = ShopPayrollAllocation(
    id: 'credit-paid', employeeId: 'chris',
    hoursHundredths: 100, rateCentsPerHour: 4000,
    completed: true, alreadyPaid: true,
  );
  testWidgets('Owner selects only completed unpaid mechanic work', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      TestPayrollTaskSelector(
        employeeId: 'chris', isOwner: true, allocations: [ready, paid],
      ),
    )));
    expect(find.text('credit-ready'), findsOneWidget);
    expect(find.text('credit-paid'), findsNothing);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.textContaining('100.00'), findsOneWidget);
    expect(find.textContaining('no payment will be recorded'), findsOneWidget);
  });
  testWidgets('Non-owner cannot choose payroll work', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      TestPayrollTaskSelector(
        employeeId: 'chris', isOwner: false, allocations: [ready],
      ),
    )));
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.textContaining('0.00'), findsOneWidget);
  });
}
