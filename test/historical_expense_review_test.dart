import 'package:briskers_app/screens/payroll/historical_expense_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Reviews source transactions without attributing a matching name',
      (tester) async {
    final access = ValueNotifier(true);
    final searches = <String>[];
    await tester.pumpWidget(MaterialApp(home: HistoricalExpenseReview(
      initialSearch: 'Chris', source: 'Expenses saved on this device',
      access: access, canView: () => access.value,
      search: (query, offset, limit) async {
        searches.add(query);
        return [
          for (final id in ['original-a', 'original-b'])
            {'id': id, 'counterparty': 'Chris', 'amount': 42,
             'transaction_date': '2026-11-02', 'remarks': 'Original entry'},
        ];
      },
    )));
    await tester.pumpAndSettle();
    expect(searches, ['Chris']);
    expect(find.text('Chris'), findsNWidgets(3));
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Transaction ID: original-a'), findsOneWidget);
    expect(find.text('Original entry'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'wages');
    await tester.tap(find.byTooltip('Search expenses'));
    await tester.pumpAndSettle();
    expect(searches, ['Chris', 'wages']);
    access.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Owner access required.'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
  });
}
