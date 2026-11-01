import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/more_screen.dart';

void main() {
  Widget screen(String role) => MaterialApp(
    home: Scaffold(body: MoreScreen(
      businessId: 'test-business',
      businessName: 'TEST',
      roleCode: role,
    )),
  );

  testWidgets('Payroll TEST entry is visible to Owner', (tester) async {
    await tester.pumpWidget(screen('owner'));
    expect(find.text('Payroll staging TEST'), findsOneWidget);
    expect(find.text('Local preview only — no payments'), findsOneWidget);
  });

  for (final role in ['manager', 'office', 'mechanic', 'porter']) {
    testWidgets('Payroll TEST entry hidden from $role', (tester) async {
      await tester.pumpWidget(screen(role));
      expect(find.text('Payroll staging TEST'), findsNothing);
    });
  }
}
