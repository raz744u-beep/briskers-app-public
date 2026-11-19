import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/payroll/job_tasks_access.dart';
import 'package:briskers_app/services/employee_nickname_store.dart';
import 'package:briskers_app/services/job_detail_first_frame.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final nicknameInPreview in [true, false, null]) {
    testWidgets('saved nickname never flashes legal name, preview alias=$nicknameInPreview', (tester) async {
      SharedPreferences.setMockInitialValues({
        'briskers_job_employees_shop': jsonEncode([
          {'id': 'mechanic', 'name': 'Chris Rideaux'},
        ]),
      });
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.runAsync(() async {
        await db.customStatement(
          "INSERT INTO local_jobs(id,business_id,access_scope,title,status,assigned_employee_id,assigned_employee_name,is_unassigned) VALUES('job','shop','owner','Repair','open','mechanic','Chris Rideaux',0)",
        );
        await EmployeeNicknameStore(database: db).save('shop', 'mechanic', 'Chris');
      });
      final preview = JobDetailFirstFrame.fromSelectedRow({
        'id': 'job',
        'assigned_employee_id': 'mechanic',
        'assigned_employee': 'Chris Rideaux',
        if (nicknameInPreview != false)
          'assigned_employee_nickname': nicknameInPreview == true ? 'Chris' : null,
      }, expectedJobId: 'job')!;

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
        width: 240,
        child: JobTasksAccess(
          business: 'shop', job: 'job', database: db,
          initialJob: preview, selectorOnly: true,
        ),
      ))));
      expect(find.text('Chris Rideaux'), findsNothing);
      expect(find.text(nicknameInPreview == true ? 'Chris' : 'Loading…'), findsOneWidget);
      expect(tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).value, 'mechanic');

      // Observe both the fast core read and the slower roster/payroll refresh.
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.text('Chris Rideaux'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Chris'), findsOneWidget);
      expect(tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).value, 'mechanic');
      await tester.runAsync(() async {
        final row = await db.customSelect("SELECT assigned_employee_id,assigned_employee_name FROM local_jobs WHERE business_id='shop' AND id='job'").getSingle();
        expect(row.read<String>('assigned_employee_id'), 'mechanic');
        expect(row.read<String>('assigned_employee_name'), 'Chris Rideaux');
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(seconds: 4));
    });
  }
}
