import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/app.dart';
import 'package:briskers_app/screens/payroll/approved_task_details.dart';
import 'package:briskers_app/screens/payroll/approved_tasks_ui.dart';
import 'package:briskers_app/screens/payroll/payroll_review_widgets.dart';
import 'package:briskers_app/screens/payroll/service_task_editor.dart';
import 'bugs35_shared_design_test.dart' show capture;
import 'support/handoff_qa_fonts.dart';

void main() {
  setUp(loadHandoffFonts);
  void size(WidgetTester t) {
    t.view.physicalSize = const Size(412, 892);
    t.view.devicePixelRatio = 1;
    t.view.padding = const FakeViewPadding(top: 24, bottom: 32);
    t.view.viewPadding = const FakeViewPadding(top: 24, bottom: 32);
    addTearDown(t.view.reset);
  }

  testWidgets(
    'J-56 final Task Details keeps job and invoice, compacts hours and places status in header',
    (t) async {
      size(t);
      final key = GlobalKey();
      var edit = 0, descriptionEdit = 0, job = 0, invoice = 0, finish = 0;
      var task = <String, dynamic>{
        'id': 'task-engine',
        'job_id': 'j56',
        'job_number': 'J-56',
        'customer_name': 'Terrance Sanders',
        'vehicle_label': '2016 Mercedes C300',
        'invoice_id': 'invoice6376',
        'invoice_number': '6376',
        'task_name': 'Replace engine',
        'description': 'Replace engine',
        'status': 'in_progress',
        'priority': 'High',
        'work_start_date': '2026-11-12',
        'work_end_date': '2026-11-19',
      };
      var allocations = <Map<String, dynamic>>[
        {
          'id': 'chris-engine',
          'employee_id': 'chris',
          'state': 'In Progress',
          'estimated_minutes': 1200,
          'actual_minutes': 0,
          'paid_minutes': 0,
          'remaining_minutes': 1200,
          'paid': 0,
          'source_active': 1,
        },
      ];
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: BriskersApp.applicationTheme,
            home: ApprovedTaskDetails(
              initialTask: task,
              allocations: allocations,
              general: false,
              employeeName: (_) => 'Chris',
              reload: () async => (task: task, allocations: allocations),
              onEdit: () async {
                edit++;
              },
              onEditDescription: () async {
                descriptionEdit++;
              },
              onJob: () => job++,
              onInvoice: () => invoice++,
              onPriority: (p) async {
                task = {...task, 'priority': p};
              },
              onProgress: (done) async {
                finish++;
                task = {...task, 'status': 'done'};
                allocations = [
                  {...allocations.single, 'state': 'Done'},
                ];
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Job J-56'), findsOneWidget);
      expect(find.text('Terrance Sanders'), findsOneWidget);
      expect(find.text('Invoice #6376'), findsOneWidget);
      final header = t.getRect(find.byKey(const Key('task-details-header')));
      final status = t.getRect(find.byKey(const Key('task-details-status')));
      expect(
        header.contains(status.topLeft) && header.contains(status.bottomRight),
        true,
      );
      expect(status.center.dx, greaterThan(header.center.dx));
      expect(find.byType(TaskStatusPill), findsOneWidget);
      final name = find.byKey(const Key('task-details-name'));
      expect(t.getTopLeft(name).dy, greaterThanOrEqualTo(header.bottom));
      expect(t.widget<Text>(name).style!.fontSize, 20);
      expect(find.text('Task Name'), findsNothing);
      expect(
        t.getCenter(name).dy,
        closeTo(t.getCenter(find.byType(TaskPriorityPill)).dy, 1),
      );
      final tiles = find.byType(LaborBalanceTiles);
      expect(t.getSize(tiles).height, 56);
      final label = t.getRect(find.text('Total'));
      final value = t.getRect(
        find.descendant(of: tiles, matching: find.text('20.00 h')).first,
      );
      expect(value.top - label.bottom, inInclusiveRange(0, 3));
      expect(find.text('View Job').hitTestable(), findsOneWidget);
      expect(
        t.getBottomRight(find.widgetWithText(OutlinedButton, 'View Job')).dy,
        lessThan(860),
      );
      final shadows = debugDisableShadows;
      debugDisableShadows = false;
      void paint(RenderObject r) {
        r.markNeedsPaint();
        r.visitChildren(paint);
      }

      paint(key.currentContext!.findRenderObject()!);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pumpAndSettle();
      await capture(t, key, 'j56-task-details-final');
      debugDisableShadows = shadows;
      await t.tap(find.byTooltip('Edit description'));
      await t.pumpAndSettle();
      expect(descriptionEdit, 1);
      expect(edit, 0);
      await t.tap(find.text('Edit Task'));
      await t.pumpAndSettle();
      expect(edit, 1);
      await t.tap(find.text('View Job'));
      await t.tap(find.text('View Invoice'));
      expect(job, 1);
      expect(invoice, 1);
      await t.tap(find.text('Finish Task'));
      await t.pumpAndSettle();
      expect(finish, 1);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Finish Task'), findsNothing);
      t.view.physicalSize = const Size(360, 640);
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(find.text('Edit Task')),
        alignment: 0.5,
      );
      await t.pumpAndSettle();
      expect(find.text('Edit Task').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'paid task editor saves name and description independently without altering assignments or dates',
    (t) async {
      size(t);
      ServiceTaskDraft? saved;
      await t.pumpWidget(
        MaterialApp(
          theme: BriskersApp.applicationTheme,
          home: ServiceTaskEditor(
            editing: true,
            statusLocked: true,
            payrollLocked: true,
            jobs: const [
              {
                'id': 'j56',
                'job_number': 'J-56',
                'customer_name': 'Terrance Sanders',
                'vehicle_label': '2016 Mercedes C300',
                'status': 'closed',
              },
            ],
            employees: const [
              {'id': 'chris', 'name': 'Chris'},
            ],
            initial: ServiceTaskDraft(
              job: 'j56',
              taskName: 'Replace engine',
              description: 'Original detailed diagnosis',
              mechanics: [
                TaskMechanicDraft(
                  'chris',
                  1200,
                  originalEmployee: 'chris',
                  locked: true,
                ),
              ],
              start: '2026-11-12',
              end: '2026-11-19',
              priority: 'High',
              status: 'Done',
              treatment: 'preserve',
            ),
            save: (v) async {
              saved = v;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('task-description')),
        'Corrected detailed diagnosis',
      );
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('task-name')))
            .controller!
            .text,
        'Replace engine',
      );
      await t.tap(find.text('Save Task'));
      await t.pumpAndSettle();
      expect(saved!.taskName, 'Replace engine');
      expect(saved!.description, 'Corrected detailed diagnosis');
      expect(saved!.status, 'Done');
      expect(saved!.treatment, 'preserve');
      expect(saved!.mechanics.single.minutes, 1200);
      expect(saved!.datesEdited, false);
      expect(t.takeException(), isNull);
    },
  );
}
