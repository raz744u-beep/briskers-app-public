import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/screens/expenses/transaction_recurring_dialog.dart';

void main() {
  const base = <String, dynamic>{
    'id': 'transaction-1',
    'direction': 'expense',
    'amount': 95.49,
    'account_id': 'account-1',
    'category_id': 'uniforms',
    'counterparty_id': 'cintas',
    'remarks': 'Uniforms',
  };

  testWidgets('general expense can be scheduled as recurring',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TransactionRecurringDialog(
          businessId: 'business-1',
          transactionId: 'transaction-1',
          transaction: base,
        ),
      ),
    ));
    expect(find.text('Make recurring'), findsOneWidget);
    expect(find.text('Next occurrence'), findsOneWidget);
    expect(find.text('Start repeating'), findsOneWidget);
    expect(find.text('Stop repeating'), findsNothing);
  });

  testWidgets('existing recurring expense exposes change and stop actions',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TransactionRecurringDialog(
          businessId: 'business-1',
          transactionId: 'transaction-1',
          transaction: <String, dynamic>{
            ...base,
            'recurring_rule': <String, dynamic>{
              'id': 'rule-1',
              'is_repeating': true,
              'frequency': 'weekly',
              'interval_count': 1,
              'next_date': '2026-10-14',
            },
          },
        ),
      ),
    ));
    expect(find.text('Manage recurring transaction'), findsOneWidget);
    expect(find.text('Save schedule'), findsOneWidget);
    expect(find.text('Stop repeating'), findsOneWidget);
  });
}
