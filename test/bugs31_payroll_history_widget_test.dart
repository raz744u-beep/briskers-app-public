import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/payroll_history_panel.dart';

void main() {
  testWidgets('TEST history layout keeps recorded gross, debt and net distinct',
      (tester) async {
    final unlocked = ValueNotifier<bool>(true);
    addTearDown(unlocked.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PayrollHistoryPanel(
          unlocked: unlocked,
          onOpenJob: (_) {},
          onOpenInvoice: (_) {},
          payments: <Map<String, dynamic>>[
            <String, dynamic>{
              'week': '2026-10-26',
              'gross': 10000,
              'repayment': 2000,
              'net': 8000,
              'verified_date': '2026-10-30',
              'method': 'Cash',
              'work': <Map<String, dynamic>>[
                <String, dynamic>{
                  'credit_id': 'credit-1',
                  'description': 'Test service',
                  'gross_cents': 10000,
                  'actual_minutes': 60,
                  'method': 'Cash',
                  'verified_date': '2026-10-30',
                  'operation_id': 'test-operation',
                },
              ],
            },
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Payroll History'), findsOneWidget);
    expect(find.text('Paid portion'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('Total paid · All'), findsOneWidget);
    expect(find.text('\$100.00'), findsWidgets);
    expect(find.text('\$80.00'), findsNothing);

    await tester.tap(find.text('Paid portion'));
    await tester.pumpAndSettle();
    expect(find.text('Debt repaid'), findsOneWidget);
    expect(find.text('Transferred'), findsOneWidget);
    expect(find.text('\$20.00'), findsOneWidget);
    expect(find.text('\$80.00'), findsOneWidget);
    expect(find.text('Paid tasks (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
