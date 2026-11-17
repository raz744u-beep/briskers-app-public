import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/screens/payroll/weekly_labor_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.now();
  final week = DateTime(now.year,now.month,now.day-now.weekday+1);
  final date = week.toIso8601String().split('T').first;
  Map<String,dynamic> task(String id,{String state='Done',int paid=0,int minutes=60}) => {
    'id':id,'task_id':'task-$id','employee_id':'kam','job_id':'job-$id',
    'job_number':id=='j41'?'J-41':'J-$id','customer_name':'Tyra Legard',
    'description':id=='j41'?'Replace front axles':id,
    'estimated_minutes':minutes,'actual_minutes':minutes,'remaining_minutes':minutes-paid,
    'paid_minutes':paid,'paid':0,'rate_cents':3500,'state':state,
    'work_start_date':date,'completed_date':state=='Done'?date:null,
    'source_active':1,
  };
  Finder check(String label) => find.byWidgetPredicate((w)=>w is Checkbox &&
    w.semanticLabel=='Select $label for payroll');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
  });

  testWidgets('Kam J-41 completion selects immediately on return without resetting other payroll choices', (tester) async {
    tester.view.physicalSize=const Size(430,1800);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows=ValueNotifier([task('j41',state:'In Progress',minutes:270),task('excluded'),task('custom',minutes:120)]);
    addTearDown(rows.dispose);
    Map<String,double>? saved;
    var payments=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(context)=>
      ValueListenableBuilder<List<Map<String,dynamic>>>(valueListenable:rows,builder:(_,data,child)=>WeeklyLaborReview(
        key:const ValueKey('kam-payroll'),employeeId:'kam',employeeName:'Kam',
        week:week,tasks:data,profileLayout:true,savedRateCents:3500,
        advanceBalance:() async=>0,
        saveDraft:(week,hours,a,r,reason) async {saved=Map.from(hours);},
        recordPayment:(a,b,c,d,e,f,g,h,i) async {payments++;},
        onOpenTask:(selected) async {
          await Navigator.of(context).push<void>(MaterialPageRoute(builder:(details)=>Scaffold(
            body:Center(child:FilledButton(onPressed:(){
              rows.value=[for(final row in rows.value)
                if(row['id']==selected['id']) {...row,'state':'Done','completed_date':date} else row];
              Navigator.pop(details);
            },child:const Text('Mark task done'))),
          )));
        },
      )),
    ))));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(check('Replace front axles')).value,isFalse);
    await tester.tap(check('excluded'));
    await tester.tap(find.byKey(const ValueKey('payable-custom')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('edit-payable-hours-custom')));
    await tester.tap(find.byKey(const ValueKey('edit-payable-hours-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('payable-hours-input')),'0.75');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('payable-j41')));
    await tester.tap(find.byKey(const ValueKey('payable-j41')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-payable-task-j41')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark task done'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(check('Replace front axles')).value,isTrue);
    expect(tester.widget<Checkbox>(check('excluded')).value,isFalse);
    expect(find.text('4.50 h'),findsOneWidget);
    expect(find.text('0.75 h'),findsOneWidget);
    await tester.ensureVisible(find.text('Save (Draft)'));
    await tester.tap(find.text('Save (Draft)'));
    await tester.pumpAndSettle();
    expect(saved,{'j41':4.5,'custom':0.75});
    expect(payments,0);
    expect(rows.value.first['paid_minutes'],0);
    expect(rows.value.first['paid'],0);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manual exclusions and paid coverage survive completion refresh', (tester) async {
    tester.view.physicalSize=const Size(430,1800);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows=ValueNotifier([task('j41',state:'In Progress',minutes:270),task('partial',state:'In Progress',minutes:120,paid:60)]);
    addTearDown(rows.dispose);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      ValueListenableBuilder<List<Map<String,dynamic>>>(valueListenable:rows,builder:(_,data,child)=>WeeklyLaborReview(
        employeeId:'kam',employeeName:'Kam',week:week,tasks:data,profileLayout:true,
        advanceBalance:() async=>0,recordPayment:(a,b,c,d,e,f,g,h,i) async=>fail('Refresh must not record a payment'),
      )),
    )));
    await tester.pumpAndSettle();
    await tester.tap(check('Replace front axles'));
    await tester.pump();
    await tester.tap(check('Replace front axles'));
    rows.value=[for(final row in rows.value) {...row,'state':'Done','completed_date':date}];
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(check('Replace front axles')).value,isFalse);
    expect(tester.widget<Checkbox>(check('partial')).value,isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a loaded payroll draft remains authoritative over automatic completion selection', (tester) async {
    final rows=ValueNotifier([task('j41',state:'In Progress',minutes:270)]);
    addTearDown(rows.dispose);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      ValueListenableBuilder<List<Map<String,dynamic>>>(valueListenable:rows,builder:(_,data,child)=>WeeklyLaborReview(
        employeeId:'kam',employeeName:'Kam',week:week,tasks:data,profileLayout:true,
        loadDraft:(_) async=>{'hours':<String,double>{},'adjustment':0,'repayment':0,'reason':''},
        advanceBalance:() async=>0,recordPayment:(a,b,c,d,e,f,g,h,i) async=>fail('Draft refresh must not record a payment'),
      )),
    )));
    await tester.pumpAndSettle();
    rows.value=[{...rows.value.single,'state':'Done','completed_date':date}];
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(check('Replace front axles')).value,isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
