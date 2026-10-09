import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/customers/customer_quick_actions.dart';
import 'package:briskers_app/screens/jobs/blank_invoice_setup_screen.dart';
import 'package:briskers_app/screens/jobs/estimate_job_setup_screen.dart';

void main() {
  for (final action in CustomerQuickAction.values) {
    testWidgets('owner tapping ${action.name} dispatches real customer action',
        (tester) async {
      CustomerQuickAction? selected;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomerQuickActionsSheet(
            roleCode: 'owner',
            onSelected: (value) => selected = value,
          ),
        ),
      ));
      final item = find.byKey(ValueKey('customer-action-${action.name}'));
      await tester.ensureVisible(item);
      await tester.tap(item);
      expect(selected, action);
    });
  }

  testWidgets('secretary sees all six functional shortcuts', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomerQuickActionsSheet(
          roleCode: 'office',
          onSelected: (_) {},
        ),
      ),
    ));
    for (final action in CustomerQuickAction.values) {
      expect(find.byKey(ValueKey('customer-action-${action.name}')),
          findsOneWidget);
      expect(customerQuickActionDestination(action), isNotEmpty);
    }
  });

  testWidgets('customer invoice setup skips reselecting customer', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BlankInvoiceSetupScreen(
        businessId: 'business',
        initialCustomerId: 'customer-123',
        initialCustomerName: 'Daniel Howard',
        initialVehicles: [
          {'id':'vehicle-1','year':2013,'make':'BMW','model':'X5'}
        ],
      ),
    ));
    expect(find.text('Daniel Howard'), findsOneWidget);
    expect(find.text('2013 BMW X5'), findsOneWidget);
    expect(find.text('Create Invoice & Add Items'), findsOneWidget);
    expect(find.text('Search by name, phone or email'), findsNothing);
  });

  testWidgets('customer estimate setup stays on selected customer', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: EstimateJobSetupScreen(
        businessId: 'business',
        initialCustomerId: 'customer-123',
        initialCustomerName: 'Daniel Howard',
        initialVehicles: [
          {'id':'vehicle-1','year':2013,'make':'BMW','model':'X5'}
        ],
      ),
    ));
    expect(find.text('Daniel Howard'), findsOneWidget);
    expect(find.text('2013 BMW X5'), findsOneWidget);
    expect(find.text('Create Job & Continue'), findsOneWidget);
  });

  testWidgets('mechanic is not offered customer creation actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomerQuickActionsSheet(
          roleCode: 'mechanic',
          onSelected: (_) {},
        ),
      ),
    ));
    expect(find.byType(ListTile), findsNothing);
    expect(find.textContaining('not available'), findsOneWidget);
  });
}
