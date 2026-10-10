import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/customers/customer_problem_flag_card.dart';

void main() {
  testWidgets('flagged customer note is collapsed until expanded', (tester) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerProblemFlagCard(
            customerId: 'test-customer',
            flagged: true,
            note: 'Original customer flag note',
            canEdit: true,
            onEdit: () => edits++,
          ),
        ),
      ),
    );

    expect(find.text('Problem customer'), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsOneWidget);
    expect(find.text('Original customer flag note'), findsNothing);

    await tester.tap(find.text('Problem customer'));
    await tester.pumpAndSettle();
    expect(find.text('Original customer flag note'), findsOneWidget);
    expect(find.text('Flag reason / note'), findsOneWidget);

    await tester.tap(find.text('Flag reason / note'));
    expect(edits, 1);
    await tester.tap(find.text('Problem customer'));
    await tester.pumpAndSettle();
    expect(find.text('Original customer flag note'), findsNothing);
  });

  testWidgets('readonly flag stays accessible but cannot be edited', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomerProblemFlagCard(
            customerId: 'readonly-customer',
            flagged: true,
            note: 'Existing note',
            canEdit: false,
            onEdit: _noOp,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Problem customer'));
    await tester.pumpAndSettle();
    expect(find.text('Existing note'), findsOneWidget);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Flag reason / note')).onTap, isNull);
  });

  testWidgets('unflagged customer shows compact collapsed header', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomerProblemFlagCard(
            customerId: 'unflagged-customer',
            flagged: false,
            note: '',
            canEdit: true,
            onEdit: _noOp,
          ),
        ),
      ),
    );
    expect(find.text('Problem customer'), findsOneWidget);
    expect(find.byIcon(Icons.outlined_flag), findsOneWidget);
    expect(find.text('Show a red flag beside this customer throughout Briskers.'), findsNothing);
    await tester.tap(find.text('Problem customer'));
    await tester.pumpAndSettle();
    expect(find.text('Show a red flag beside this customer throughout Briskers.'), findsOneWidget);
  });
}

void _noOp() {}
