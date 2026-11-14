import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/tasks_workspace.dart';
import 'package:briskers_app/screens/payroll/compact_task_card.dart';
import 'package:briskers_app/screens/payroll/service_task_editor.dart';
import 'bugs35_shared_design_test.dart' show capture;

void main(){
  setUp(()async{
    for(final entry in {'Roboto':'/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf','MaterialIcons':'${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries){final file=File(entry.value);if(await file.exists())await(FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())))).load();}
  });
  testWidgets('Galaxy compact cards separate touch tap and long press; filters safe above navigation and keyboard',(tester)async{
    tester.view.physicalSize=const Size(412,915);tester.view.devicePixelRatio=1;
    tester.view.padding=const FakeViewPadding(bottom:32);tester.view.viewPadding=const FakeViewPadding(bottom:32);
    addTearDown(tester.view.reset);
    int edits=0,generalEdits=0,done=0;final key=GlobalKey();
    const title='Remove oil pan. Replace oil control valve and complete the final inspection.';
    await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Roboto'),home:Scaffold(appBar:AppBar(title:const Text('Tasks')),body:SafeArea(top:false,child:TasksWorkspace(
      serviceTasks:const [{'job_id':'j56','job_number':'J-56','customer_name':'Terrance Sanders','vehicle_label':'2016 Mercedes','line_id':'task','source_description':title,'status':'in_progress'}],
      generalTasks:const [{'id':1,'description':'Order replacement part and confirm delivery with the supplier','employee_id':'owner','status':'planned','category':'Office'}],
      allocationsByLine:const {'task':[{'id':'allocation','employee_id':'kam','estimated_minutes':300}]},
      employeeIds:const ['kam','owner'],employeeName:(id)=>id=='kam'?'Kam':'Owner',serviceTaskCard:(_)=>const Text('Full task details'),
      onAddGeneral:(){},onAddService:(){},onGeneralStatus:(_,_)async{done++;},onOpenJob:(_){},onEmployeeTap:(_){},onEditService:(_){edits++;},onEditGeneral:(_){generalEdits++;},onMarkDone:(_){done++;},
    ))))));await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('J-56  Terrance Sanders')).dy,lessThan(260));
    expect(find.text('Tap to open · Long press for options'),findsNothing);
    await tester.tap(find.text('J-56  Terrance Sanders'));await tester.pumpAndSettle();
    final card=find.byType(CompactTaskCard).first;
    final label=find.descendant(of:card,matching:find.text(title));expect(tester.widget<Text>(label).maxLines,1);
    await tester.longPress(label);await tester.pumpAndSettle();expect(find.text('Edit Assignment'),findsOneWidget);expect(find.text('Full task details'),findsNothing);
    await tester.tap(find.text('Edit Assignment'));await tester.pumpAndSettle();expect(edits,1);
    await tester.tap(label);await tester.pumpAndSettle();expect(find.text('Full task details'),findsOneWidget);expect(find.text('Kam · 5.0 h'),findsOneWidget);expect(tester.takeException(),isNull);
    await capture(tester,key,'bugs36-service-tasks');
    await tester.tap(find.byKey(const Key('toggle-task-filters')));await tester.pumpAndSettle();
    for(final text in ['Employee','Job','Task Type','Period','Status','Sort By']){expect(find.text(text),findsOneWidget);}
    expect(tester.getBottomLeft(find.text('Apply Filters')).dy,lessThan(883));
    await capture(tester,key,'bugs36-filters');
    tester.view.viewInsets=const FakeViewPadding(bottom:300);await tester.pumpAndSettle();expect(tester.getBottomLeft(find.text('Apply Filters')).dy,lessThan(615));expect(tester.takeException(),isNull);
    await tester.tap(find.text('Apply Filters'));await tester.pumpAndSettle();tester.view.resetViewInsets();await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('general-tasks-tab')));await tester.pumpAndSettle();
    final general=find.text('Order replacement part and confirm delivery with the supplier');
    expect(tester.widget<Text>(general).maxLines,1);await tester.longPress(general);await tester.pumpAndSettle();expect(find.text('Edit Task'),findsOneWidget);expect(find.text('Mark Done'),findsOneWidget);expect(find.byType(PopupMenuButton<String>),findsNothing);
    await tester.tap(find.text('Edit Task'));await tester.pumpAndSettle();expect(generalEdits,1);expect(done,0);
    await capture(tester,key,'bugs36-general-tasks');
  });
  testWidgets('Done invoice editor permits task-only text and unpaid mechanic edits, safe footer',(tester)async{
    tester.view.physicalSize=const Size(412,915);tester.view.devicePixelRatio=1;tester.view.padding=const FakeViewPadding(bottom:32);addTearDown(tester.view.reset);
    ServiceTaskDraft? saved;final key=GlobalKey();
    await tester.pumpWidget(MaterialApp(theme:ThemeData(fontFamily:'Roboto'),home:RepaintBoundary(key:key,child:ServiceTaskEditor(
      editing:true,invoiceLabor:true,statusLocked:true,jobs:const [{'id':'j56','job_number':'J-56','customer_name':'Terrance Sanders','vehicle_label':'2016 Mercedes'}],employees:const [{'id':'chris','name':'Chris'},{'id':'kam','name':'Kam'}],
      initial:ServiceTaskDraft(job:'j56',description:'Remove oil pan. Replace pip control valve.',mechanics:[TaskMechanicDraft('chris',300,originalEmployee:'chris')],start:'2026-11-13',end:'2026-11-13',priority:'Normal',status:'Done',treatment:'unpaid'),save:(v)async{saved=v;},
    ))));await tester.pumpAndSettle();
    final description=find.byType(TextFormField).first;expect(tester.widget<TextFormField>(description).enabled,isNot(false));
    await tester.enterText(description,'Remove oil pan. Replace oil control valve.');
    await tester.tap(find.text('Chris').first);await tester.pumpAndSettle();await tester.tap(find.text('Kam').last);await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();await tester.pumpAndSettle();
    await capture(tester,key,'bugs36-edit-done-task');
    expect(tester.getBottomLeft(find.text('Save Task')).dy,lessThan(883));
    await tester.tap(find.text('Save Task'));await tester.pumpAndSettle();expect(saved,isNotNull);expect(saved!.description,'Remove oil pan. Replace oil control valve.');expect(saved!.mechanics.single.employee,'kam');expect(saved!.mechanics.single.originalEmployee,'chris');expect(saved!.datesEdited,isFalse);expect(saved!.status,'Done');expect(tester.takeException(),isNull);
  });
}
