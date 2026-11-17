import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/app.dart';
import 'package:briskers_app/screens/payroll/approved_tasks_ui.dart';
import 'package:briskers_app/screens/payroll/weekly_labor_review_screen.dart';
import 'package:briskers_app/screens/payroll/tasks_workspace.dart';
import 'package:briskers_app/screens/settings/employee_list_tile.dart';
import 'bugs35_shared_design_test.dart' show capture;
import 'support/handoff_qa_fonts.dart';

void main(){
  setUp(loadHandoffFonts);
  void size(WidgetTester t,{double width=412}){t.view.physicalSize=Size(width,915);t.view.devicePixelRatio=1;t.view.padding=const FakeViewPadding(top:24,bottom:32);t.view.viewPadding=const FakeViewPadding(top:24,bottom:32);addTearDown(t.view.reset);}
  Future<void> shot(WidgetTester t,GlobalKey key,String name)async{final old=debugDisableShadows;void repaint(RenderObject r){r.markNeedsPaint();r.visitChildren(repaint);}try{debugDisableShadows=false;repaint(key.currentContext!.findRenderObject()!);await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:200)));await t.pumpAndSettle();await capture(t,key,name);}finally{debugDisableShadows=old;repaint(key.currentContext!.findRenderObject()!);await t.pump();}}
  const long='Remove and install wheel liner. Inspect the area. Found a small broken piece of plastic. Everything else looked normal.';
  Map<String,dynamic> task(int i)=>{'id':'allocation-$i','task_id':'saved-task-$i','job_id':'job-$i','job_number':i==0?'J-51':'J-50','customer_name':i==0?'Ireona Dowl':'Marzel Stafford','description':i==2?long:'Oil Change','state':'Done','actual_minutes':60,'remaining_minutes':60,'paid_minutes':0,'paid':0,'rate_cents':3500,'completed_date':'2026-11-12','source_active':1};
  testWidgets('compact payroll preserves selection, partial hours, week and scroll on independent task/job navigation',(t)async{
    size(t);final key=GlobalKey(),nav=GlobalKey<NavigatorState>();String? openedTask,openedJob;Map<String,double>? draft;
    final rows=[for(var i=0;i<8;i++)task(i)];rows[6]={...rows[6],'actual_minutes':240,'remaining_minutes':240};rows[7]={...rows[7],'actual_minutes':240,'remaining_minutes':240};
    Future<void> open(String label)async{await nav.currentState!.push<void>(MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:Text(label)))));}
    await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(navigatorKey:nav,debugShowCheckedModeBanner:false,theme:BriskersApp.applicationTheme,home:DefaultTabController(length:4,initialIndex:1,child:Scaffold(backgroundColor:taskCanvas,appBar:const ApprovedTasksHeader(title:'Employee Profile'),body:Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:ApprovedEmployeeIdentity(name:'Kam',role:'Mechanic',active:true,onDetails:(){})),const ApprovedProfileTabs(),
      Expanded(child:WeeklyLaborReview(employeeId:'kam',employeeName:'Kam',week:DateTime(2026,11,9),profileLayout:true,savedRateCents:3500,tasks:rows,advanceBalance:()async=>0,recordPayment:(a,b,c,d,e,f,g,h,i)async{},
        onOpenTask:(r)async{openedTask=r['task_id'];await open('Existing Task Details · $openedTask');},onOpenJob:(id){openedJob=id;open('Job Details · $id');},saveDraft:(w,s,a,r,reason)async{draft=s;})),
    ]))))));
    await t.pumpAndSettle();expect(find.text(r'$490.00'),findsWidgets);expect(find.text('Deselect All'),findsOneWidget);
    final cards=[for(var i=0;i<3;i++)find.byKey(ValueKey('payable-allocation-$i'))];
    expect(cards.map((f)=>t.getSize(f).height).toSet(),hasLength(1));expect(t.getSize(cards.first).height,lessThan(110));
    final description=t.widget<Text>(find.text(long));expect(description.maxLines,1);expect(description.overflow,TextOverflow.ellipsis);
    await shot(t,key,'quick-payroll-collapsed');
    await t.tap(find.byType(Checkbox).first);await t.pumpAndSettle();expect(find.text('Select All'),findsOneWidget);
    await t.tap(find.text(long));await t.pumpAndSettle();expect(find.text(long),findsNWidgets(2));expect(t.widget<Checkbox>(find.byType(Checkbox).first).value,false);
    await t.ensureVisible(find.byKey(const ValueKey('view-payable-task-allocation-2')));await t.pumpAndSettle();
    final list=find.byKey(const Key('employee-payroll-preparation'));final offset=t.state<ScrollableState>(find.descendant(of:list,matching:find.byType(Scrollable)).first).position.pixels;
    await t.tap(find.byKey(const ValueKey('view-payable-task-allocation-2')));await t.pumpAndSettle();expect(openedTask,'saved-task-2');nav.currentState!.pop();await t.pumpAndSettle();
    expect(t.state<ScrollableState>(find.descendant(of:list,matching:find.byType(Scrollable)).first).position.pixels,offset);
    await shot(t,key,'quick-payroll-expanded');
    await t.scrollUntilVisible(find.text('J-51 · Ireona Dowl'),-250,scrollable:find.byType(Scrollable).last);await t.tap(find.text('J-51 · Ireona Dowl'));await t.pumpAndSettle();expect(openedJob,'job-0');nav.currentState!.pop();await t.pumpAndSettle();expect(t.widget<Checkbox>(find.byType(Checkbox).first).value,false);
    await t.scrollUntilVisible(find.text('Select All'),-250,scrollable:find.byType(Scrollable).last);await t.tap(find.text('Select All'));await t.pumpAndSettle();expect(find.text('Deselect All'),findsOneWidget);
    await t.tap(find.text('Deselect All'));await t.pumpAndSettle();expect(t.widgetList<Checkbox>(find.byType(Checkbox)).every((c)=>c.value==false),true);
    await t.tap(find.text('Select All'));await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Payable Hours'),150,scrollable:find.byType(Scrollable).last);await t.tap(find.text('Payable Hours'));await t.pumpAndSettle();await t.enterText(find.byType(TextField).last,'0.50');
    await t.tap(find.text('Save'));await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Save (Draft)'),350,scrollable:find.byType(Scrollable).last);await t.tap(find.text('Save (Draft)'));await t.pumpAndSettle();expect(draft!['allocation-2'],.5);expect(draft!.length,8);expect(t.takeException(),isNull);
  });
  testWidgets('roster keeps two lines, real compensation and legal names at narrow and owner sizes',(t)async{
    size(t);final key=GlobalKey();var opens=0,actions=0;
    final people=[('Chris','Chris Rideaux','Mechanic',r'$40.00 / hr'),('Kam','Kamerron Smith','Mechanic',r'$35.00 / hr'),('Adam','Adam Bourgeois','Porter','Pay not saved on this device'),('Raz','Raz','Owner',r'$0.00 / hr'),('Tyra','Tyrianna Fedison','Secretary','Pay not saved on this device')];
    await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:BriskersApp.applicationTheme,home:Scaffold(appBar:AppBar(title:const Text('Employees')),body:ListView(padding:const EdgeInsets.all(12),children:[for(final p in people)EmployeeListTile(employee:{'id':p.$1,'nickname':p.$1,'name':p.$2,'position':p.$3},pay:p.$4,onOpen:()=>opens++,onLongPress:()=>actions++)]),floatingActionButton:FloatingActionButton.extended(onPressed:(){},icon:const Icon(Icons.groups),label:const Text('Manage'))))));
    await t.pumpAndSettle();await shot(t,key,'quick-employees');
    for(final width in [412.0,360.0]){t.view.physicalSize=Size(width,915);await t.pumpAndSettle();expect(t.takeException(),isNull);for(final tile in t.widgetList<EmployeeListTile>(find.byType(EmployeeListTile))){expect(find.text(tile.pay),findsWidgets);}expect(t.getSize(find.byType(EmployeeListTile).first).height,lessThan(90));}
    await t.tap(find.byType(EmployeeListTile).first);await t.longPress(find.byType(EmployeeListTile).first);await t.pumpAndSettle();expect(opens,1);expect(actions,1);
  });
  testWidgets('one continuous full-row stripe exactly matches each active tab background',(t)async{
    size(t);
    final boundary=GlobalKey();
    const labels=['Work','Payroll','Reports','Taxes'];
    const colors=[Color(0xFF2479C6),Color(0xFF176B40),Color(0xFF6942A2),Color(0xFF697586)];
    await t.pumpWidget(MaterialApp(home:DefaultTabController(length:4,child:Scaffold(body:Column(children:[
      RepaintBoundary(key:boundary,child:const ApprovedProfileTabs()),
      Expanded(child:TabBarView(children:[for(final n in labels)Text('$n body')])),
    ])))));
    for(final (width,height) in [(412.0,915.0),(360.0,915.0),(844.0,390.0)]){
      t.view.physicalSize=Size(width,height);await t.pumpAndSettle();
      for(final (index,selected) in labels.indexed){
        await t.tap(find.text(selected));await t.pump(const Duration(milliseconds:50));
        // One stripe spans every tab, including during selection transitions.
        expect(find.byKey(const ValueKey('profile-tabs-stripe')),findsOneWidget);
        for(final label in labels){
          expect(find.byKey(ValueKey('profile-tab-stripe-$label')),findsNothing);
          final decoration=t.widget<Container>(find.byKey(ValueKey('profile-tab-$label'))).decoration! as BoxDecoration;
          expect(decoration.color,label==selected?colors[index]:null);
        }
        await t.pumpAndSettle();
        final bounds=t.getRect(find.byKey(ValueKey('profile-tab-$selected')));
        expect(bounds.height,40);expect(bounds.width,width/4);
        final origin=t.getTopLeft(find.byKey(boundary));
        final pixels=await t.runAsync(()async{
          final image=await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:1);
          final bytes=await image.toByteData(format:ui.ImageByteFormat.rawRgba);image.dispose();return bytes!;
        });
        int pixel(int x,int y){final offset=(y*width.toInt()+x)*4;return (pixels!.getUint8(offset+3)<<24)|(pixels.getUint8(offset)<<16)|(pixels.getUint8(offset+1)<<8)|pixels.getUint8(offset+2);}
        final left=(bounds.left-origin.dx).round(),bottom=(bounds.bottom-origin.dy).round();
        final expected=colors[index].toARGB32();
        final stripe=t.getRect(find.byKey(const ValueKey('profile-tabs-stripe')));
        expect(stripe.width,width);expect(stripe.height,3);
        expect(stripe.top,bounds.bottom);
        // Every pixel across the entire tab row must be the same selected color.
        for(var x=0;x<width.toInt();x++){
          for(var y=bottom;y<bottom+3;y++){
            expect(pixel(x,y),expected,reason:'$selected stripe pixel ($x,$y) at width $width');
          }
        }
        expect(pixel(left+6,bottom-8),expected,reason:'Tab background and stripe must be identical');
        expect(find.text('$selected body').hitTestable(),findsOneWidget);
        if(width==412)await capture(t,boundary,'profile-tab-stripe-$index');
      }
    }
    expect(t.takeException(),isNull);
  });
  testWidgets('completed General Tasks are excluded only by Active and remain in All and Done filters',(t)async{
    size(t);var status='in_progress';late StateSetter refresh;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(builder:(context,set){refresh=set;return TasksWorkspace(initialGeneral:true,serviceTasks:const [],generalTasks:[{'id':7,'employee_id':'owner','description':'Call customer','job_id':'j40','job_number':'J-40','customer_name':'Gloria Johnson','status':status,'due_at':DateTime(2026,11,20).millisecondsSinceEpoch}],allocationsByLine:const {},employeeName:(_)=>'Owner',employeeIds:const ['owner'],serviceTaskCard:(_)=>const SizedBox(),onAddService:(){},onAddGeneral:(){},onGeneralStatus:(_,next)async{set(()=>status=next);},onOpenJob:(_){},onEmployeeTap:(_){});}))));
    await t.pumpAndSettle();expect(find.text('Call customer'),findsOneWidget);
    refresh(()=>status='done');await t.pumpAndSettle();expect(find.text('Call customer'),findsNothing);expect(find.text('Tasks · 0 (Active)'),findsOneWidget);
    await t.tap(find.text('Show all task statuses'));await t.pumpAndSettle();expect(find.text('Call customer'),findsOneWidget);expect(find.text('Tasks · 1 (All)'),findsOneWidget);
    await t.tap(find.byKey(const Key('toggle-task-filters')));await t.pumpAndSettle();await t.scrollUntilVisible(find.byKey(const ValueKey('Status:All')),150,scrollable:find.byType(Scrollable).last);await t.tap(find.byKey(const ValueKey('Status:All')));await t.pumpAndSettle();await t.tap(find.text('Done').last);await t.pumpAndSettle();await t.tap(find.text('Apply Filters'));await t.pumpAndSettle();expect(find.text('Call customer'),findsOneWidget);expect(find.text('Tasks · 1 (Done)'),findsOneWidget);expect(t.takeException(),isNull);
  });
}
