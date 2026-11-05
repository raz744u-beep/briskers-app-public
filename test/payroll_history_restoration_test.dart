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
    await tester.tap(find.text('Week of Oct 26, 2026'));
    await tester.pumpAndSettle();
    expect(find.text('Gross pay'), findsOneWidget);
    expect(find.text('Debt repaid'), findsOneWidget);
    expect(find.text('Transferred'), findsOneWidget);
    expect(find.text('$85.00'), findsOneWidget);
    expect(find.text('$20.00'), findsOneWidget);
    expect(find.text('$65.00'), findsOneWidget);
    expect(find.text('Paid · $100.00'), findsOneWidget);
    await tester.tap(find.text('Job J-24'));
    await tester.tap(find.text('Invoice #6342'));
    expect(openedJob, 'job-id');
    expect(openedInvoice, 'invoice-id');
    unlocked.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Owner payroll locked.'), findsOneWidget);
    expect(find.text('Paid · $100.00'), findsNothing);
  });
}
