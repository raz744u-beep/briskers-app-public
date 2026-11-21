import 'package:briskers_app/widgets/job_compact_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Job card tap opens, while long press invokes actions only', (
    tester,
  ) async {
    var opens = 0;
    var menus = 0;
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );

    expect(find.text('Long press for options'), findsOneWidget);

    await tester.tap(find.byType(JobCompactCard));
    await tester.pump();
    expect(opens, 1);
    expect(menus, 0);

    await tester.longPress(find.byType(JobCompactCard));
    await tester.pump();
    expect(opens, 1);
    expect(menus, 1);
  });

  testWidgets(
    'Owner planned time stays visible with edit affordance on narrow cards',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final hours in [0, 1234.5]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: JobCompactCard(
                job: {
                  'id': 'synthetic-job',
                  'job_number': 'J-6',
                  'status': 'open',
                  'planned_hours': hours,
                },
                statusControl: const Text('Open'),
                onOpen: () {},
                onEditMechanic: () {},
                onEditPlannedTime: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Busy Job card suppresses tap and long-press actions', (
    tester,
  ) async {
    var opens = 0;
    var menus = 0;
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );

    expect(find.text('Long press for options'), findsNothing);
    await tester.tap(find.byType(JobCompactCard));
    await tester.longPress(find.byType(JobCompactCard));
    expect(opens, 0);
    expect(menus, 0);
  });
}
