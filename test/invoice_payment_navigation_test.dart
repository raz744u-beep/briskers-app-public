import 'package:briskers_app/screens/jobs/invoice_payment_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const invoice = <String, dynamic>{
    'id': 'invoice-1',
    'kind': 'invoice',
    'document_number': '6303',
    'status': 'draft',
    'total_amount': 300,
    'paid_amount': 0,
    'pending_payment': 0,
  };
  test('payment shortcut is restricted to financial roles', () {
    for (final role in ['owner', 'manager', 'office']) {
      expect(canOpenJobInvoicePayment(role), isTrue);
    }
    for (final role in ['mechanic', 'customer', '', 'unknown']) {
      expect(canOpenJobInvoicePayment(role), isFalse);
    }
  });
  test('unpaid and pending invoices qualify without bypassing locks', () {
    expect(isJobInvoicePaymentEligible(invoice), isTrue);
    expect(
      isJobInvoicePaymentEligible({...invoice, 'pending_payment': 300}),
      isTrue,
    );
    expect(
      isJobInvoicePaymentEligible({...invoice, 'paid_amount': 300}),
      isFalse,
    );
    for (final status in ['void', 'closed', 'paid', 'cancelled']) {
      expect(
        isJobInvoicePaymentEligible({...invoice, 'status': status}),
        isFalse,
      );
    }
    expect(
      isJobInvoicePaymentEligible({...invoice, 'closed_at': '2026-10-01'}),
      isFalse,
    );
    expect(
      isJobInvoicePaymentEligible({...invoice, 'legacy_read_only': true}),
      isFalse,
    );
    expect(
      isJobInvoicePaymentEligible({...invoice, 'kind': 'estimate'}),
      isFalse,
    );
    expect(
      isJobInvoicePaymentEligible({...invoice, 'total_amount': double.nan}),
      isFalse,
    );
    expect(
      isJobInvoicePaymentEligible({...invoice, 'paid_amount': null}),
      isFalse,
    );
  });
  test(
    'offline selection requires complete detail and overlays queued receipts',
    () {
      final detail = {...invoice, 'job_id': 'job-1', 'legacy_read_only': false};
      expect(
        cachedJobInvoicePaymentSnapshot(invoice, null, jobId: 'job-1'),
        isNull,
      );
      expect(
        cachedJobInvoicePaymentSnapshot(invoice, {
          ...detail,
          'paid_amount': null,
        }, jobId: 'job-1'),
        isNull,
      );
      expect(
        cachedJobInvoicePaymentSnapshot(invoice, {
          ...detail,
          'job_id': 'other-job',
        }, jobId: 'job-1'),
        isNull,
      );
      expect(
        cachedJobInvoicePaymentSnapshot(invoice, {
          ...detail,
          'id': 'other-invoice',
        }, jobId: 'job-1'),
        isNull,
      );
      expect(
        cachedJobInvoicePaymentSnapshot(
          invoice,
          {...detail}..remove('legacy_read_only'),
          jobId: 'job-1',
        ),
        isNull,
      );
      final saved = cachedJobInvoicePaymentSnapshot(
        invoice,
        detail,
        jobId: 'job-1',
        queuedPayments: [
          {
            'operation_id': 'receipt-1',
            'amount_cents': 30000,
            'method_name': 'Cash',
          },
        ],
      );
      expect(saved?['pending_payment'], 300);
      expect(saved?['_local_pending_payment'], isTrue);
      expect(detail['pending_payment'], 0);
    },
  );
  testWidgets('invoice chooser supports selection and cancellation', (
    tester,
  ) async {
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Choose'),
              onPressed: () async {
                result = await chooseJobInvoice(
                  context,
                  invoices: [
                    invoice,
                    {...invoice, 'id': 'invoice-2', 'document_number': '6346'},
                  ],
                  title: 'Choose invoice for payment',
                  showBalance: true,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Invoice #6303'), findsOneWidget);
    expect(find.text('Invoice #6346'), findsOneWidget);
    await tester.tap(find.text('Invoice #6346'));
    await tester.pumpAndSettle();
    expect(result?['id'], 'invoice-2');
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
