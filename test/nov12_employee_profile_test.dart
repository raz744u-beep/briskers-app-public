import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/employee_work_review.dart';
import 'package:briskers_app/screens/payroll/weekly_labor_review_screen.dart';
import 'bugs35_shared_design_test.dart' show capture;

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final entry in {
      'Roboto': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      'MaterialIcons':
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final f = File(entry.value);
      if (await f.exists()) {
        await (FontLoader(entry.key)..addFont(
              Future.value(ByteData.sublistView(await f.readAsBytes())),
            ))
            .load();
      }
    }
  });
  Map<String, dynamic> task(String id, String status, int minutes) => {
    'id': id,
    'employee_id': 'chris',
    'job_number': 'J-54',
    'customer_name': 'Nathan Hogue',
    'description': 'Repair $id',
    'state': status,
    'actual_minutes': status == 'Done' ? minutes : 0,
    'estimated_minutes': minutes,
    'remaining_minutes': status == 'Done' ? minutes : 0,
    'completed_date': status == 'Done' ? '2026-11-10' : null,
    'invoice_date': '2026-11-09',
    'rate_cents': 4000,
    'paid_minutes': 0,
    'paid': 0,
    'source_active': 1,
  };
  testWidgets(
    'Work Review is read-only, counts real allocations and navigates weeks',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      var week = DateTime(2026, 11, 9);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            home: Scaffold(
              appBar: AppBar(title: const Text('Employee Profile · Chris')),
              body: StatefulBuilder(
                builder: (context, set) => EmployeeWorkReview(
                  week: week,
                  rows: [
                    task('oil', 'Done', 60),
                    task('brake', 'Done', 60),
                    task('pump', 'Done', 390),
                    task('filters', 'In Progress', 60),
                    task('plug', 'Open', 90),
                  ],
                  jobs: const [
                    {
                      'id': 'j54',
                      'job_number': 'J-54',
                      'customer_name': 'Nathan Hogue',
                      'vehicle_label': '2018 Mercedes E300',
                      'status': 'in_progress',
                    },
                  ],
                  onWeekChanged: (v) => set(() => week = v),
                  onJob: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Labor This Week · 5 tasks'), findsOneWidget);
      expect(find.text('Assigned hours: 11.00 hrs'), findsOneWidget);
      expect(find.text('Completed\n8.50 hrs'), findsOneWidget);
      expect(find.text('In Progress\n1.00 hrs'), findsOneWidget);
      expect(find.text('New Task'), findsNothing);
      expect(find.text('Verify Weekly Payment'), findsNothing);
      await capture(tester, key, 'nov12-work-review');
      await tester.tap(find.byTooltip('Previous work week'));
      await tester.pumpAndSettle();
      expect(find.text('Labor This Week · 0 tasks'), findsOneWidget);
      expect(find.text('Currently Assigned Jobs (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Payroll shows 10 unpaid warranty hours at 40, hides irrelevant history, saves draft and verifies net',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      Map<String, double>? draft;
      var recorded = 0;
      final row = {
        ...task('warranty', 'Done', 600),
        'job_number': 'J-40',
        'customer_name': 'Gloria Johnson',
        'description': 'Oil Separator',
        'carry_week': '2026-11-09',
      };
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            home: Scaffold(
              appBar: AppBar(title: const Text('Employee Profile · Chris')),
              body: WeeklyLaborReview(
                employeeId: 'chris',
                employeeName: 'Chris',
                tasks: [row],
                advanceBalance: () async => 5000,
                week: DateTime(2026, 11, 9),
                profileLayout: true,
                savedRateCents: 4000,
                paymentHistory: [
                  {
                    'week': '2026-11-02',
                    'work': [row],
                  },
                ],
                saveDraft:
                    (week, selected, adjustment, repayment, reason) async {
                      draft = selected;
                    },
                recordPayment:
                    (
                      week,
                      date,
                      method,
                      selected,
                      adjustment,
                      repayment,
                      net,
                      reason,
                      base,
                    ) async {
                      recorded++;
                      expect(selected.single['id'], 'warranty');
                      expect(selected.single['pay_minutes'], 600);
                      expect(net, 37000);
                      expect(adjustment, 2000);
                      expect(repayment, 5000);
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unpaid Labor (1)'), findsOneWidget);
      expect(find.text(r'$40.00 / hr'), findsOneWidget);
      expect(find.text('Previously Paid Work'), findsNothing);
      expect(find.textContaining('Needs Review'), findsNothing);
      await capture(tester, key, 'nov12-payroll-preparation');
      await tester.ensureVisible(find.text('Save (Draft)'));
      await tester.tap(find.text('Save (Draft)'));
      await tester.pumpAndSettle();
      expect(draft, {'warranty': 10.0});
      await tester.ensureVisible(find.text('Adjustments & repayment'));
      await tester.tap(find.text('Adjustments & repayment'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Adjustment (+/−)'),
        '20',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Repayment from this payment'),
        '50',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Adjustment reason'),
        'Owner approved bonus',
      );
      await tester.pumpAndSettle();
      expect(find.text(r'Payment Total: $370.00'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Verify Weekly Payment'));
      await tester.tap(find.text('Verify Weekly Payment'));
      await tester.pumpAndSettle();
      expect(find.text(r'Calculated labor: $400.00'), findsOneWidget);
      expect(recorded, 0);
      await tester.ensureVisible(find.text('Record payment'));
      await tester.tap(find.text('Record payment'));
      await tester.pumpAndSettle();
      expect(recorded, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Previously Paid Work contains only the selected payroll week', (
    tester,
  ) async {
    final row = task('this-week', 'Done', 60);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklyLaborReview(
            employeeId: 'chris',
            employeeName: 'Chris',
            tasks: const [],
            advanceBalance: () async => 0,
            week: DateTime(2026, 11, 9),
            profileLayout: true,
            savedRateCents: 4000,
            paymentHistory: [
              {
                'week': '2026-11-09',
                'work': [row],
              },
              {
                'week': '2026-11-02',
                'work': [
                  {...row, 'description': 'Already paid last week'},
                ],
              },
            ],
            recordPayment:
                (
                  week,
                  date,
                  method,
                  selected,
                  adjustment,
                  repayment,
                  net,
                  reason,
                  base,
                ) async {
                  fail('No unpaid labor can be verified');
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Previously Paid Work'));
    await tester.tap(find.text('Previously Paid Work'));
    await tester.pumpAndSettle();
    expect(find.text('J-54 · Repair this-week'), findsOneWidget);
    expect(find.textContaining('Already paid last week'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Verify Weekly Payment'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
