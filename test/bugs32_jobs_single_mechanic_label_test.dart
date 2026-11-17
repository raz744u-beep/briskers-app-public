import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/job_compact_card.dart';

void main() {
  testWidgets('Jobs card shows mechanic nickname and assigned hours once',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: JobCompactCard(
      job: const {
        'id': 'j-45', 'job_number': 'J-45',
        'customer_name': 'Jenny Felton',
        'vehicle': '2018 BMW X1',
        'title': 'Invoice',
        'status': 'completed',
        'payment_state': 'awaiting_payment',
        'assigned_employee': 'Chris Rideaux',
        'assigned_employee_nickname': 'Chris',
      },
      statusControl: const Text('Completed'),
      onOpen: () {},
      mechanicMinutes: const {'Chris Rideaux': 120},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Chris · 2h'), findsOneWidget);
    expect(find.text('Chris'), findsNothing);
    expect(find.text('Chris Rideaux 2h'), findsNothing);
    expect(find.text('2 hr'), findsNothing,
      reason: 'A single mechanic already shows the full assigned hours.');
    expect(tester.takeException(), isNull);
  });
}
