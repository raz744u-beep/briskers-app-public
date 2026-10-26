import 'dart:async';

/// A backend-confirmed invoice closure. Never broadcast for a locally assumed
/// payment, Job completion, or an unacknowledged/pending close request.
class VerifiedInvoiceClosed {
  const VerifiedInvoiceClosed({
    required this.businessId,
    required this.invoiceId,
  });

  final String businessId;
  final String invoiceId;
}

class VerifiedInvoiceCloseEvents {
  VerifiedInvoiceCloseEvents._();

  static final StreamController<VerifiedInvoiceClosed> _events =
      StreamController<VerifiedInvoiceClosed>.broadcast(sync: true);

  static Stream<VerifiedInvoiceClosed> get changes => _events.stream;

  static void serverConfirmed(VerifiedInvoiceClosed event) {
    if (event.businessId.isEmpty || event.invoiceId.isEmpty) {
      return;
    }
    _events.add(event);
  }
}
