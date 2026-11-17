import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/job_scoped_tasks.dart';

void main() {
  testWidgets('job-scoped Tasks retains approved compact navigation cards',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var laborFinished = false;
    var generalFinished = false;
    var opened=0;
    var assignmentsOpened = false;
    final tasks = <Map<String, dynamic>>[
      {
        'job_id': 'job-44',
        'line_id': 'labor-1',
        'status': 'in_progress',
        'source_description': 'Replace front struts',
        'description': 'Replace front struts',
        'invoice_id': 'invoice-6363',
        'source_line_id': 'line-1',
      },
      {
        'job_id': 'other-job',
        'line_id': 'labor-other',
        'status': 'planned',
        'description': 'Never show another job',
      },
      {
        'job_id': 'job-44',
        'line_id': 'labor-2',
        'status': 'done',
        'source_description': 'Initial inspection',
      },
    ];
    final allocations = <String, List<Map<String, dynamic>>>{
      'labor-1': [
        {
          'id': 'credit-1',
          'employee_id': 'chris',
          'estimated_minutes': 216,
          'state': 'In Progress',
          'source_active': 1,
        },
      ],
      'labor-2': [
        {
          'id': 'credit-2',
          'employee_id': 'kam',
          'estimated_minutes': 30,
          'state': 'Done',
          'source_active': 1,
        },
      ],
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: JobScopedTasks(
      jobId: 'job-44',
      serviceTasks: tasks,
      generalTasks: [
        {
          'id': 1, 'job_id': 'job-44',
          'description': 'Road test vehicle',
          'status': 'planned',
          'employee_id': 'kam',
        },
      ],
      allocationsByLine: allocations,
      employeeName: (id) => id == 'chris' ? 'Chris' : 'Kam',
      onAddLabor: () {},
      onAddGeneral: () {},
      onLaborProgress: (_, finish) async { laborFinished = finish; },
      onGeneralProgress: (id, next) async {
        generalFinished = id == 1 && next == 'done';
      },
      onOpenTask:(_,_)=>opened++,
      onManageLabor: (_) => assignmentsOpened = true,
    ))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
      reason: 'Closed task cards must not overflow a 390px phone.');

    expect(find.text('3 tasks (1 of 3 completed)'), findsOneWidget);
    expect(find.text('Labor Task'), findsOneWidget);
    expect(find.text('General Task'), findsOneWidget);
    expect(find.text('Never show another job'), findsNothing);
    expect(find.text('Advanced task filters'), findsNothing);
    expect(find.byIcon(Icons.tune), findsNothing);
    expect(find.text('Service Tasks'), findsNothing);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Replace front struts'));await tester.pumpAndSettle();expect(opened,1);
    await tester.longPress(find.text('Replace front struts'));await tester.pumpAndSettle();
    await tester.tap(find.text('Mark Done'));await tester.pumpAndSettle();expect(laborFinished,isTrue);expect(opened,1);
    await tester.longPress(find.text('Road test vehicle'));await tester.pumpAndSettle();await tester.tap(find.text('Mark Done'));await tester.pumpAndSettle();expect(generalFinished,isTrue);
    expect(find.textContaining('3.6 hrs'),findsWidgets);
    await tester.longPress(find.text('Replace front struts').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile,'Edit Assignment'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile,'Edit Assignment'));
    await tester.pumpAndSettle();
    expect(assignmentsOpened, isTrue);
    expect(tester.takeException(), isNull);
  });
}
