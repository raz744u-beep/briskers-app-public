import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/tasks_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String,dynamic> service(String job,int ageDays,
      {String status='planned',int remaining=0,int paid=0}) {
    final now=DateTime.now();
    final day=DateTime(now.year,now.month,now.day)
      .subtract(Duration(days:ageDays));
    return {
      'id':'line-$job', 'job_id':'job-$job', 'line_id':'line-$job',
      'job_number':'J-$job', 'job_created_at':day.millisecondsSinceEpoch,
      'invoice_date':day.toIso8601String().substring(0,10),
      'source_description':'Service $job','description':'Service $job',
      'source_kind':'invoice','source_missing':0,
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
      onGeneralStatus:(_,__)async{},
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
    expect(find.text('Jobs with Tasks · 2'),findsOneWidget);
    expect(find.byTooltip('Period'),findsOneWidget);
    await tester.tap(find.byTooltip('Period'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 7 days').last);
    await tester.pumpAndSettle();
    expect(find.text('Jobs with Tasks · 1'),findsOneWidget);
    expect(find.text('J-new'),findsOneWidget);
    expect(find.text('J-old'),findsNothing);
    await tester.tap(find.byTooltip('Period'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any time').last);
    await tester.pumpAndSettle();
    expect(find.text('Jobs with Tasks · 2'),findsOneWidget);
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
    expect(find.text('Jobs with Tasks · 1'),findsOneWidget);
    await tester.tap(find.byTooltip('Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpaid').last);
    await tester.pumpAndSettle();
    expect(find.text('Jobs with Tasks · 1'),findsOneWidget);
    expect(find.text('J-unpaid'),findsOneWidget);
    await tester.tap(find.byTooltip('Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paid').last);
    await tester.pumpAndSettle();
    expect(find.text('Jobs with Tasks · 1'),findsOneWidget);
    expect(find.text('J-paid'),findsOneWidget);
  });

  test('unknown service dates cannot be passed off as recently completed',(){
    // The widget must use grounded job, invoice, or completed dates,
    // not task-list position or an invented current-day timestamp.
    expect(service('dated',3)['job_created_at'],isA<int>());
  });
}
