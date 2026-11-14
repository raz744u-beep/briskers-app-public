import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/tasks_workspace.dart';

void main() {
  testWidgets('Rechecks filter excludes ordinary task-first Job work',
      (tester) async {
    final tasks = <Map<String, dynamic>>[
      {
        'job_id': 'job-a', 'job_number': 'J-10',
        'source_description': 'Ordinary task-first job work',
        'source_kind': 'job', 'line_id': 'job-task',
        'status': 'planned',
      },
      {
        'job_id': 'job-a', 'job_number': 'J-10',
        'source_description': 'Separate recheck after repair',
        'source_kind': 'recheck', 'line_id': 'recheck-task',
        'status': 'planned',
      },
      {
        'job_id': 'job-b', 'job_number': 'J-11',
        'source_description': 'Invoice labor task',
        'source_kind': 'invoice', 'document_id': 'invoice-b',
        'line_id': 'invoice-task', 'status': 'planned',
      },
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TasksWorkspace(
        serviceTasks: tasks,
        generalTasks: const [],
        allocationsByLine: const {},
        employeeName: (_) => 'Mechanic',
        employeeIds: const [],
        serviceTaskCard: (row) => ListTile(
          title: Text(row['source_description'] as String)),
        onAddGeneral: () {},
        onGeneralStatus: (_, _) async {},
        onOpenJob: (_) {},
        onEmployeeTap: (_) {},
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ordinary task-first job work'), findsOneWidget);
    expect(find.text('Separate recheck after repair'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle-task-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('Task Type:All Types')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rechecks').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Separate recheck after repair'), findsOneWidget); // Header and expandable details.
    expect(find.text('Ordinary task-first job work'), findsNothing);
    expect(find.text('Invoice labor task'), findsNothing);

    await tester.tap(find.byKey(const Key('toggle-task-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('Task Type:Rechecks')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invoice Labor').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Invoice labor task'), findsOneWidget);
    expect(find.text('Separate recheck after repair'), findsNothing);
  });
}
