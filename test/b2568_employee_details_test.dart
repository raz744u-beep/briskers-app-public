import 'dart:async';
import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/employee_nickname_store.dart';
import 'package:briskers_app/screens/settings/employee_edit_screen.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('known Details paint before slow nickname database without inventing private fields',(tester)async{
    SharedPreferences.setMockInitialValues({});FlutterSecureStorage.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
    final gate=Completer<void>();
    final db=BriskersLocalDatabase(LazyDatabase(()async{await gate.future;return NativeDatabase.memory();}));
    addTearDown(()async{if(!gate.isCompleted)gate.complete();await db.close();await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);});
    await tester.pumpWidget(MaterialApp(home:EmployeeEditScreen(businessId:'shop',employeeId:'a',isOwner:true,
      rosterName:'Known Legal Name',rosterPosition:'Mechanic',nicknameStore:EmployeeNicknameStore(database:db),currentOwner:()=>null)));
    await tester.pump();
    expect(find.text('Known Legal Name'),findsOneWidget);expect(find.text('Mechanic'),findsWidgets);
    expect(find.byType(CircularProgressIndicator),findsNothing);
    expect(find.textContaining('Not saved locally'),findsWidgets);
    await tester.pump(const Duration(seconds:4));
    expect(find.text('Known Legal Name'),findsOneWidget);
    expect(find.textContaining('Nickname is not available'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());gate.complete();
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:80)));await tester.pump();
    expect(tester.takeException(),isNull);
  });
}
