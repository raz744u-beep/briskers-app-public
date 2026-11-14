import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/payroll/job_tasks_access.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Main Mechanic and Job Tasks draw equal 50px controls',
      (tester) async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:Center(child:SizedBox(width:380,child:JobTasksAccess(
        business:'test-shop',job:'J-test',database:db,
      ))),
    )));
    // The offline roster has a bounded 3-second loading timeout; allow it to
    // resolve before ending the widget test or fake_async reports a pending timer.
    await tester.pump(const Duration(seconds:4));
    await tester.pump();
    final dropdown=find.byType(DropdownButton<String>);
    final taskButton=find.widgetWithText(OutlinedButton,'Job Tasks');
    expect(dropdown,findsOneWidget);
    expect(taskButton,findsOneWidget);
    final outer=find.ancestor(of:dropdown,matching:find.byType(Container));
    expect(outer,findsWidgets);
    final dropdownHeight=tester.getSize(outer.first).height;
    final buttonHeight=tester.getSize(taskButton).height;
    expect(dropdownHeight,50);
    expect(buttonHeight,50);
    expect(dropdownHeight,buttonHeight);
    final outline = find.descendant(of:taskButton,matching:find.byType(Material));
    final painted = tester.getRect(outline.first);
    final selector = tester.getRect(outer.first);
    expect(painted.top,selector.top);
    expect(painted.bottom,selector.bottom);
    final label = tester.getRect(find.text('Main Mechanic'));
    expect(selector.contains(label.topLeft),isTrue);
    expect(selector.contains(label.bottomRight),isTrue);
  });

  testWidgets('Invoice mirrors the job Main Mechanic selector without Job Tasks button',
      (tester) async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:SizedBox(width:220,child:JobTasksAccess(
        business:'test-shop',job:'J-test',invoice:'invoice-test',
        selectorOnly:true,database:db,
      )),
    )));
    await tester.pump(const Duration(seconds:4));
    await tester.pump();
    expect(find.text('Main Mechanic'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.text('Job Tasks'), findsNothing);
  });

  test('Invoice Items uses the same durable main mechanic assignment',
      () async {
    final invoice=await File('lib/screens/jobs/job_document_screen.dart')
        .readAsString();
    final access=await File('lib/screens/payroll/job_tasks_access.dart')
        .readAsString();
    expect(invoice, contains('selectorOnly: true'));
    expect(invoice, contains("job: _detail!['job_id'].toString()"));
    expect(access, contains('await repo.setMainMechanic(widget.job,id,'));
    expect(access, contains('final bool selectorOnly;'));
  });

  test('Invoice labor inherits lead; pencil manages assignments and hours',
      () async {
    final text=await File('lib/screens/payroll/job_tasks_access.dart')
        .readAsString();
    final repo=await File('lib/services/local_payroll_repository.dart')
        .readAsString();
    expect(text, isNot(contains('chooseLineMechanic(String employeeId)')));
    expect(text, contains("if(widget.line!=null)"));
    expect(text, contains("linePeople.map((p) =>"));
    expect(text, contains("tooltip:'Assign or split mechanic labor'"));
    expect(text, contains("'Edit or split mechanic labor'"));
    expect(text, contains("onPressed:busy?null:open"));
    expect(text, contains("Assigned total:"));
    expect(text, contains('linePeople.fold<int>'));
    expect(text, contains("tooltip:'Assign or split mechanic labor'"));
    expect(repo, contains('setMainMechanic('));
    expect(repo, contains('LocalTaskAssignmentStore(db).inherit'));
    expect(repo, contains('setEstimatedMinutes('));
  });
}
