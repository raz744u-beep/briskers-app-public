import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/service_task_editor.dart';
import 'package:briskers_app/screens/payroll/general_task_editor.dart';
import 'package:briskers_app/screens/payroll/weekly_labor_review_screen.dart';
import 'package:briskers_app/screens/payroll/employee_work_review.dart';
import 'package:briskers_app/widgets/owner_confirmation_dialog.dart';
import 'package:briskers_app/widgets/task_schedule_indicator.dart';
import 'bugs35_shared_design_test.dart' show capture;

void main(){
  setUp(()async{TestWidgetsFlutterBinding.ensureInitialized();final f=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');if(await f.exists()){await(FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())))).load();}final i=File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');if(await i.exists()){await(FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await i.readAsBytes())))).load();}});
  void size(WidgetTester t){t.view.physicalSize=const Size(390,844);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);}
  const jobs=[{'id':'j40','job_number':'J-40','customer_name':'Gloria Johnson','vehicle_label':'Mercedes','title':'Oil Separator','status':'closed'}];
  const staff=[{'id':'chris','name':'Chris','rate':4000}];
  testWidgets('one labor editor remains keyboard safe, Done and paid assignments stay locked while dates remain editable',(t)async{
    size(t);final key=GlobalKey();ServiceTaskDraft? saved;
    await t.pumpWidget(MaterialApp(home:RepaintBoundary(key:key,child:MediaQuery(data:const MediaQueryData(size:Size(390,844),padding:EdgeInsets.only(bottom:32),viewPadding:EdgeInsets.only(bottom:32),viewInsets:EdgeInsets.only(bottom:300)),child:ServiceTaskEditor(jobs:jobs,employees:staff,editing:true,statusLocked:true,payrollLocked:true,initial:ServiceTaskDraft(job:'j40',description:'Oil Separator',mechanics:[TaskMechanicDraft('chris',600,locked:true)],start:'2026-11-09',end:'2026-11-10',priority:'High',status:'Done',treatment:'unpaid'),save:(v)async{saved=v;})))));
    await t.pumpAndSettle();
    expect(t.getBottomRight(find.text('Save Task')).dy,lessThan(544));expect(t.getBottomRight(find.text('Cancel')).dy,lessThan(544));
    await capture(t,key,'nov13-service-editor-keyboard');
    await t.ensureVisible(find.text('Start Date: 2026-11-09'));await t.tap(find.text('Start Date: 2026-11-09'));await t.pumpAndSettle();expect(find.byType(DatePickerDialog),findsOneWidget);await t.tap(find.text('Cancel').last);await t.pumpAndSettle();
    await t.tap(find.text('Save Task'));await t.pumpAndSettle();expect(saved!.start,'2026-11-09');expect(saved!.status,'Done');expect(saved!.mechanics.single.minutes,600);expect(t.takeException(),isNull);
  });
  testWidgets('historical zero-hour Done task can change dates and historical-paid choice requires confirmation',(t)async{
    size(t);var saves=0;
    Widget editor(String treatment,int minutes)=>MaterialApp(home:ServiceTaskEditor(jobs:jobs,employees:staff,editing:true,statusLocked:true,initial:ServiceTaskDraft(job:'j40',description:'Historical task',mechanics:[TaskMechanicDraft('chris',minutes)],start:'2026-11-02',end:'2026-11-06',priority:'Normal',status:'Done',treatment:treatment),save:(v)async{saves++;}));
    await t.pumpWidget(editor('preserve',0));await t.pumpAndSettle();await t.tap(find.text('Save Task'));await t.pumpAndSettle();expect(saves,1);
    await t.pumpWidget(const SizedBox.shrink());await t.pumpAndSettle();
    await t.pumpWidget(editor('paid',60));await t.pumpAndSettle();await t.tap(find.text('Save Task'));await t.pumpAndSettle();expect(find.text('Mark as Already Paid'),findsOneWidget);await t.tap(find.text('Cancel').last);await t.pumpAndSettle();expect(saves,1);
    await t.tap(find.text('Save Task'));await t.pumpAndSettle();await t.tap(find.text('Confirm historical payment'));await t.pumpAndSettle();expect(saves,2);expect(t.takeException(),isNull);
  });
  testWidgets('General Task editor keeps Save and Cancel above keyboard and navigation',(t)async{
    size(t);final key=GlobalKey();
    await t.pumpWidget(MaterialApp(home:RepaintBoundary(key:key,child:MediaQuery(data:const MediaQueryData(size:Size(390,844),padding:EdgeInsets.only(bottom:32),viewPadding:EdgeInsets.only(bottom:32),viewInsets:EdgeInsets.only(bottom:300)),child:GeneralTaskEditor(jobs:jobs,employees:staff,initial:const {'employee_id':'chris','description':'Order warranty part','job_id':'j40'},save:(_)async{})))));
    await t.pumpAndSettle();expect(t.getBottomRight(find.text('Save General Task')).dy,lessThan(544));expect(t.getBottomRight(find.text('Cancel')).dy,lessThan(544));await capture(t,key,'nov13-general-editor-keyboard');expect(t.takeException(),isNull);
  });
  Map<String,dynamic> labor(String id,String description,int minutes,{String state='Done',bool paid=false,String start='2026-11-09',String end='2026-11-10'})=>{'id':id,'task_id':id,'job_id':id=='oil'?'j40':'j54','job_number':id=='oil'?'J-40':'J-54','customer_name':id=='oil'?'Gloria Johnson':'Nathan Hogue','description':description,'state':state,'actual_minutes':minutes,'estimated_minutes':minutes,'remaining_minutes':paid?0:minutes,'paid_minutes':paid?minutes:0,'paid':paid?1:0,'rate_cents':4000,'completed_date':'2026-11-10','work_start_date':start,'work_end_date':end,'source_active':1,'priority':'Normal'};
  testWidgets('480 payroll aligned metrics, dark whole-job link independent of selection, retained repayments and safe bottom',(t)async{
    size(t);final key=GlobalKey();String? opened;Map<String,double>? draft;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:RepaintBoundary(key:key,child:WeeklyLaborReview(employeeId:'chris',employeeName:'Chris',week:DateTime(2026,11,9),profileLayout:true,savedRateCents:4000,tasks:[labor('oil','Oil Separator',600),labor('change','Oil Change',60),labor('brake','Brake Flush',60),labor('filter','Replace filters',60,state:'Open'),labor('paid48','Water pump',450,paid:true,start:'2026-11-02',end:'2026-11-06')],advanceBalance:()async=>5000,onOpenJob:(id)=>opened=id,saveDraft:(week,selected,a,r,reason)async{draft=selected;},recordPayment:(a,b,c,d,e,f,g,h,i)async{})))));
    await t.pumpAndSettle();expect(find.text('Unpaid Labor (3)'),findsOneWidget);expect(find.text('12.00'),findsOneWidget);expect(find.text(r'$480.00'),findsWidgets);
    final heights=['Unpaid Hours','Rate / Hr','Gross Pay'].map((label)=>t.getTopLeft(find.text(label).first).dy).toSet();expect(heights,hasLength(1));
    await t.tap(find.text('J-40 · Gloria Johnson'));await t.pumpAndSettle();expect(opened,'j40');expect(t.widget<Checkbox>(find.byType(Checkbox).first).value,isTrue);
    await capture(t,key,'nov13-payroll-480');
    await t.tap(find.byType(Checkbox).first);await t.pumpAndSettle();expect(t.widget<Checkbox>(find.byType(Checkbox).first).value,isFalse);expect(opened,'j40');
    await t.scrollUntilVisible(find.text('Save (Draft)'),200,scrollable:find.byType(Scrollable).first);await t.tap(find.text('Save (Draft)'));await t.pumpAndSettle();expect(draft!.keys.toSet(),{'change','brake'});await t.ensureVisible(find.text('Verify Weekly Payment'));expect(find.text('Adjustments & repayment'),findsOneWidget);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox.shrink());await t.pumpAndSettle();
  });
  testWidgets('actual work dates determine readonly weekly review, not prior completion/payroll dates',(t)async{
    size(t);var week=DateTime(2026,11,9);final rows=[labor('paid48','Water pump',450,paid:true,start:'2026-11-02',end:'2026-11-06'),labor('oil','Oil Separator',600)];
    await t.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(builder:(context,set)=>EmployeeWorkReview(week:week,rows:rows,jobs:const [],onWeekChanged:(v)=>set(()=>week=v),onJob:(_){})))));await t.pumpAndSettle();expect(find.textContaining('Water pump'),findsNothing);expect(find.textContaining('Oil Separator'),findsOneWidget);await t.tap(find.byTooltip('Previous work week'));await t.pumpAndSettle();expect(find.textContaining('Water pump'),findsOneWidget);expect(find.textContaining('Oil Separator'),findsNothing);expect(t.takeException(),isNull);
  });
  testWidgets('large confirmation scrolls its inventory with always visible buttons and trailing priority flag',(t)async{
    size(t);final key=GlobalKey();
    await t.pumpWidget(MaterialApp(home:Scaffold(body:RepaintBoundary(key:key,child:OwnerConfirmationDialog(title:'Delete Job J-48?',confirm:'Permanently delete these records',destructive:true,sections:[const Text('Records affected',style:TextStyle(fontWeight:FontWeight.w800)),for(var i=0;i<20;i++)Text('• Saved linked record $i'),const Text('Payment deletion does not refund a bank transaction.')])))));await t.pumpAndSettle();expect(find.text('Cancel').hitTestable(),findsOneWidget);expect(find.text('Permanently delete these records').hitTestable(),findsOneWidget);await capture(t,key,'nov13-delete-confirmation');expect(t.takeException(),isNull);
    await t.pumpWidget(const MaterialApp(home:Scaffold(body:Row(children:[Expanded(child:Text('Repair title')),TaskScheduleIndicator({'priority':'Low','state':'Done','work_end_date':'2026-11-01'})]))));expect(find.text('Overdue'),findsNothing);expect(t.widget<Icon>(find.byIcon(Icons.flag)).color,const Color(0xFFCBD5E1));
  });
}
