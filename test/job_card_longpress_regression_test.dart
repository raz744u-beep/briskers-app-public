import 'package:briskers_app/widgets/job_compact_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Job card tap opens, while long press invokes actions only',
      (tester) async {
    var opens = 0;
    var menus = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: JobCompactCard(
          job: const <String, dynamic>{
            'id': 'test-job',
            'job_number': 'J-10',
            'customer_name': 'Test Customer',
            'status': 'in_progress',
            'title': 'Test Job',
          },
          statusControl: const Text('In Progress'),
          onOpen: () => opens++,
          onLongPress: () => menus++,
        ),
      ),
    ));

    await tester.tap(find.byType(JobCompactCard));
    await tester.pump();
    expect(opens, 1);
    expect(menus, 0);

    await tester.longPress(find.byType(JobCompactCard));
    await tester.pump();
    expect(opens, 1);
    expect(menus, 1);
  });

  testWidgets('Busy Job card suppresses tap and long-press actions',
      (tester) async {
    var opens = 0;
    var menus = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: JobCompactCard(
          job: const <String, dynamic>{
            'id': 'test-job',
            'job_number': 'J-11',
            'customer_name': 'Test Customer',
            'status': 'in_progress',
          },
          statusControl: const Text('In Progress'),
          canOpen: false,
          onOpen: () => opens++,
          onLongPress: () => menus++,
        ),
      ),
    ));

    await tester.tap(find.byType(JobCompactCard));
    await tester.longPress(find.byType(JobCompactCard));
    expect(opens, 0);
    expect(menus, 0);
  });
}
