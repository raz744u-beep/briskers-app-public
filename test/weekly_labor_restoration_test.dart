import 'package:briskers_app/screens/payroll/weekly_labor_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('weekly labor selects carried unpaid work and excludes paid work',
      (tester) async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
    final prior = monday.subtract(const Duration(days: 3));
    String date(DateTime value) => value.toIso8601String().split('T').first;
    Map<String, dynamic> task(String id, DateTime completed, int paid) => {
      'id': id, 'description': id, 'actual_minutes': 60, 'state': 'Done',
      'completed_date': date(completed), 'gross_cents': 4000, 'paid': paid,
      'job_number': 'J-18',
    };
    await tester.pumpWidget(MaterialApp(home: WeeklyLaborReview(
      employeeId: 'mechanic', employeeName: 'Mechanic', week: monday,
      tasks: [task('Carried labor', prior, 0), task('Settled labor', monday, 1)],
      advanceBalance: () async => 0,
      recordPayment: (_, _, _, _, _, _, _, _, _) async {
        fail('Selection must not record a payment.');
      },
    )));
    expect(find.text('Carried labor'), findsOneWidget);
    expect(find.text('Settled labor'), findsNothing);
    expect(find.text('1 of 1'), findsOneWidget);
    await tester.tap(find.text('Clear All'));
    await tester.pump();
    expect(find.text('0 of 1'), findsOneWidget);
    expect(tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Verify Payment'),
    ).onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('partial labor review records only selected remaining minutes',
      (tester) async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
    List<Map<String, dynamic>>? selection;
    int? verifiedNet;
    await tester.pumpWidget(MaterialApp(home: WeeklyLaborReview(
      employeeId: 'mechanic', employeeName: 'Mechanic', week: monday,
      tasks: [
        {'id': 'labor', 'description': 'Partially settled labor',
          'actual_minutes': 60, 'remaining_minutes': 40, 'paid_minutes': 20,
          'rate_cents': 1001, 'state': 'Done', 'paid': 0,
          'completed_date': monday.toIso8601String().split('T').first,
          'gross_cents': 1001, 'job_number': 'J-18'},
      ],
      advanceBalance: () async => 0,
      recordPayment: (_, _, _, selected, adjustment, repayment, net, _, base) async {
        selection = selected;
        verifiedNet = net;
        expect(adjustment, 0);
        expect(repayment, 0);
        expect(base, 0);
      },
    )));
    expect(find.text('Partially Paid · Remaining hours only'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit payable hours'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Hours to pay this week'), '0.33');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Verify Payment'));
    await tester.pumpAndSettle();
    expect(find.text(r'Calculated labor: $3.33'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Record payment'));
    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await tester.pumpAndSettle();
    expect(selection!.single['pay_minutes'], 20);
    expect(selection!.single['paid_minutes'], 20);
    expect(verifiedNet, 333);
    expect(find.text('Payment Recorded'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });

}
