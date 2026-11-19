import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/payroll/job_tasks_access.dart';
import 'package:briskers_app/services/job_detail_first_frame.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'selected job mechanic appears before database or payroll hydration',
    (tester) async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      Map<String, dynamic> summary(String id, String name) =>
          JobDetailFirstFrame.fromSelectedRow({
            'id': id,
            'assigned_employee_id': name.toLowerCase(),
            'assigned_employee': name,
          }, expectedJobId: id)!;
      Widget screen(String job, String name) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: JobTasksAccess(
              business: 'shop',
              job: job,
              initialJob: summary(job, name),
              database: db,
              selectorOnly: true,
            ),
          ),
        ),
      );
      await tester.pumpWidget(screen('job-a', 'Chris'));
      expect(find.text('Chris'), findsOneWidget);
      final first = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(first.value, 'chris');
      await tester.pumpWidget(screen('job-b', 'Kam'));
      expect(find.text('Kam'), findsOneWidget);
      expect(find.text('Chris'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        'kam',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'unknown assignment never paints Unassigned as a selected value',
    (tester) async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: JobTasksAccess(
                business: 'shop',
                job: 'job',
                database: db,
                selectorOnly: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Loading…'), findsOneWidget);
      expect(find.text('Unassigned').hitTestable(), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    },
  );
}
