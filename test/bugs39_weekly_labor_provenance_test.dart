import 'package:briskers_app/screens/payroll/employee_work_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final week = DateTime(2026, 11, 16);
  Map<String, dynamic> labor(String id, int minutes, {bool historical = false}) => {
    'id': id, 'task_id': 'task-$id', 'job_id': 'job-40', 'invoice_id': 'invoice-6359',
    'job_number': 'J-40', 'customer_name': 'Gloria Johnson', 'description': id,
    'estimated_minutes': minutes, 'actual_minutes': minutes,
    'remaining_minutes': 0, 'paid_minutes': minutes, 'paid': 1,
    'state': 'Done', 'source_active': 1, 'archived_labor': historical ? 1 : 0,
    'date_mode': 'inherited',
    'work_start_date': '2026-11-16', 'work_end_date': '2026-11-20',
    'completed_date': '2026-11-13',
  };
  final engine = <String, dynamic>{
    'id': 'engine', 'task_id': 'engine-task', 'job_id': 'job-56', 'job_number': 'J-56',
    'customer_name': 'Terrance Sanders', 'description': 'Replace engine',
    'estimated_minutes': 1200, 'actual_minutes': 0, 'paid_minutes': 480,
    'remaining_minutes': 720, 'state': 'In Progress', 'source_active': 1,
    'work_start_date': '2026-11-12', 'work_end_date': '2026-11-19',
  };

  test('14.60 historical Gloria hours cannot enter a new week through inherited dates', () {
    final rows = [labor('struts', 216, historical: true),
      labor('separator', 600, historical: true), labor('pump', 60, historical: true), engine];
    final before = rows.map((r) => Map<String, dynamic>.from(r)).toList();
    expect(rows.take(3).fold<int>(0, (n, r) => n + EmployeeWorkReview.minutes(r)), 876);
    expect(EmployeeWorkReview.weeklyRows(rows, week), [engine]);
    expect(rows, before);
    expect(EmployeeWorkReview.weeklyRows([labor('prior-paid', 216)], week), isEmpty);
    expect(EmployeeWorkReview.weeklyRows([
      {...labor('paid-unknown', 60), 'completed_date': null},
    ], week), isEmpty);
  });

  test('genuine current completed work and explicit unpaid work remain visible', () {
    final current = {...labor('current', 90), 'completed_date': '2026-11-17'};
    expect(EmployeeWorkReview.weeklyRows([current], week), [current]);
    final manual = {...labor('manual', 90), 'date_mode': 'manual'};
    expect(EmployeeWorkReview.weeklyRows([manual], week), [manual]);
    final unpaid = {...labor('unpaid', 90), 'completed_date': null,
      'paid_minutes': 0, 'paid': 0, 'remaining_minutes': 90};
    expect(EmployeeWorkReview.weeklyRows([unpaid], week), [unpaid]);
    expect(EmployeeWorkReview.weeklyRows([{...engine, 'source_active': 0}], week), isEmpty);
    expect(EmployeeWorkReview.weeklyRows([{...engine, 'assignment_conflict': 1}], week), isEmpty);
    expect(EmployeeWorkReview.weeklyRows([{...engine, 'work_end_date': '2026-11-13'}], week,
      now: DateTime(2026, 11, 18)), hasLength(1));
    final historical = {...labor('historical', 216, historical: true), 'invoice_date': '2026-11-03'};
    expect(EmployeeWorkReview.weeklyRows([historical], DateTime(2026, 11, 2)), [historical]);
    expect(EmployeeWorkReview.weeklyRows([historical], week), isEmpty);
  });

  testWidgets('read-only breakdown exposes included and excluded internal identities', (tester) async {
    final rows = [labor('struts', 216, historical: true), engine];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EmployeeWorkReview(
      week: week, rows: rows, jobs: const [], employeeName: 'Chris',
      onWeekChanged: (_) {}, onJob: (_) {},
    ))));
    await tester.ensureVisible(find.byKey(const Key('weekly-hours-breakdown')));
    await tester.tap(find.byKey(const Key('weekly-hours-breakdown')));
    await tester.pumpAndSettle();
    expect(find.text('Weekly hours breakdown'), findsOneWidget);
    expect(find.textContaining('Allocation ID: struts'), findsOneWidget);
    expect(find.textContaining('Excluded: historical labor'), findsOneWidget);
    expect(find.textContaining('invoice-6359'), findsOneWidget);
    expect(rows.first['paid_minutes'], 216);
    expect(tester.takeException(), isNull);
  });
}
