import 'package:briskers_app/services/job_task_summary.dart';
import 'package:briskers_app/widgets/job_list_approved_card.dart';
import 'package:briskers_app/screens/payroll/tasks_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('job status, invoice link, and task action occupy their approved rows', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opens = 0;
    var starts = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: JobListApprovedCard(
      job: const {'status': 'in_progress'},
      number: 'J-60', customer: 'Glenn Smith', invoiceNumber: '6380',
      vehicle: '2017 Jaguar XF', description: 'Pressure test cooling system',
      mechanic: 'Kam', employee: 'Kam', mechanicMinutes: const {'Kam': 120},
      progress: const JobTaskProgress(0, 4),
      statusControl: const Text('In progress'),
      onOpen: () => opens++,
      onOpenInvoice: () {},
      taskAction: FilledButton(onPressed: () => starts++, child: const Text('Start')),
    ))));
    final name = tester.getCenter(find.text('J-60  Glenn Smith'));
    final status = tester.getCenter(find.text('In progress'));
    final vehicle = tester.getCenter(find.text('2017 Jaguar XF'));
    final invoice = tester.getCenter(find.text('Invoice #6380'));
    expect((name.dy - status.dy).abs(), lessThan(3));
    expect((vehicle.dy - invoice.dy).abs(), lessThan(3));
    expect(status.dx, greaterThan(name.dx));
    expect(invoice.dx, greaterThan(vehicle.dx));
    expect(tester.getCenter(find.text('Start')).dx,
        greaterThan(tester.getCenter(find.text('Kam · 2.0 hrs')).dx));
    await tester.tap(find.text('Start'));
    expect(starts, 1);
    expect(opens, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed tasks can be shown and switched back while retaining search', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TasksWorkspace(
      initialGeneral: true,
      serviceTasks: const [],
      generalTasks: const [
        {'id': 1, 'description': 'Call Gloria', 'status': 'planned', 'employee_id': 'owner'},
        {'id': 2, 'description': 'Order Gloria parts', 'status': 'done', 'employee_id': 'owner'},
        {'id': 3, 'description': 'Call Rick', 'status': 'done', 'employee_id': 'owner'},
      ],
      allocationsByLine: const {}, employeeName: (_) => 'Owner', employeeIds: const ['owner'],
      serviceTaskCard: (_) => const SizedBox(), onAddGeneral: () {},
      onGeneralStatus: (_, _) async {}, onOpenJob: (_) {}, onEmployeeTap: (_) {},
    ))));
    await tester.enterText(find.byType(TextField).first, 'Gloria');
    await tester.pump();
    expect(find.text('Call Gloria'), findsOneWidget);
    expect(find.text('Order Gloria parts'), findsNothing);
    await tester.tap(find.text('Show completed tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Order Gloria parts'), findsOneWidget);
    expect(find.text('Call Gloria'), findsNothing);
    expect(find.text('Call Rick'), findsNothing);
    await tester.tap(find.text('Show active tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Call Gloria'), findsOneWidget);
    expect(find.text('Order Gloria parts'), findsNothing);
  });
}
