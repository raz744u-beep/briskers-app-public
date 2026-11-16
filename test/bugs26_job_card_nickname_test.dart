import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/widgets/job_compact_card.dart';

void main() {
  Widget fixture(Map<String, dynamic> job) => MaterialApp(
    home: Scaffold(
      body: JobCompactCard(
        job: job,
        statusControl: const Text('Open'),
        onOpen: () {},
      ),
    ),
  );

  testWidgets('Job card displays nickname while source keeps legal employee name',
      (tester) async {
    final job = <String, dynamic>{
      'id': 'test-job',
      'job_number': 'J-12',
      'status': 'open',
      'assigned_employee_id': 'employee-1',
      'assigned_employee': 'Kamerron Example',
      'assigned_employee_nickname': 'Kam',
      'assigned_position': 'Mechanic',
    };
    await tester.pumpWidget(fixture(job));
    expect(find.text('Kam'), findsOneWidget);
    expect(find.text('Kamerron Example'), findsNothing);
    expect(job['assigned_employee'], 'Kamerron Example',
        reason: 'Display nicknames must not overwrite full payroll names.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Job card without nickname retains the existing first-name fallback',
      (tester) async {
    await tester.pumpWidget(fixture({
      'id': 'test-job',
      'job_number': 'J-13',
      'status': 'open',
      'assigned_employee': 'Christopher Example',
      'assigned_position': 'Mechanic',
    }));
    expect(find.text('Christopher'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
