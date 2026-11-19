import 'dart:convert';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/screens/jobs/job_create_screen.dart';
import 'package:briskers_app/services/employee_nickname_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Create job uses saved nickname with role and retains the selected employee ID', (tester) async {
    final roster=[
      {'id':'chris','name':'Chris Rideaux','position_name':'Mechanic'},
      {'id':'kam','name':'Kamerron Smith','position_name':'Mechanic'},
      {'id':'adam','name':'Adam Bourgeois','position_name':'Porter'},
      {'id':'secretary','name':'Tyrianna Fedison','position_name':'Secretary'},
    ];
    SharedPreferences.setMockInitialValues({'briskers_job_employees_shop':jsonEncode(roster)});
    final db=BriskersLocalDatabase(NativeDatabase.memory()); debugUseLocalDatabase(db);
    addTearDown(() async {
      debugUseLocalDatabase(null); await db.close();
      await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);
    });
    await tester.runAsync(() async {
    await EmployeeNicknameStore(database:db).save('shop','chris','Chris');
    await EmployeeNicknameStore(database:db).save('shop','kam','Kam');
    await EmployeeNicknameStore(database:db).save('shop','adam','Adam');
    await EmployeeNicknameStore(database:db).save('shop','secretary','Tyra');
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
    });
    await tester.pumpWidget(const MaterialApp(home:JobCreateScreen(
      businessId:'shop',customerId:'customer',customerName:'Saved customer',
      vehicles:[],roleCode:'owner')));
    for(var i=0;i<8;i++) {
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));
      await tester.pump(const Duration(milliseconds:100));
    }
    final field=find.byType(DropdownButtonFormField<String?>);
    final menu=tester.widget<DropdownButtonFormField<String?>>(field);
    await tester.ensureVisible(field); await tester.pump();
    await tester.tap(find.text('Unassigned').first); await tester.pumpAndSettle();
    for(final label in ['Chris — Mechanic','Kam — Mechanic','Adam — Porter','Tyra — Secretary']) {
      expect(find.text(label).hitTestable(),findsOneWidget);
    }
    expect(find.textContaining('Kamerron Smith'),findsNothing);
    await tester.tap(find.text('Kam — Mechanic').last); await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<String?>>(find.byType(DropdownButton<String?>)).value,'kam');
    expect(menu.initialValue,isNull);
    await tester.runAsync(() async {
      expect((await db.customSelect('SELECT count(*) AS n FROM local_jobs').getSingle()).read<int>('n'),0);
    });
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
