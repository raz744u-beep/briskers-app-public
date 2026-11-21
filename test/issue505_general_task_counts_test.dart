import 'package:briskers_app/screens/payroll/employee_work_review.dart';
import 'package:briskers_app/screens/payroll/tasks_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Map<String, dynamic> labor(String id, String state, int minutes) => {
        'id': id,
        'task_id': id,
        'employee_id': 'chris',
        'job_id': 'job22',
        'job_number': 'J-22',
        'customer_name': 'Daniel Schenck',
        'description': id == 'oil' ? 'Check for oil leaks' : 'Completed labor',
        'state': state,
        'status': state == 'Done' ? 'done' : 'planned',
        'estimated_minutes': minutes,
        'actual_minutes': state == 'Done' ? minutes : 0,
        'remaining_minutes': state == 'Done' ? 0 : minutes,
        'paid_minutes': 0,
        'source_active': 1,
        'priority': 'Normal',
        'work_start_date': '2026-11-16',
        'work_end_date': '2026-11-20',
      };

  Map<String, dynamic> general(int id, String status, {String job = 'job22'}) => {
        'id': id,
        'employee_id': 'chris',
        'job_id': job,
        'job_number': job == 'job22' ? 'J-22' : 'J-99',
        'customer_name': 'Daniel Schenck',
        'description': 'Call if you have any questions',
        'category': 'General',
        'status': status,
        'priority': 'Normal',
      };

  testWidgets('Employee Work counts active Labor and General separately; General has no payroll hours',
      (tester) async {
    phone(tester);
    Map<String, dynamic>? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmployeeWorkReview(
          week: DateTime(2026, 11, 16),
          employeeId: 'chris',
          employeeName: 'Chris',
          rows: [labor('oil', 'Open', 150), labor('done', 'Done', 60)],
          generalTasks: [general(71, 'planned'), general(72, 'done'),
            {...general(73, 'planned'), 'employee_id': 'kam'}],
          jobs: const [],
          onWeekChanged: (_) {},
          onJob: (_) {},
          onGeneralTask: (row) => opened = row,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Currently Assigned Tasks (2)'), findsOneWidget);
    expect(find.text('Labor: 1 · General: 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('assigned-general-task-71')), findsOneWidget);
    expect(find.byKey(const ValueKey('assigned-general-task-72')), findsNothing);
    expect(find.byKey(const ValueKey('assigned-general-task-73')), findsNothing);
    expect(find.textContaining('No payroll hours'), findsOneWidget);
    // The only 2.50 hours counted are the active Labor allocation;
    // completed Labor and General Tasks do not inflate this week's hours.
    expect(find.text('Total assigned: 2.50 hrs'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('assigned-general-task-71')));
    await tester.tap(find.byKey(const ValueKey('assigned-general-task-71')));
    expect(opened?['id'], 71);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Task category counts include Done and ignore search/status filters',
      (tester) async {
    phone(tester);
    final service = [
      {'line_id': 'a', 'job_id': 'job22', 'source_description': 'Oil', 'status': 'planned'},
      {'line_id': 'b', 'job_id': 'job22', 'source_description': 'Timing', 'status': 'done'},
      {'line_id': 'c', 'job_id': 'job22', 'source_description': 'Turbo', 'status': 'done'},
      {'line_id': 'other', 'job_id': 'other', 'source_description': 'Other', 'status': 'planned'},
    ];
    final generalTasks = [general(71, 'planned'), general(72, 'done', job: 'other')];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TasksWorkspace(
        scopedJob: 'job22',
        serviceTasks: service,
        generalTasks: generalTasks,
        allocationsByLine: const {},
        employeeName: (_) => 'Chris',
        employeeIds: const ['chris'],
        serviceTaskCard: (_) => const SizedBox(height: 32),
        onAddGeneral: () {},
        onGeneralStatus: (_, __) async {},
        onOpenJob: (_) {},
        onEmployeeTap: (_) {},
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('service-tasks-count')), findsOneWidget);
    expect(find.byKey(const ValueKey('general-tasks-count')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('general-tasks-tab')));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'nothing matches');
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
