import 'dart:async';

/// Only emit after the backend confirms a finalized, fully-paid invoice.
/// This is not an invoice-close event: the server may still require a
/// separate close operation. Never emit for entered/queued/pending receipts.
class VerifiedInvoiceFullyPaid {
  const VerifiedInvoiceFullyPaid({
    required this.businessId,
    required this.invoiceId,
    required this.total,
    required this.finalizedPaid,
  });

  final String businessId;
  final String invoiceId;
  final num total;
  final num finalizedPaid;
}

class VerifiedInvoicePaymentEvents {
  VerifiedInvoicePaymentEvents._();

  static final StreamController<VerifiedInvoiceFullyPaid> _paid =
      StreamController<VerifiedInvoiceFullyPaid>.broadcast(sync: true);

  static Stream<VerifiedInvoiceFullyPaid> get fullyPaid => _paid.stream;

  static void confirmedFullyPaid(VerifiedInvoiceFullyPaid event) {
    if (event.businessId.isEmpty || event.invoiceId.isEmpty ||
        !event.total.isFinite || event.total <= 0 ||
        !event.finalizedPaid.isFinite ||
        event.finalizedPaid < event.total - 0.005) {
      return;
    }
    _paid.add(event);
  }
}
