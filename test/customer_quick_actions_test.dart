import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/customers/customer_quick_actions.dart';

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
