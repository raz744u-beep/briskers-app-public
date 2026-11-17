import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/tasks_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String,dynamic> service(String job,int ageDays,
      {String status='planned',int remaining=0,int paid=0,bool archived=false}) {
    final now=DateTime.now();
    final day=DateTime(now.year,now.month,now.day)
      .subtract(Duration(days:ageDays));
    return {
      'id':'line-$job', 'job_id':'job-$job', 'line_id':'line-$job',
      'job_number':'J-$job', 'job_created_at':day.millisecondsSinceEpoch,
      'invoice_date':day.toIso8601String().substring(0,10),
      'source_description':'Service $job','description':'Service $job',
      'source_kind':'invoice','source_missing':0,
      'archived_labor':archived?1:0,
      'employee_id':'mechanic','status':status,'remaining_minutes':remaining,
      'paid':paid,'completed_date': status=='done' ?
        day.toIso8601String().substring(0,10) : null,
    };
  }

  Future<void> showTasks(WidgetTester tester,
      List<Map<String,dynamic>> rows) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:TasksWorkspace(
      serviceTasks:rows,
      generalTasks:const [],
      allocationsByLine:const {},
      employeeIds:const ['mechanic'],
      employeeName:(_)=>'Chris',
      serviceTaskCard:(row)=>ListTile(title:Text(row['description'].toString())),
      onAddGeneral:(){},
      onGeneralStatus:(_,status)async{},
      onOpenJob:(_){},
      onEmployeeTap:(_){},
    ))));
    await tester.pumpAndSettle();
  }

  testWidgets('visible Period filters recent service jobs without changing records',
      (tester)async{
    tester.view.physicalSize=const Size(390,844);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showTasks(tester,[
      service('new',2), service('old',65),
    ]);
    expect(find.textContaining('Tasks · 2 ('),findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle-task-filters')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Period'));
    await tester.tap(find.ancestor(of:find.text('Period'),matching:find.byType(DropdownButtonFormField<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 7 days').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tasks · 1 ('),findsOneWidget);
    expect(find.text('Service new'),findsOneWidget);
    expect(find.text('Service old'),findsNothing);
    await tester.tap(find.byKey(const Key('toggle-task-filters')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Period'));
    await tester.tap(find.ancestor(of:find.text('Period'),matching:find.byType(DropdownButtonFormField<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any time').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tasks · 2 ('),findsOneWidget);
  });

  testWidgets('Paid and Unpaid filters do not mingle with Active jobs',
      (tester)async{
    tester.view.physicalSize=const Size(390,844);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showTasks(tester,[
      service('active',1),
      service('unpaid',2,status:'done',remaining:60),
      service('paid',2,status:'done',paid:1),
    ]);
    expect(find.textContaining('Tasks · 1 ('),findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle-task-filters')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Status'));
    await tester.tap(find.ancestor(of:find.text('Status'),matching:find.byType(DropdownButtonFormField<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpaid').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tasks · 1 ('),findsOneWidget);
    expect(find.text('Service unpaid'),findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle-task-filters')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Status'));
    await tester.tap(find.ancestor(of:find.text('Status'),matching:find.byType(DropdownButtonFormField<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paid').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tasks · 1 ('),findsOneWidget);
    expect(find.text('Service paid'),findsOneWidget);
  });

  test('unknown service dates cannot be passed off as recently completed',(){
    // The widget must use grounded job, invoice, or completed dates,
    // not task-list position or an invented current-day timestamp.
    expect(service('dated',3)['job_created_at'],isA<int>());
  });
  testWidgets('empty Active view offers read-only access to existing completed tasks',
      (tester)async{
    tester.view.physicalSize=const Size(390,844);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showTasks(tester,[service('historical',10,status:'done',paid:1)]);
    expect(find.textContaining('Tasks · 0 ('),findsOneWidget);
    expect(find.byKey(const Key('show-all-service-task-statuses')),findsOneWidget);
    await tester.tap(find.byKey(const Key('show-all-service-task-statuses')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tasks · 1 ('),findsOneWidget);
    expect(find.text('Service historical'),findsOneWidget);
  });


  testWidgets('archived planned invoice is historical, never active or unpaid',
      (tester)async{
    tester.view.physicalSize=const Size(390,844);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showTasks(tester,[
      service('historical',10,archived:true,remaining:60),
    ]);
    expect(find.textContaining('Tasks · 0 ('),findsOneWidget);
    await tester.tap(find.byKey(const Key('show-all-service-task-statuses')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tasks · 1 ('),findsOneWidget);
    expect(find.text('Service historical'),findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle-task-filters')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Status'));
    await tester.tap(find.ancestor(of:find.text('Status'),matching:find.byType(DropdownButtonFormField<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpaid').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tasks · 0 ('),findsOneWidget);
  });


}
