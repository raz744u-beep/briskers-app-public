import 'dart:convert';

import 'package:briskers_app/screens/payroll/weekly_labor_review_screen.dart';
import 'package:briskers_app/screens/payroll/recorded_weekly_payment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bugs39_recorded_payroll_week_test.dart' show receipt;

void main() {
  final week = DateTime(2026, 11, 9);
  Widget screen(
    List<Map<String, dynamic>> history, {
    List<Map<String, dynamic>> tasks = const [],
    double scale = 1,
    int base = 0,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: WeeklyLaborReview(
          employeeId: 'chris',
          employeeName: 'Chris',
          week: week,
          paymentHistory: history,
          tasks: tasks,
          profileLayout: true,
          embedded: true,
          savedRateCents: 9000,
          weeklyBaseCents: base,
          advanceBalance: () async => 0,
          recordPayment: (_, _, _, _, _, _, _, _, _) async {
            fail('Reading the snapshot must not create a payment.');
          },
        ),
      ),
    ),
  );
  String value(WidgetTester t, String key) =>
      t.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets(
    'paid week shows saved figures and a conspicuous task-detail control, never a zero new payment',
    (t) async {
      final history = [
        receipt(
          'one',
          '2026-11-09',
          480,
          32000,
          adjustment: -200,
          repayment: 800,
        ),
      ];
      final before = jsonEncode(history);
      await t.pumpWidget(screen(history));
      await t.pumpAndSettle();
      expect(find.text('Weekly Payment Summary'), findsOneWidget);
      expect(value(t, 'recorded-paid-hours'), '8.00 hrs');
      expect(value(t, 'recorded-labor-pay'), r'$320.00');
      expect(value(t, 'recorded-adjustment'), r'-$2.00');
      expect(value(t, 'recorded-gross'), r'$318.00');
      expect(value(t, 'recorded-repayment'), r'$8.00');
      expect(value(t, 'recorded-payment-total'), r'$310.00');
      expect(
        find.byKey(const Key('new-weekly-payment-preparation')),
        findsNothing,
      );
      expect(find.byKey(const Key('verify-weekly-payment')), findsNothing);
      final control = find.text('View paid work details');
      await t.ensureVisible(control);
      await t.tap(control);
      await t.pumpAndSettle();
      expect(find.text('J-40 · Oil Separator'), findsOneWidget);
      expect(find.textContaining('8.00 hrs paid'), findsOneWidget);
      expect(find.textContaining('Cash'), findsOneWidget);
      expect(
        t.getTopLeft(control).dy,
        greaterThan(t.getTopLeft(find.byType(RecordedWeeklyPaymentCard)).dy),
      );
      expect(jsonEncode(history), before);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'changing selected week changes the recorded snapshot, not the payment records',
    (t) async {
      final history = [
        receipt('one', '2026-11-09', 480, 32000),
        receipt('two', '2026-11-16', 120, 8000),
      ];
      final before = jsonEncode(history);
      await t.pumpWidget(screen(history));
      await t.pumpAndSettle();
      expect(value(t, 'recorded-payment-total'), r'$320.00');
      await t.tap(find.byTooltip('Next week'));
      await t.pumpAndSettle();
      expect(value(t, 'recorded-paid-hours'), '2.00 hrs');
      expect(value(t, 'recorded-payment-total'), r'$80.00');
      await t.tap(find.byTooltip('Previous week'));
      await t.pumpAndSettle();
      expect(value(t, 'recorded-payment-total'), r'$320.00');
      expect(jsonEncode(history), before);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'partly paid week keeps saved totals separate from the new unpaid preparation',
    (t) async {
      final task = {
        'id': 'unpaid',
        'task_id': 'task',
        'job_id': 'job-56',
        'job_number': 'J-56',
        'description': 'Replace engine',
        'state': 'In Progress',
        'source_active': 1,
        'estimated_minutes': 1200,
        'actual_minutes': 0,
        'remaining_minutes': 720,
        'paid_minutes': 480,
        'paid': 0,
        'rate_cents': 4000,
        'work_start_date': '2026-11-09',
      };
      await t.pumpWidget(
        screen([receipt('one', '2026-11-09', 480, 32000)], tasks: [task]),
      );
      await t.pumpAndSettle();
      expect(value(t, 'recorded-payment-total'), r'$320.00');
      final scroll = find
          .descendant(
            of: find.byKey(const Key('employee-payroll-preparation')),
            matching: find.byType(Scrollable),
          )
          .first;
      await t.scrollUntilVisible(
        find.text('New Payment'),
        180,
        scrollable: scroll,
      );
      expect(
        find.byKey(const Key('new-weekly-payment-preparation')),
        findsOneWidget,
      );
      expect(find.text('Weekly Payment Summary'), findsOneWidget);
      expect(find.text('Unpaid Labor (1)'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'empty week has an explicit no-payment state and fully paid base cannot be prepared again',
    (t) async {
      await t.pumpWidget(screen([]));
      await t.pumpAndSettle();
      expect(find.text('No recorded payments for this week.'), findsOneWidget);
      expect(find.byKey(const Key('verify-weekly-payment')), findsNothing);
      await t.pumpWidget(
        screen([receipt('base', '2026-11-09', 0, 0, base: 80000)], base: 80000),
      );
      await t.pumpAndSettle();
      expect(value(t, 'recorded-payment-total'), r'$800.00');
      expect(find.text('New Payment'), findsNothing);
      expect(find.byKey(const Key('verify-weekly-payment')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final config in [(393.0, 1.0), (320.0, 1.8)]) {
    testWidgets(
      'snapshot remains readable at ${config.$1} width scale ${config.$2}',
      (t) async {
        t.view.physicalSize = Size(config.$1, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          screen([receipt('one', '2026-11-09', 480, 32000)], scale: config.$2),
        );
        await t.pumpAndSettle();
        expect(value(t, 'recorded-payment-total'), r'$320.00');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
