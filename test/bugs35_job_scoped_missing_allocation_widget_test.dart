import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/job_scoped_tasks.dart';

void main() {
  testWidgets('invoice labor without allocations offers assignment recovery',
      (tester) async {
    Map<String, dynamic>? managed;
    final task = <String, dynamic>{
      'job_id': 'J-49',
      'line_id': 'line-49',
      'invoice_id': 'invoice-49',
      'source_line_id': 'line-49',
      'source_description': 'Replace and program battery in the DME',
      'status': 'planned',
      'source_active': 1,
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      JobScopedTasks(
        jobId: 'J-49',
        serviceTasks: [task],
        generalTasks: const [],
        allocationsByLine: const {},
        employeeName: (id) => id ?? 'Unassigned',
        onAddLabor: () {},
        onAddGeneral: () {},
        onLaborProgress: (allocation, finish) async {},
        onGeneralProgress: (taskId, status) async {},
        onManageLabor: (row) => managed = row,
      ),
    )));
    expect(find.text('Replace and program battery in the DME'), findsOneWidget);
    await tester.longPress(find.text('Replace and program battery in the DME'));await tester.pumpAndSettle();
    expect(find.text('Edit Assignment'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
    await tester.tap(find.text('Edit Assignment'));
    expect(managed, same(task));
  });

  testWidgets('historical labor without allocation is read-only',
      (tester) async {
    final task = <String, dynamic>{
      'job_id': 'J-old',
      'line_id': 'old-line',
      'source_description': 'Historical invoice labor',
      'archived_labor': 1,
      'status': 'planned',
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      JobScopedTasks(
        jobId: 'J-old',
        serviceTasks: [task],
        generalTasks: const [],
        allocationsByLine: const {},
        employeeName: (id) => id ?? 'Unassigned',
        onAddLabor: () {},
        onAddGeneral: () {},
        onLaborProgress: (allocation, finish) async {},
        onGeneralProgress: (taskId, status) async {},
        onManageLabor: (row) =>
            fail('Historical labor must not become assignable'),
      ),
    )));
    await tester.longPress(find.text('Historical invoice labor'));await tester.pumpAndSettle();
    expect(find.text('Mark Done'),findsNothing);
    expect(find.text('Assign mechanic'), findsNothing);
    expect(find.text('Start'), findsNothing);
  });

  testWidgets('assigned labor shows mechanic, hours and Start action',
      (tester) async {
    final task = <String, dynamic>{
      'job_id': 'J-49', 'line_id': 'line-49',
      'source_description': 'Replace and program battery in the DME',
      'status': 'planned',
    };
    final allocation = <String, dynamic>{
      'id': 'alloc-49', 'employee_id': 'mechanic-1',
      'estimated_minutes': 90, 'state': 'Open',
      'source_active': 1, 'paid_minutes': 0,
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      JobScopedTasks(
        jobId: 'J-49',
        serviceTasks: [task],
        generalTasks: const [],
        allocationsByLine: {'line-49': [allocation]},
        employeeName: (id) => id == 'mechanic-1' ? 'Chris' : 'Unassigned',
        onAddLabor: () {},
        onAddGeneral: () {},
        onLaborProgress: (allocation, finish) async {},
        onGeneralProgress: (taskId, status) async {},
      ),
    )));
    expect(find.textContaining('Chris'), findsWidgets);
    expect(find.textContaining('1.5 hrs'), findsWidgets);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Start'),findsNothing);
  });
}
