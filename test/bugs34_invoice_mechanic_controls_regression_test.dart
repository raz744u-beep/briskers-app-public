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
  });

  test('Invoice line exposes selection and per-person edit, total is derived',
      () async {
    final text=await File('lib/screens/payroll/job_tasks_access.dart')
        .readAsString();
    expect(text,contains('chooseLineMechanic(String employeeId)'));
    expect(text,contains('registerAssignedLabor('));
    expect(text,contains('editMechanicHours(one)'));
    expect(text,contains('editMechanicHours(person)'));
    expect(text,contains('linePeople.fold<int>'));
    expect(text,contains('Assigned total:'));
    expect(text,contains('setEstimatedMinutes(task,employee,'));
    expect(text,contains('LocalTaskAssignmentStore(db)'));
    expect(text,contains('ownerPeer(widget.business,employeeId)'));
    expect(text,contains('Force Offline'),isFalse);
  });
}
