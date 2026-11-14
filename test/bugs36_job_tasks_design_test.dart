import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/job_scoped_tasks.dart';
import 'bugs35_shared_design_test.dart' show capture;
import 'support/handoff_qa_fonts.dart';

void main() {
  setUp(loadHandoffFonts);
  testWidgets('J-56 job Tasks matches compact design without losing protected actions', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 32);
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    var edits = 0, assignments = 0, done = 0, reconciliation = 0, bulk = 0, opened=0;
    const description = 'Remove oil pan. Replace pip control valve.';
    final tasks = [
      {'job_id':'j56','job_number':'J-56','customer_name':'Terrance Sanders','vehicle_label':'2016 Mercedes C300','line_id':'engine','invoice_id':'invoice','source_line_id':'engine','description':'Replace engine','status':'planned','work_start_date':'2026-11-13','work_end_date':'2026-11-13'},
      {'job_id':'j56','line_id':'oil','invoice_id':'invoice','source_line_id':'oil','description':description,'status':'done','work_start_date':'2026-11-13','work_end_date':'2026-11-13'},
    ];
    await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(
      debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Roboto',scaffoldBackgroundColor:const Color(0xFFF7F8FA),colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF00877D)),appBarTheme:const AppBarTheme(backgroundColor:Colors.white)),
      home:Scaffold(appBar:AppBar(title:const Text('Tasks')),body:SafeArea(top:false,child:JobScopedTasks(
        jobId:'j56',serviceTasks:tasks,generalTasks:const [],
        allocationsByLine:const {
          'engine':[{'id':'chris-engine','employee_id':'chris','estimated_minutes':1080,'state':'Open','source_active':1}],
          'oil':[{'id':'kam-oil','employee_id':'kam','estimated_minutes':300,'state':'Done','source_active':1,'paid_minutes':300}],
        },employeeName:(id)=>id=='chris'?'Chris':'Kam',
        onAddLabor:(){},onAddGeneral:(){},onLaborProgress:(_,_)async{done++;},onGeneralProgress:(_,_)async{},
        onOpenTask:(_,_)=>opened++,
        onEditLabor:(_){edits++;},onManageLabor:(_){assignments++;},
        onReconcileLabor:(_){reconciliation++;},onReviewLabor:(_){},
        markAllDoneCount:1,onMarkAllDone:()async{bulk++;},
      ))))));
    await tester.pumpAndSettle();
    final engine = find.byKey(const ValueKey('job-task-l-engine'));
    final oil = find.byKey(const ValueKey('job-task-l-oil'));
    expect(tester.getTopLeft(engine).dy,lessThan(270));
    expect(tester.getSize(oil).height,lessThan(100));
    expect(tester.widget<Text>(find.text(description)).maxLines,1);
    final surface = tester.widget<Material>(find.descendant(of:engine,matching:find.byType(Material)).first);
    expect(surface.color,Colors.white);
    expect(find.text('Reconcile historical wages'),findsNothing);
    await capture(tester,key,'bugs36-job-tasks-collapsed');
    await tester.tap(find.text('Replace engine'));
    await tester.pumpAndSettle();
    expect(opened,1);expect(tester.getSize(engine).height,lessThan(100));
    expect(find.text('Edit Task'),findsNothing);
    await tester.longPress(find.text('Replace engine'));await tester.pumpAndSettle();await tester.tap(find.text('Edit Task'));await tester.pumpAndSettle();
    await tester.longPress(find.text('Replace engine'));await tester.pumpAndSettle();await tester.tap(find.text('Edit Assignment'));await tester.pumpAndSettle();
    expect(edits,1);expect(assignments,1);expect(done,0);expect(reconciliation,0);expect(opened,1);
    // Long press must not toggle the already-expanded card or complete labor.
    await tester.longPress(find.text('Replace engine'));await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile,'Mark Done'),findsOneWidget);
    expect(find.widgetWithText(ListTile,'Reconcile historical wages'),findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile,'Reconcile historical wages'));await tester.pumpAndSettle();
    expect(reconciliation,1);expect(done,0);
    expect(opened,1);
    await tester.longPress(find.text(description));await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile,'Mark Done'),findsNothing);
    expect(find.widgetWithText(ListTile,'Reconcile historical wages'),findsNothing);
    await tester.tap(find.widgetWithText(ListTile,'Edit Task'));await tester.pumpAndSettle();
    expect(edits,2);expect(assignments,1);expect(done,0);expect(bulk,0);
    expect(tasks[1]['description'],description);
    expect(tasks[1]['status'],'done');
    expect(tester.takeException(),isNull);
  });
}
