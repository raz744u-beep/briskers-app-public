import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/tasks_workspace.dart';

void main() {
  testWidgets('original TEST Add Recheck targets the selected regular Job',
      (tester) async {
    String? recheckJob;
    String? openedJob;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TasksWorkspace(
          serviceTasks: [
            {
              'job_id': 'actual-job-uuid-24',
              'job_number': 'J-24',
              'source_description': 'Rear differential service',
              'line_id': 'line-24',
              'document_id': 'invoice-6342',
              'status': 'planned',
              'customer_name': 'Test Customer',
              'vehicle_label': 'Test Vehicle',
            },
          ],
          generalTasks: const [],
          allocationsByLine: const {},
          employeeName: (_) => 'Mechanic',
          employeeIds: const [],
          serviceTaskCard: (row) =>
              ListTile(title: Text(row['source_description'] as String)),
          onAddGeneral: () {},
          onGeneralStatus: (_, _) async {},
          onOpenJob: (job) => openedJob = job,
          onEmployeeTap: (_) {},
          onAddRecheck: (job) => recheckJob = job,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('J-24'), findsOneWidget);
    await tester.ensureVisible(find.text('Add Recheck'));
    await tester.tap(find.text('Add Recheck'));
    await tester.pump();
    expect(recheckJob, 'actual-job-uuid-24');
    expect(openedJob, isNull);
    await tester.tap(find.text('J-24'));
    await tester.pump();
    expect(find.text('Add Recheck'), findsNothing);
  });
}
