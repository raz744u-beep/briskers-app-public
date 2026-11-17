import 'package:briskers_app/screens/payroll/payroll_history_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('history uses settlement figures and separate real record links',
      (tester) async {
    final unlocked = ValueNotifier(true);
    addTearDown(unlocked.dispose);
    String? openedJob;
    String? openedInvoice;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: PayrollHistoryPanel(
        unlocked: unlocked,
        onOpenJob: (id) => openedJob = id,
        onOpenInvoice: (id) => openedInvoice = id,
        payments: const [
          {
            'week': '2026-10-26',
            'gross': 8500, 'repayment': 2000, 'net': 6500,
            'work': <Map<String, dynamic>>[
              {
                'credit_id': 'credit', 'operation_id': 'payment',
                'description': 'Repair', 'gross_cents': 10000,
                'job_id': 'job-id', 'invoice_id': 'invoice-id',
                'job_number': 'J-24', 'document_number': '#6342',
                'vehicle_label': '2012 Hyundai Equus', 'actual_minutes': 150,
                'method': 'Cash', 'verified_date': '2026-10-28',
              },
            ],
          },
        ],
      ),
    )));
    final paidCard = find.ancestor(of: find.text('Paid portion'), matching: find.byType(Card)).first;
    expect(tester.getTopLeft(find.text('Tap to view details')).dy,
      greaterThan(tester.getBottomLeft(paidCard).dy));
    await tester.tap(find.text('All Time'));
    await tester.pumpAndSettle();
    expect(find.text('Payroll History · Date range'), findsOneWidget);
    expect(tester.getTopLeft(find.text('2026')).dy,
      greaterThan(tester.getTopLeft(find.text('All Time').last).dy));
    await tester.tap(find.text('2026'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Total paid · 2026'), findsOneWidget);
    await tester.tap(find.text('Tap to view details'));
    await tester.pumpAndSettle();
    expect(find.text('Gross Pay'), findsOneWidget);
    expect(find.text('Debt Repaid'), findsOneWidget);
    expect(find.text('Transferred'), findsOneWidget);
    expect(find.text(r'$85.00'), findsOneWidget);
    expect(find.text(r'$20.00'), findsOneWidget);
    expect(find.text(r'$65.00'), findsOneWidget);
    expect(find.text(r'$100.00'), findsOneWidget);
    await tester.tap(find.textContaining('Job J-24'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Job'));
    await tester.tap(find.text('Open Invoice'));
    expect(openedJob, 'job-id');
    expect(openedInvoice, 'invoice-id');
    unlocked.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Owner payroll locked.'), findsOneWidget);
    expect(find.text(r'$100.00'), findsNothing);
  });
}
