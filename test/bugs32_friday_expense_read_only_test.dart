import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/historical_expense_review.dart';

void main() {
  testWidgets('Friday expense review is read only and shows original transaction ID',
      (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final access = ValueNotifier<bool>(true);
    addTearDown(access.dispose);
    final rows = <Map<String, dynamic>>[
      {
        'id': 'original-expense-11-06',
        'counterparty': 'Kam',
        'transaction_date': '2026-11-06',
        'amount': 450.0,
        'currency_code': 'USD',
        'remarks': 'Original Friday payment',
      },
    ];
    await tester.pumpWidget(MaterialApp(home: HistoricalExpenseReview(
      initialSearch: 'Kam',
      exactDate: DateTime(2026, 11, 6),
      access: access,
      canView: () => access.value,
      source: 'Expenses saved on this device',
      search: (query, offset, limit) async {
        expect(query, 'Kam');
        return rows.skip(offset).take(limit).toList();
      },
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('11/6/2026'), findsOneWidget);
    expect(find.text('Kam'), findsOneWidget);
    expect(find.textContaining('original-expense-11-06'), findsNothing);
    await tester.tap(find.text('Kam'));
    await tester.pumpAndSettle();
    expect(find.textContaining('original-expense-11-06'), findsOneWidget);
    expect(find.text('Save Payment'), findsNothing);
    expect(find.text('Mark Paid'), findsNothing);
  });
}
