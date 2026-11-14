import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/app.dart';
import 'package:briskers_app/screens/payroll/approved_tasks_ui.dart';
import 'package:briskers_app/screens/payroll/approved_task_details.dart';
import 'package:briskers_app/screens/payroll/tasks_workspace.dart';
import 'package:briskers_app/screens/payroll/job_scoped_tasks.dart';
import 'package:briskers_app/screens/payroll/employee_work_review.dart';
import 'bugs35_shared_design_test.dart' show capture;
import 'support/handoff_qa_fonts.dart';

void main(){
  setUp(loadHandoffFonts);
  Future<void> shot(WidgetTester t,GlobalKey key,String name)async{final old=debugDisableShadows;try{debugDisableShadows=false;await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:200)));await t.pumpAndSettle();await capture(t,key,name);}finally{debugDisableShadows=old;await t.pump();}}
  final service=<Map<String,dynamic>>[
    {'line_id':'engine','job_id':'j56','job_number':'J-56','customer_name':'Terrance Sanders','vehicle_label':'2016 Mercedes C300','description':'Replace engine','source_description':'Replace engine','status':'in_progress','priority':'High'},
    {'line_id':'struts','job_id':'j40','job_number':'J-40','customer_name':'Gloria Johnson','description':'Replace front air struts','source_description':'Replace front air struts','status':'planned','priority':'Normal'},
    {'line_id':'oil','job_id':'j56','job_number':'J-56','customer_name':'Terrance Sanders','description':'Remove oil pan. Replace oil control valve.','source_description':'Remove oil pan. Replace oil control valve.','status':'done','priority':'Normal'},
    {'line_id':'align','job_id':'j60','job_number':'J-60','customer_name':'Mike Reynolds','description':'Perform alignment','source_description':'Perform alignment','status':'planned','priority':'Low'},
  ];
  const allocations=<String,List<Map<String,dynamic>>>{
    'engine':[{'id':'a','employee_id':'chris','estimated_minutes':1080,'state':'Open','source_active':1}],
    'struts':[{'id':'b','employee_id':'kam','estimated_minutes':216,'state':'Open','source_active':1}],
    'oil':[{'id':'c','employee_id':'kam','estimated_minutes':300,'state':'Done','source_active':1,'paid_minutes':300}],
    'align':[{'id':'d','employee_id':'chris','estimated_minutes':90,'state':'Open','source_active':1}],
  };
  String employee(String? id)=>id=='kam'?'Kam':id=='chris'?'Chris':id=='secretary'?'Secretary':'Owner';
  void size(WidgetTester t){t.view.physicalSize=const Size(412,915);t.view.devicePixelRatio=1;t.view.padding=const FakeViewPadding(top:24,bottom:32);t.view.viewPadding=const FakeViewPadding(top:24,bottom:32);addTearDown(t.view.reset);}
  Widget app(GlobalKey key,Widget screen)=>RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:BriskersApp.applicationTheme,home:screen));
  testWidgets('approved flat lists use independent priority, tap navigation, long press actions and safe filters',(t)async{
    size(t);final key=GlobalKey();var opens=0,edits=0;String? priority;
    await t.pumpWidget(app(key,Scaffold(backgroundColor:taskCanvas,appBar:ApprovedTasksHeader(title:'Tasks',actions:[PopupMenuButton<String>(icon:const Icon(Icons.more_vert,color:Colors.white),itemBuilder:(_)=>[const PopupMenuItem(value:'history',child:Text('Invoice labor history'))])]),body:SafeArea(top:false,child:TasksWorkspace(
      serviceTasks:service,generalTasks:[for(final (i,title) in ['Add expenses for Gloria','Call customer for approval','Order parts – engine kit','Schedule alignment'].indexed){'id':i,'description':title,'employee_id':['owner','secretary','chris','chris'][i],'job_id':i==0?'j40':'j56','job_number':i==0?'J-40':'J-56','customer_name':i==0?'Gloria Johnson':'Terrance Sanders','status':i==0?'in_progress':'planned','priority':i==0?'High':i==3?'Low':'Normal'}],
      allocationsByLine:allocations,employeeName:employee,employeeIds:const ['chris','kam','owner','secretary'],serviceTaskCard:(_)=>const SizedBox(),onAddService:(){},onAddGeneral:(){},onGeneralStatus:(_,_)async{},onOpenJob:(_){},onEmployeeTap:(_){},onOpenTask:(_,_)=>opens++,onEditService:(_)=>edits++,onPriority:(_,_,p)=>priority=p,
    )))));
    await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:150)));await t.pumpAndSettle();expect(find.byType(ApprovedTaskListCard),findsNWidgets(3));
    expect(t.getTopLeft(find.byType(ApprovedTaskListCard).first).dy,lessThan(310));
    await shot(t,key,'approved-main-service');
    await t.tap(find.text('Replace engine'));await t.pumpAndSettle();expect(opens,1);
    await t.longPress(find.text('Replace engine'));await t.pumpAndSettle();expect(opens,1);await t.tap(find.text('Edit Assignment'));await t.pumpAndSettle();expect(edits,1);
    await t.tap(find.byTooltip('Task priority').first);await t.pumpAndSettle();await t.tap(find.text('Low').last);await t.pumpAndSettle();expect(priority,'Low');expect(opens,1);
    await t.tap(find.byKey(const Key('toggle-task-filters')));await t.pumpAndSettle();expect(find.text('Apply Filters').hitTestable(),findsOneWidget);
    t.view.viewInsets=const FakeViewPadding(bottom:300);await t.pumpAndSettle();expect(t.getBottomLeft(find.text('Apply Filters')).dy,lessThan(615));
    await shot(t,key,'approved-filters-keyboard');await t.tap(find.text('Apply Filters'));await t.pumpAndSettle();t.view.resetViewInsets();
    await t.tap(find.byKey(const Key('general-tasks-tab')));await t.pumpAndSettle();await shot(t,key,'approved-main-general');expect(t.takeException(),isNull);
  });
  testWidgets('approved job list keeps compact independent status and priority and protected historical actions',(t)async{
    size(t);final key=GlobalKey();var opens=0,edits=0,bulk=0;
    await t.pumpWidget(app(key,Scaffold(backgroundColor:taskCanvas,appBar:const ApprovedTasksHeader(title:'Job J-56',subtitle:'Terrance Sanders'),body:SafeArea(top:false,child:JobScopedTasks(jobId:'j56',serviceTasks:[{...service[0],'status':'planned'},service[2]],generalTasks:const [],allocationsByLine:allocations,employeeName:employee,onAddLabor:(){},onAddGeneral:(){},onLaborProgress:(_,_)async{},onGeneralProgress:(_,_)async{},onOpenTask:(_,_)=>opens++,onEditLabor:(_)=>edits++,onManageLabor:(_)=>edits++,onReconcileLabor:(_){},onMarkAllDone:()async{bulk++;},markAllDoneCount:1)))));
    await t.pumpAndSettle();expect(find.text('50%'),findsOneWidget);expect(t.getSize(find.byKey(const ValueKey('job-task-l-oil'))).height,lessThan(100));await shot(t,key,'approved-job-tasks');
    await t.tap(find.text('Replace engine'));await t.pumpAndSettle();expect(opens,1);expect(find.text('Edit Task'),findsNothing);
    await t.longPress(find.text('Remove oil pan. Replace oil control valve.'));await t.pumpAndSettle();expect(opens,1);expect(find.text('Mark Done'),findsNothing);expect(find.text('Reconcile historical wages'),findsNothing);await t.tap(find.text('Edit Task'));await t.pumpAndSettle();expect(edits,1);expect(bulk,0);expect(t.takeException(),isNull);
  });
  testWidgets('approved dedicated details refreshes saved state and keeps paid task edit available',(t)async{
    size(t);final key=GlobalKey();var edits=0,starts=0;var task=<String,dynamic>{'job_id':'j50','job_number':'J-50','customer_name':'Marzel Stafford','vehicle_label':'2018 BMW 330i','job_status':'open','invoice_id':'i','invoice_number':'6356','description':'Oil Change','priority':'High','status':'planned','work_start_date':'2026-11-12','work_end_date':'2026-11-12'};
    var rows=<Map<String,dynamic>>[{'employee_id':'kam','estimated_minutes':60,'state':'Open','source_active':1,'paid':0}];
    await t.pumpWidget(app(key,ApprovedTaskDetails(initialTask:task,allocations:rows,general:false,employeeName:employee,reload:()async=>(task:task,allocations:rows),onEdit:()async{edits++;},onPriority:(p)async{task={...task,'priority':p};},onProgress:(done)async{starts++;task={...task,'status':done?'done':'in_progress'};rows=[{...rows.single,'state':done?'Done':'In Progress'}];},onJob:(){},onInvoice:(){},onActions:(){})));
    await t.pumpAndSettle();await shot(t,key,'approved-task-details');expect(find.text('Mark as Done').hitTestable(),findsOneWidget);await t.tap(find.text('Start Task'));await t.pumpAndSettle();expect(starts,1);expect(find.text('Finish Task'),findsOneWidget);
    task={...task,'status':'done'};rows=[{...rows.single,'state':'Done','paid':1}];await t.tap(find.text('Edit Task'));await t.pumpAndSettle();expect(edits,1);expect(find.text('Paid'),findsOneWidget);expect(find.text('Mark as Done'),findsNothing);expect(find.text('Edit Task').hitTestable(),findsOneWidget);expect(t.takeException(),isNull);
  });
  testWidgets('approved Work Review uses real weekly totals and readonly paid history',(t)async{
    size(t);final key=GlobalKey();var week=DateTime(2026,11,9);
    await t.pumpWidget(app(key,DefaultTabController(length:4,child:Scaffold(backgroundColor:taskCanvas,appBar:const ApprovedTasksHeader(title:'Employee Profile'),body:Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:ApprovedEmployeeIdentity(name:'Kam',role:'Mechanic',active:true,onDetails:(){})),const ApprovedProfileTabs(),
      Expanded(child:StatefulBuilder(builder:(context,set)=>EmployeeWorkReview(week:week,rows:[for(var i=0;i<8;i++){'job_number':i==0?'J-51':'J-50','customer_name':i==0?'Ireona Dowl':'Marzel Stafford','description':i<2?'Oil Change':'Repair ${i+1}','state':'Done','estimated_minutes':i<6?60:240,'actual_minutes':i<6?60:240,'remaining_minutes':i<6?60:240,'paid':0,'work_start_date':'2026-11-12','work_end_date':'2026-11-12','source_active':1}],jobs:const[{'id':'j56','job_number':'J-56','customer_name':'Terrance Sanders','vehicle_label':'2016 Mercedes C300','status':'open'}],onWeekChanged:(v)=>set(()=>week=v),onJob:(_){}))),
    ])))));
    await t.pumpAndSettle();expect(find.text('14.00 hrs'),findsNWidgets(2));expect(find.text('Completed\n14.00 hrs'),findsOneWidget);expect(find.text('New Task'),findsNothing);expect(find.text('Verify Weekly Payment'),findsNothing);await shot(t,key,'approved-work-review');await t.tap(find.byTooltip('Previous work week'));await t.pumpAndSettle();expect(find.text('Labor This Week · 0 tasks'),findsOneWidget);expect(t.takeException(),isNull);
  });
}
