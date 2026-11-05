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
      recordPayment: (_, _, _, _, _, _, _, _) async {
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
}
