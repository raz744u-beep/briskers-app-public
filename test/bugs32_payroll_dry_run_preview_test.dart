import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/payroll_dry_run_preview.dart';

void main() {
  test('dry run reads stored allocation minutes but cannot make payment', () {
    final rows = <Map<String,dynamic>>[
      {
        'estimated_minutes':540,
        'recorded_actual_minutes':420,
        'rate_cents':3000,
        'archived_labor':1,
      },
      {
        'estimated_minutes':120,
        'actual_minutes':60,
        'rate_cents':2500,
        'archived_labor':0,
      },
    ];
    final before=rows.map((r)=>Map<String,dynamic>.from(r)).toList();
    final totals=PayrollDryRunTotals.fromSavedWork(rows);
    expect(totals.lines,2);
    expect(totals.assignedMinutes,660);
    expect(totals.recordedMinutes,480);
    expect(totals.laborCents,23500);
    expect(totals.historicalLines,1);
    expect(rows,before);
  });

  testWidgets('dry run screen is marked TEST ONLY without save actions',
      (tester)async{
    await tester.pumpWidget(MaterialApp(home:PayrollDryRunPreview(
      employeeName:'Mechanic',
      weekStart:DateTime(2026,11,2),
      rows:const [
        {'job_number':'J-44','description':'Labor example',
         'estimated_minutes':540,'recorded_actual_minutes':420,
         'rate_cents':3000,'archived_labor':1},
      ],
    )));
    expect(find.textContaining('TEST ONLY'),findsOneWidget);
    expect(find.textContaining('11/6/2026'),findsOneWidget);
    expect(find.text('Save Payment'),findsNothing);
    expect(find.text('Mark Paid'),findsNothing);
  });
}
