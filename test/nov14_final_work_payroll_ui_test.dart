import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/app.dart';
import 'package:briskers_app/services/local_payroll_repository.dart' show VerifiedPayrollWeek;
import 'package:briskers_app/screens/payroll/approved_tasks_ui.dart';
import 'package:briskers_app/screens/payroll/approved_task_details.dart';
import 'package:briskers_app/screens/payroll/employee_work_review.dart';
import 'package:briskers_app/screens/payroll/payroll_review_widgets.dart';
import 'package:briskers_app/screens/payroll/historical_expense_review.dart';
import 'package:briskers_app/screens/payroll/weekly_labor_review_screen.dart';
import 'bugs35_shared_design_test.dart' show capture;
import 'support/handoff_qa_fonts.dart';

void main() {
  setUp(loadHandoffFonts);
  void size(WidgetTester t, {double width = 412}) {
    t.view.physicalSize = Size(width, 915);
    t.view.devicePixelRatio = 1;
    t.view.padding = const FakeViewPadding(top: 24, bottom: 32);
    t.view.viewPadding = const FakeViewPadding(top: 24, bottom: 32);
    addTearDown(t.view.reset);
  }

  Future<void> shot(WidgetTester t, GlobalKey key, String name) async {
    final old = debugDisableShadows;
    void repaint(RenderObject r) {
      r.markNeedsPaint();
      r.visitChildren(repaint);
    }

    try {
      debugDisableShadows = false;
      repaint(key.currentContext!.findRenderObject()!);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pumpAndSettle();
      await capture(t, key, 'final-$name');
    } finally {
      debugDisableShadows = old;
      repaint(key.currentContext!.findRenderObject()!);
      await t.pump();
    }
  }

  final week = DateTime(2026, 11, 9);
  Map<String, dynamic> row({
    String id = 'engine',
    String state = 'In Progress',
    int assigned = 1200,
    int paid = 480,
  }) => {
    'id': id,
    'task_id': 'task-$id',
    'employee_id': 'chris',
    'job_id': 'j56',
    'job_number': 'J-56',
    'customer_name': 'Terrance Sanders',
    'vehicle_label': '2016 Mercedes C300',
    'description': id == 'engine' ? 'Replace engine' : 'Oil Change',
    'state': state,
    'estimated_minutes': assigned,
    'actual_minutes': state == 'Done' ? assigned : 0,
    'remaining_minutes': assigned - paid,
    'paid_minutes': paid,
    'paid': paid == assigned ? 1 : 0,
    'rate_cents': 4000,
    'completed_date': state == 'Done' ? '2026-11-12' : null,
    'work_start_date': '2026-11-09',
    'work_end_date': '2026-11-13',
    'source_active': 1,
    'priority': 'Normal',
  };
  Widget app(Widget child, {GlobalKey? key}) => RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: BriskersApp.applicationTheme,
      home: child,
    ),
  );

  testWidgets('Weekly Labor shows remaining hours in equal-width columns', (t) async {
    size(t, width: 360);
    await t.pumpWidget(app(Scaffold(body: EmployeeWorkReview(
      week: week,
      rows: [row()],
      jobs: const [],
      employeeName: 'Chris',
      onWeekChanged: (_) {},
      onJob: (_) {},
      paidMinutesThisWeek: 0,
    ))));
    await t.pumpAndSettle();
    final note = find.text('(includes 8.00 hrs paid on these tasks)');
    await t.ensureVisible(find.text('In Progress\n12.00 hrs'));
    await t.pumpAndSettle();

    final metrics = [
      find.text('Completed\n0.00 hrs'),
      find.text('In Progress\n12.00 hrs'),
      find.text('Not Started\n0.00 hrs'),
    ];
    final widths = <double>[];
    for (final metric in metrics) {
      expect(t.widget<Text>(metric).style?.fontSize, 16);
      expect(find.ancestor(of: metric, matching: find.byType(FittedBox)), findsNothing);
      final column = find.ancestor(of: metric, matching: find.byType(Column)).first;
      final columnParent = find.ancestor(of: column, matching: find.byType(Padding)).first;
      widths.add(t.getSize(columnParent).width);
      expect(t.getTopLeft(metric).dy, t.getTopLeft(metrics.first).dy);
      expect(t.widget<Icon>(find.descendant(of: column, matching: find.byType(Icon))).size, 18);
    }
    expect(widths[1], closeTo(widths[0], 0.01));
    expect(widths[2], closeTo(widths[0], 0.01));
    expect(note, findsNothing);
    expect(find.text('Total assigned: 12.00 hrs'), findsOneWidget);
    expect(find.text('Total Paid This Week'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Corrected cash balance is displayed for the recorded week', (t) async {
    size(t, width: 360);
    await t.pumpWidget(app(Scaffold(body: WorkPayrollSummary(
      week: week,
      rows: [row()],
      recorded: (minutes: 480, netCents: 30000),
      paymentBalance: 2000,
      loadDraft: (_) async => null,
      onReview: () {},
      revision: 0,
    ))));
    await t.pumpAndSettle();
    expect(find.text('Partially paid'), findsOneWidget);
    expect(find.text('Recorded hours: 8.00'), findsOneWidget);
    expect(find.text(r'$300.00'), findsOneWidget);
    expect(find.text(r'Remaining payment · $20.00'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'Work summary uses only selected-week saved draft or recorded payroll',
    (t) async {
      size(t);
      Map<String, dynamic>? draft;
      var revision = 0;
      var reviewed = 0;
      Widget summary(DateTime w, Map<DateTime, VerifiedPayrollWeek> payments) =>
          Scaffold(
            body: WorkPayrollSummary(
              week: w,
              rows: [row()],
              recorded: payments[w],
              loadDraft: (_) async => draft,
              onReview: () => reviewed++,
              revision: revision,
            ),
          );
      await t.pumpWidget(app(summary(week, {})));
      await t.pumpAndSettle();
      expect(find.text('Not calculated'), findsOneWidget);
      expect(find.text(r'$800.00'), findsNothing);
      draft = {
        'hours': {'engine': 8.0},
        'adjustment': 0,
        'repayment': 0,
      };
      revision++;
      await t.pumpWidget(app(summary(week, {})));
      await t.pumpAndSettle();
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text(r'$320.00'), findsOneWidget);
      await t.tap(find.text('Review & Pay'));
      expect(reviewed, 1);
      draft = null;
      revision++;
      await t.pumpWidget(
        app(
          summary(week, {week: (minutes: 1260, netCents: 87000)}),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Recorded hours: 21.00'), findsOneWidget);
      expect(find.text(r'$870.00'), findsOneWidget);
      expect(find.text('Nov 9 – Nov 13, 2026'), findsOneWidget);
      await t.pumpWidget(
        app(
          summary(DateTime(2026, 11, 16), {week: (minutes: 1260, netCents: 87000)}),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Not calculated'), findsOneWidget);
      expect(find.text(r'$870.00'), findsNothing);
      expect(find.text('Nov 16 – Nov 20, 2026'), findsOneWidget);
    },
  );
  testWidgets(
    'Work opens exact assigned task, remains read only and renders final overview',
    (t) async {
      size(t);
      final key = GlobalKey();
      String? opened;
      final rows = [
        row(paid: 0),
        row(id: 'oil', state: 'Done', assigned: 60, paid: 0),
      ];
      Widget profile(int selected) => app(
          DefaultTabController(
            length: 4,
            initialIndex: selected,
            child: Scaffold(
              appBar: const ApprovedTasksHeader(title: 'Employee Profile'),
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12,8,12,10),
                    child: ApprovedEmployeeIdentity(
                      name: 'Chris',
                      role: 'Mechanic',
                      active: true,
                      onDetails: () {},
                    ),
                  ),
                  const ApprovedProfileTabs(),
                  Expanded(
                    child: TabBarView(children: [
                      SafeArea(top: false, child: Builder(builder: (context) => EmployeeWorkReview(
                      week: week,
                      rows: rows,
                      jobs: const [],
                      employeeName: 'Chris',
                      onWeekChanged: (_) {},
                      onJob: (_) {},
                      onTask: (task) => opened = task['task_id'],
                      payrollSummary: WorkPayrollSummary(
                        week: week,
                        rows: rows,
                        loadDraft: (_) async => null,
                        onReview: () => DefaultTabController.of(context).animateTo(1),
                        revision: 0,
                      ),
                    ))),
                      SafeArea(top: false, child: WeeklyLaborReview(
                        employeeId: 'chris', employeeName: 'Chris',
                        week: week, tasks: rows, profileLayout: true,
                        savedRateCents: 4000, advanceBalance: () async => 0,
                        recordPayment: (a,b,c,d,e,f,g,h,i) async => fail('Read-only visual review cannot create payments'),
                      )),
                      const SizedBox(), const SizedBox(),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          key: key,
        );
      await t.pumpWidget(profile(0));
      await t.pumpAndSettle();
      expect(find.text('Currently Assigned Tasks (1)'), findsOneWidget);
      expect(find.text('Work Review (Read Only)'), findsNothing);
      expect(find.text('Currently Assigned Jobs'), findsNothing);
      expect(find.text('New Task'), findsNothing);
      expect(find.text('Verify Weekly Payment'), findsNothing);
      expect(find.text('Not calculated'), findsOneWidget);
      await t.tap(find.text('Replace engine').first);
      expect(opened, 'task-engine');
      final list=t.widget<ListView>(find.byKey(const Key('employee-work-review')));
      final children=(list.childrenDelegate as SliverChildListDelegate).children;
      expect(children,hasLength(4),reason:'Calendar, assigned tasks, labor summary and payroll summary only');
      expect(children.last,isA<WorkPayrollSummary>());
      expect(find.text('Oil Change'),findsNothing,reason:'Completed labor must not be repeated below Work summary');
      expect(find.text('Weekly Labor'),findsOneWidget);
      expect(find.text('Total assigned: 21.00 hrs'),findsOneWidget,reason:'Unpaid work retains every allocation in weekly totals');
      expect(find.text('Review & Pay').hitTestable(),findsOneWidget);
      final button=find.widgetWithText(FilledButton,'Review & Pay');
      final summary=find.byKey(const Key('work-payroll-summary'));
      // The existing card has 12 px inside its bottom edge beneath the button.
      expect(t.getBottomRight(find.descendant(of:summary,matching:find.byType(Material)).first).dy-t.getBottomRight(button).dy, inInclusiveRange(12,16));
      final stripe=find.byKey(const ValueKey('profile-tabs-stripe'));
      final fixedBounds=t.getRect(stripe);
      await shot(t, key, 'work-overview');
      await t.tap(find.text('Review & Pay'));await t.pumpAndSettle();
      expect(t.widget<ColoredBox>(stripe).color,const Color(0xFF176B40));
      expect(find.text('Oil Change'),findsOneWidget,reason:'Payroll retains individual labor selection');
      expect(find.byType(Checkbox),findsWidgets);
      await t.drag(find.byKey(const Key('employee-payroll-preparation')),const Offset(0,-400));await t.pumpAndSettle();
      expect(t.getRect(stripe),fixedBounds,reason:'Stripe stays pinned while Payroll scrolls');
      await t.tap(find.text('Work'));await t.pumpAndSettle();
      expect(t.widget<ColoredBox>(stripe).color,const Color(0xFF2479C6));
      // A smaller viewport must scroll to the same end without moving the tab row.
      t.view.physicalSize=const Size(360,640);await t.pumpAndSettle();
      final smallStripe=t.getRect(stripe);
      await t.drag(find.byKey(const Key('employee-work-review')),const Offset(0,-500));await t.pumpAndSettle();
      expect(find.text('Review & Pay').hitTestable(),findsOneWidget);
      expect(t.getRect(stripe),smallStripe);
      expect(find.text('Oil Change'),findsNothing);
      expect(rows,hasLength(2));expect(rows.last['remaining_minutes'],60);
      expect(t.takeException(), isNull);
      t.view.physicalSize = const Size(844, 390);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Weekly Labor'));
      await t.pumpAndSettle();
      expect(find.text('Weekly Labor').hitTestable(), findsOneWidget);
      expect(t.widget<Text>(find.text('Weekly Labor')).maxLines, 1);
      expect(t.takeException(), isNull);
      // Capture Payroll from a fresh route to avoid cached headless header layers.
      await t.pumpWidget(const SizedBox.shrink());await t.pumpAndSettle();
      t.view.physicalSize=const Size(412,915);
      await t.pumpWidget(profile(1));await t.pumpAndSettle();
      await shot(t,key,'payroll-full-width-stripe');
      expect(t.takeException(),isNull);
    },
  );
  testWidgets(
    'Task Details shows independent actual mechanic balances and saved history',
    (t) async {
      size(t);
      final key = GlobalKey();
      final task = {
        ...row(),
        'id': 'task-engine',
        'status':'in_progress',
        'job_status': 'in_progress',
        'invoice_id': 'invoice',
        'invoice_number': '6376',
      };
      final allocations = [
        {
          ...row(),
          'payment_history': [
            {
              'verified_date': '2026-11-13',
              'minutes': 480,
              'amount': 32000,
              'method': 'Cash',
            },
          ],
        },
        {...row(id: 'kam', assigned: 300, paid: 0), 'employee_id': 'kam'},
      ];
      await t.pumpWidget(
        app(
          ApprovedTaskDetails(
            initialTask: task,
            allocations: allocations,
            general: false,
            employeeName: (id) => id == 'kam' ? 'Kam' : 'Chris',
            reload: () async => (task: task, allocations: allocations),
            onEdit: () async {},
            onPriority: (_) async {},
            onProgress: (_) async {},
            onJob: () {},
            onInvoice: () {},
          ),
          key: key,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('20.00 h'), findsWidgets);
      expect(find.text('8.00 h'), findsOneWidget);
      expect(find.text('12.00 h'), findsOneWidget);
      expect(find.text('Payroll · Kam'), findsOneWidget);
      expect(find.textContaining(r'$320.00'), findsOneWidget);
      expect(find.text('In Progress'), findsWidgets);
      await shot(t, key, 'task-payment-details');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Payable Hours accepts hundredths, rejects invalid amounts and has no stepper',
    (t) async {
      size(t);
      final key = GlobalKey();
      double? saved;
      await t.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await showDialog<double>(
                    context: context,
                    builder: (_) => PayableHoursDialog(
                      task: row(),
                      selected: 8,
                      total: 20,
                      paid: 8,
                      remaining: 12,
                    ),
                  );
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
          key: key,
        ),
      );
      await t.tap(find.text('Open editor'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      for (final value in ['1.25', '3.60', '8.75', '0.00']) {
        await t.enterText(find.byKey(const Key('payable-hours-input')), value);
        await t.pumpAndSettle();
        expect(
          t
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
              .onPressed,
          isNotNull,
        );
      }
      for (final value in ['12.01', '-1', '1.234', 'NaN']) {
        await t.enterText(find.byKey(const Key('payable-hours-input')), value);
        await t.pumpAndSettle();
        expect(
          t
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
              .onPressed,
          isNull,
        );
      }
      await t.enterText(find.byKey(const Key('payable-hours-input')), '8.75');
      await t.pumpAndSettle();
      t.testTextInput.hide();
      await shot(t, key, 'payable-hours');
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Save'));
      await t.pumpAndSettle();
      expect(t.getBottomRight(find.text('Save')).dy, lessThan(615));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(saved, 8.75);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Historical review excludes unrelated payees, shows cents and expands real saved fields',
    (t) async {
      size(t);
      final key = GlobalKey();
      final access = ValueNotifier(true);
      addTearDown(access.dispose);
      await t.pumpWidget(
        app(
          HistoricalExpenseReview(
            initialSearch: 'Chris',
            access: access,
            canView: () => access.value,
            source: 'Expenses saved on this device',
            search: (q, o, l) async => [
              {
                'id': 'chris',
                'counterparty': 'Chris',
                'amount': 200,
                'currency_code': 'USD',
                'transaction_date': '2026-11-06',
                'category': 'Labor',
                'account': 'Cash',
                'remarks': 'Original saved entry',
              },
              {
                'id': 'wrong',
                'counterparty': 'Worldpac',
                'amount': 124.55,
                'transaction_date': '2026-11-06',
                'category': 'Parts',
                'remarks': 'Shop filters',
              },
            ],
          ),
          key: key,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Worldpac'), findsNothing);
      expect(find.text(r'$200.00'), findsOneWidget);
      expect(find.text('Nov 6, 2026'), findsOneWidget);
      await t.tap(find.byType(ExpansionTile));
      await t.pumpAndSettle();
      expect(find.text('Original saved entry'), findsOneWidget);
      await shot(t, key, 'historical-expenses');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Payroll progress hours require selection; payable/adjustments save only draft and render',
    (t) async {
      size(t);
      final key = GlobalKey();
      Map<String, double>? saved;
      var authorized = 0;
      await t.pumpWidget(
        app(
          Scaffold(
            appBar: const ApprovedTasksHeader(title: 'Employee Profile'),
            body: WeeklyLaborReview(
              employeeId: 'chris',
              employeeName: 'Chris',
              tasks: [
                row(paid: 0),
                row(id: 'oil', state: 'Done', assigned: 60, paid: 0),
              ],
              week: week,
              profileLayout: true,
              savedRateCents: 4000,
              advanceBalance: () async => 5000,
              recordPayment: (a, b, c, d, e, f, g, h, i) async {
                authorized++;
              },
              saveDraft: (w, h, a, r, reason) async {
                saved = h;
              },
              onOpenTask: (_) async {},
            ),
          ),
          key: key,
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widgetList<Checkbox>(find.byType(Checkbox))
            .where((x) => x.value == true),
        hasLength(1),
      );
      await t.tap(find.text('Replace engine'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Payable Hours'));
      await t.tap(find.text('Payable Hours'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('payable-hours-input')), '8.00');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(saved!['engine'], 8);
      expect(authorized, 0);
      await shot(t, key, 'payroll-expanded');
      await t.scrollUntilVisible(
        find.text('Adjustments & repayment'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Adjustments & repayment'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Adjustment (+/−)'),
        '20',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Repayment from this payment'),
        '50',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Adjustment reason'),
        'Owner bonus',
      );
      await t.pumpAndSettle();
      expect(find.text(r'Payment Total: $330.00'), findsOneWidget);
      t.testTextInput.hide();
      await shot(t, key, 'adjustments');
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await t.pumpAndSettle();
      expect(t.getBottomRight(find.text('Apply')).dy, lessThan(615));
      await t.tap(find.text('Apply'));
      await t.pumpAndSettle();
      expect(authorized, 0);
      expect(saved!['engine'], 8);
      expect(t.takeException(), isNull);
    },
  );
}
