import 'package:briskers_app/screens/payroll/payroll_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('approved overview routes real employee and week to labor review',
      (tester) async {
    String? selected;
    DateTime? week;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PayrollOverview(
      employees: const [
        {'id': 'mechanic-a', 'name': 'Actual Mechanic', 'role': 'mechanic',
          'rate': 4000},
      ],
      work: const [], payments: const [],
      onOpenProfile: (_, _) async {},
      onReviewWeek: (id, date) async { selected = id; week = date; },
    ))));
    expect(find.text('Actual Mechanic'), findsOneWidget);
    expect(find.text('Outstanding from previous weeks'), findsOneWidget);
    expect(find.byKey(const Key('payroll-overview-fixed-totals')), findsOneWidget);
    await tester.tap(find.text('Review Weekly Labor (0 tasks)'));
    expect(selected, 'mechanic-a');
    expect(week, isNotNull);
    expect(find.textContaining('designated'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
