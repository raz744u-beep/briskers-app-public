import 'package:briskers_app/screens/payroll/tasks_workspace.dart';
import 'package:briskers_app/services/service_task_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main(){
  final rows=<Map<String,dynamic>>[
    {'job_id':'new','job_number':'J-2','job_created_at':1793836800,'line_id':'a','line_position':1,'document_id':'inv-new','source_description':'Second printed line','status':'planned'},
    {'job_id':'old','job_number':'MB-6220','job_created_at':'2025-01-01','line_id':'z','line_position':0,'document_id':'inv-old','source_description':'Old job','status':'done'},
    {'job_id':'new','job_number':'J-2','job_created_at':1793836800000,'line_id':'x','line_position':0,'document_id':'inv-new','source_description':'First printed line','status':'planned'},
    {'job_id':'middle','job_number':'MB-3335','job_created_at':'2026-05-01','line_id':'q','line_position':0,'source_description':'Middle job','status':'in_progress'},
  ];
  test('real dates order job cards independently of mixed IDs and number spelling',(){
    final asc=[...rows]..sort((a,b)=>ServiceTaskOrder.compareJobs(a,b,newest:false));
    final desc=[...rows]..sort((a,b)=>ServiceTaskOrder.compareJobs(a,b,newest:true));
    expect(asc.map((r)=>r['job_id']).toList(),['old','middle','new','new']);
    expect(desc.map((r)=>r['job_id']).toList(),asc.reversed.map((r)=>r['job_id']).toList());
    final lines=rows.where((r)=>r['job_id']=='new').toList()..sort((a,b)=>ServiceTaskOrder.compareLines(a,b,newest:true));
    expect(lines.map((r)=>r['line_id']).toList(),['x','a']);
    expect(ServiceTaskOrder.timestamp(1793836800),ServiceTaskOrder.timestamp(1793836800000));
  });
  testWidgets('Newest/Oldest and Active/All render the right grouped tasks stably',(tester)async{
    tester.view.physicalSize=const Size(430,1400);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:TasksWorkspace(
      serviceTasks:rows,generalTasks:const [],allocationsByLine:const {},employeeName:(id)=>id??'Unassigned',employeeIds:const [],
      serviceTaskCard:(row)=>Text(row['source_description'] as String),onAddGeneral:(){},onGeneralStatus:(_,_)async{},onOpenJob:(_){},onEmployeeTap:(_){}))));
    Future<void> pick(String title,String value)async{
      await tester.tap(find.ancestor(of:find.text(title),matching:find.byType(DropdownButtonFormField<String>)));await tester.pumpAndSettle();
      await tester.tap(find.text(value).last);await tester.pumpAndSettle();
    }
    expect(find.text('Old job'),findsNothing);
    expect(tester.getTopLeft(find.text('J-2')).dy,lessThan(tester.getTopLeft(find.text('MB-3335')).dy));
    await tester.tap(find.text('J-2'));await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('First printed line')).dy,lessThan(tester.getTopLeft(find.text('Second printed line')).dy));
    await tester.tap(find.byKey(const Key('toggle-task-filters')));
    await tester.pumpAndSettle();
    await pick('Status','All');
    await tester.tap(find.text('Apply Filters'));await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toggle-task-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort By').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oldest First').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('MB-6220')).dy,lessThan(tester.getTopLeft(find.text('MB-3335')).dy));
    await tester.tap(find.byKey(const Key('toggle-task-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort By').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Newest First').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('J-2')).dy,lessThan(tester.getTopLeft(find.text('MB-3335')).dy));
    expect(tester.takeException(),isNull);
  });
}
