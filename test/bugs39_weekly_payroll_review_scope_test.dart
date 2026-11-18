import 'dart:convert';

import 'package:briskers_app/screens/payroll/employee_work_review.dart';
import 'package:briskers_app/screens/payroll/weekly_labor_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final week = DateTime(2026, 11, 16), priorWeek = DateTime(2026, 11, 9);
  Map<String, dynamic> historical(String id, String description, int minutes) =>
      {
        'id': id,
        'task_id': 'task-$id',
        'job_id': 'job-40',
        'job_number': 'J-40',
        'invoice_id': 'invoice-6359',
        'customer_name': 'Gloria Johnson',
        'description': description,
        'state': 'Done',
        'source_active': 1,
        'estimated_minutes': minutes,
        'actual_minutes': minutes,
        'remaining_minutes': 0,
        'paid_minutes': minutes,
        'paid': 1,
        'rate_cents': 4000,
        'archived_labor': 1,
        'invoice_date': '2026-11-03',
        'completed_date': '2026-11-13',
        'date_mode': 'inherited',
        'work_start_date': '2026-11-16',
        'work_end_date': '2026-11-20',
      };
  List<Map<String, dynamic>> gloria() => [
    historical(
      'separator',
      'Replace oil separator, thermostat and cross over pipes',
      600,
    ),
    historical('pump', 'Replace water pump and bleed cooling system', 60),
    historical('struts', 'Replace front air struts', 216),
  ];
  Map<String, dynamic> warranty() => {
    ...historical('new-return', 'New warranty return labor', 600),
    'invoice_id': 'invoice-6359',
    'archived_labor': 0,
    'state': 'In Progress',
    'date_mode': 'manual',
    'actual_minutes': 0,
    'paid': 0,
    'paid_minutes': 0,
    'remaining_minutes': 600,
    'completed_date': null,
    'payroll_treatment': 'review',
  };
  int rate(Map<String, dynamic> row) => row['rate_cents'] as int? ?? 0;
  List<Map<String, dynamic>> review(
    List<Map<String, dynamic>> rows,
    DateTime selected,
  ) => EmployeeWorkReview.weeklyReviewRows(
    rows,
    selected,
    rate: rate,
    now: DateTime(2026, 11, 18),
  );

  test('three paid Gloria tasks totaling 14.6 hours never request weekly payroll review', () {
    final rows = gloria(), before = jsonEncode(gloria());
    expect(rows.fold<int>(0, (n, r) => n + (r['actual_minutes'] as int)), 876);
    expect(review(rows, week), isEmpty);
    expect(review(rows, priorWeek), isEmpty);
    expect(jsonEncode(rows), before);
  });

  test('historical unknown settlement stays in its original week without inventing paid evidence', () {
    final row = {
      ...gloria().first,
      'paid': 0,
      'paid_minutes': 0,
      'remaining_minutes': 600,
    };
    final before = jsonEncode(row);
    expect(review([row], week), isEmpty);
    expect(review([row], priorWeek), isEmpty);
    expect(review([row], DateTime(2026, 11, 2)), [row]);
    expect(jsonEncode(row), before);
  });

  test('completion week beats inherited dates; explicit manual work dates remain authoritative', () {
    final old = {
      ...gloria().first,
      'archived_labor': 0,
      'paid': 0,
      'paid_minutes': 0,
      'remaining_minutes': 600,
      'payroll_treatment': 'review',
    };
    expect(review([old], week), isEmpty);
    expect(review([old], priorWeek), [old]);
    expect(
      review([
        {...old, 'date_mode': 'manual'},
      ], week),
      hasLength(1),
    );
  });

  test('new J40 warranty and real conflicts remain reviewable; settled and duplicate rows do not', () {
    final current = warranty(), before = jsonEncode(warranty());
    expect(review([current, ...gloria()], week), [current]);
    final conflict = {
      ...current,
      'payroll_treatment': 'unpaid',
      'assignment_conflict': 1,
    };
    expect(review([conflict], week), [conflict]);
    expect(EmployeeWorkReview.weeklyRows([conflict], week), isEmpty);
    expect(
      review([
        {...current, 'source_active': 0},
      ], week),
      isEmpty,
    );
    expect(
      review([
        {...current, 'recordkeeping_only': true},
      ], week),
      isEmpty,
    );
    expect(
      review([
        {...current, 'duplicate_of_task_id': 'original'},
      ], week),
      isEmpty,
    );
    expect(
      review([
        {...current, 'owner_prior_paid': 1},
      ], week),
      isEmpty,
    );
    expect(
      review([
        {...current, 'paid_minutes': 600, 'remaining_minutes': 0},
      ], week),
      isEmpty,
    );
    final partial = {...current, 'paid_minutes': 120, 'remaining_minutes': 480};
    expect(review([partial], week), [partial]);
    expect(jsonEncode(current), before);
  });

  test('current missing compensation and explicit carry-forward are preserved for review', () {
    final current = {
      ...warranty(),
      'state': 'Done',
      'completed_date': '2026-11-17',
      'actual_minutes': 600,
      'rate_cents': 0,
      'payroll_treatment': 'unpaid',
    };
    expect(review([current], week), [current]);
    expect(
      EmployeeWorkReview.weeklyReviewRows([current], week, rate: (_) => 4000),
      isEmpty,
    );
    final carried = {
      ...current,
      'rate_cents': 4000,
      'payroll_treatment': 'review',
      'carry_week': '2026-11-16',
      'archived_labor': 0,
    };
    expect(review([carried], week), [carried]);
    final historicalCarry = {
      ...carried,
      'completed_date': '2026-11-03',
      'date_mode': 'inherited',
      'work_start_date': '2026-11-02',
      'work_end_date': '2026-11-06',
    };
    expect(review([historicalCarry], week), [historicalCarry]);
    expect(
      review([
        {...historicalCarry, 'source_active': 0},
      ], week),
      isEmpty,
    );
    expect(
      review([
        {...carried, 'carry_week': '2026-11-23'},
      ], week),
      isEmpty,
    );
  });

  Widget screen(
    List<Map<String, dynamic>> rows,
    DateTime selected, {
    String? message,
  }) => MaterialApp(
    home: Scaffold(
      body: WeeklyLaborReview(
        employeeId: 'chris',
        employeeName: 'Chris',
        tasks: rows,
        week: selected,
        embedded: true,
        profileLayout: true,
        savedRateCents: 4000,
        reviewMessage: message,
        advanceBalance: () async => 0,
        paymentHistory: [
          {
            'week': '2026-11-09',
            'operation_id': 'original-payment',
            'work': gloria(),
          },
        ],
        recordPayment: (_, _, _, _, _, _, _, _, _) async {
          fail('Viewing review must never record payment.');
        },
      ),
    ),
  );

  testWidgets(
    'current Payroll hides stale historical review; original paid history remains',
    (tester) async {
      final rows = gloria(), before = jsonEncode(gloria());
      await tester.pumpWidget(
        screen(rows, week, message: 'Historical carry review'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Needs Review'), findsNothing);
      expect(find.text('Historical carry review'), findsNothing);
      expect(find.text('Unpaid Labor (0)'), findsOneWidget);
      expect(find.text('View paid work details'), findsNothing);
      await tester.pumpWidget(screen(rows, priorWeek));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View paid work details'));
      await tester.tap(find.text('View paid work details'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('J-40 · Replace oil separator'),
        findsOneWidget,
      );
      expect(find.textContaining('Needs Review'), findsNothing);
      expect(jsonEncode(rows), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Needs Review counts only genuine current warranty work, not the three old tasks',
    (tester) async {
      final rows = [...gloria(), warranty()],
          before = jsonEncode([...gloria(), warranty()]);
      await tester.pumpWidget(screen(rows, week));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Needs Review (1)'));
      await tester.tap(find.text('Needs Review (1)'));
      await tester.pumpAndSettle();
      expect(find.text('J-40 · New warranty return labor'), findsOneWidget);
      expect(find.textContaining('Replace oil separator'), findsNothing);
      expect(find.textContaining('Replace water pump'), findsNothing);
      expect(find.textContaining('Replace front air struts'), findsNothing);
      expect(find.text('Unpaid Labor (0)'), findsOneWidget);
      expect(jsonEncode(rows), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
