import 'package:briskers_app/screens/payroll/tasks_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Job Tasks scopes both lists, two creation actions and collapsed details', (tester) async {
    tester.view.physicalSize = const Size(430, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var labor = 0, general = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TasksWorkspace(
      scopedJob: 'job45',
      serviceTasks: [
        for (final number in [45, 46])
          {'job_id':'job$number','job_number':'J-$number','line_id':'line$number',
            'status':'planned','source_description':'Labor $number'},
      ],
      generalTasks: [
        for (final number in [45, 46])
          {'id':number,'job_id':'job$number','description':'Inspection $number','status':'planned'},
      ],
      allocationsByLine: const {}, employeeIds: const [], employeeName: (_) => '',
      serviceTaskCard: (_) => const Text('Allocation details'),
      onAddGeneral: () => general++, onAddService: () => labor++,
      onEmployeeTap: (_) {}, onOpenJob: (_) {}, onGeneralStatus: (_, _) async {},
    ))));
    expect(find.text('J-46'), findsNothing);
    expect(find.text('Labor 45'), findsNothing);
    await tester.tap(find.text('J-45'));
    await tester.pumpAndSettle();
    expect(find.text('Allocation details'), findsNothing);
    await tester.tap(find.text('Labor 45'));
    await tester.pumpAndSettle();
    expect(find.text('Allocation details'), findsOneWidget);
    await tester.tap(find.text('Labor Task'));
    await tester.tap(find.text('General Task'));
    expect([labor, general], [1, 1]);
    await tester.tap(find.text('General Tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Inspection 45'), findsOneWidget);
    expect(find.text('Inspection 46'), findsNothing);
  });
}
