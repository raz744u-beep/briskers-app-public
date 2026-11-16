import 'package:briskers_app/screens/payroll/payroll_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('idle employee never blanks totals for another employee earned work',(tester)async{
    final now=DateTime.now();final monday=DateTime(now.year,now.month,now.day-now.weekday+1);
    final date=monday.toIso8601String().split('T').first;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:PayrollOverview(
      employees:const [{'id':'a','name':'Legal A','nickname':'Kam','rate':4000},{'id':'b','name':'Legal B','nickname':'Chris'}],
      work:[{'employee_id':'a','state':'Done','paid':0,'completed_date':date,'remaining_minutes':60,'actual_minutes':60,'remaining_cents':4000,'gross_cents':4000}],
      payments:const [],onOpenProfile:(_,_)async{},onReviewWeek:(_,_)async{}))));
    final footer=find.byKey(const Key('payroll-overview-fixed-totals'));
    expect(find.descendant(of:footer,matching:find.text('1.0')),findsOneWidget);
    expect(find.descendant(of:footer,matching:find.text(r'$40.00')),findsNWidgets(2));
    expect(find.descendant(of:footer,matching:find.text(r'$0.00')),findsOneWidget);
    expect(find.text('Kam'),findsOneWidget);expect(find.text('Chris'),findsOneWidget);
    expect(find.text('Paid'),findsNWidgets(2));expect(find.text('Total Paid'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

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
