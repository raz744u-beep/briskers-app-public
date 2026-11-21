import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/verified_invoice_payment_events.dart';
import 'package:briskers_app/screens/documents_screen.dart';

void main() {
  test('Verified fully-paid notification requires actual finalized coverage', () async {
    final captured = <VerifiedInvoiceFullyPaid>[];
    final subscription = VerifiedInvoicePaymentEvents.fullyPaid.listen(captured.add);
    const valid = VerifiedInvoiceFullyPaid(
      businessId: 'synthetic-shop',
      invoiceId: 'synthetic-invoice',
      total: 350,
      finalizedPaid: 350,
    );
    VerifiedInvoicePaymentEvents.confirmedFullyPaid(valid);
    VerifiedInvoicePaymentEvents.confirmedFullyPaid(const VerifiedInvoiceFullyPaid(
      businessId: 'synthetic-shop', invoiceId: 'not-paid',
      total: 350, finalizedPaid: 200,
    ));
    VerifiedInvoicePaymentEvents.confirmedFullyPaid(const VerifiedInvoiceFullyPaid(
      businessId: '', invoiceId: 'other', total: 350, finalizedPaid: 350,
    ));
    expect(captured, hasLength(1));
    expect(captured.single.invoiceId, 'synthetic-invoice');
    expect(captured.single.businessId, 'synthetic-shop');
    await subscription.cancel();
  });

  test('Confirmed fully paid is Pending Close until authoritative Closed', () {
    const previouslyOpen = <String, dynamic>{
      'id':'synthetic-invoice', 'kind':'invoice', 'status':'issued',
      'display_status_code':'open', 'total_amount':350.0,
      'paid_amount':0.0, 'pending_payment':0.0,
    };
    final retainedPaid = {
      ...previouslyOpen,
      'paid_amount':350.0,
      'pending_payment':0.0,
      'display_status_code':'pending_close',
    };
    expect(invoiceListStageWithReceipts(retainedPaid, receipts:350), 'Pending Close');
    expect(invoiceListStageWithReceipts({
      ...retainedPaid, 'status':'closed',
      'display_status_code':'closed',
    }, receipts:0), 'Closed');
    expect(invoiceListStageWithReceipts(previouslyOpen,receipts:0),'Open');
  });

  test('On receipt verification, lists repaint before the Job-complete prompt', () {
    final docs=File('lib/screens/documents_screen.dart').readAsStringSync();
    final detail=File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    expect(docs, contains('VerifiedInvoicePaymentEvents.fullyPaid.listen('));
    expect(docs, contains('_verifiedFullyPaidInvoiceIds.add(event.invoiceId)'));
    expect(docs, contains("return 'Pending Close';"));
    expect(docs, contains("event.businessId != widget.businessId"));
    expect(docs, contains("row['id']?.toString() == event.invoiceId"));
    expect(docs, contains('_verifiedFullyPaidInvoiceIds.clear()'));
    expect(docs, contains('_verifiedFullyPaidInvoiceIds.remove(event.invoiceId)'));
    final finalize=detail.split('Future<void> _finalizeEnteredPayments() async {').last
      .split('Future<void> _enterWarrantyPayment() async {').first;
    expect(finalize, contains('presentation.paymentDetailsKnown'));
    expect(finalize, contains('presentation.finalizedCents! / 100'));
    expect(finalize, contains('identity == widget.documentId'));
    expect(finalize.indexOf('VerifiedInvoicePaymentEvents.confirmedFullyPaid('),
      lessThan(finalize.indexOf('await _offerCompletePaidJob();')));
    expect(finalize, contains('await _autoCloseOwnerInvoiceIfReady();'));
    expect(finalize, contains('await _load(fastAfterMutation: true)'));
  });
}
