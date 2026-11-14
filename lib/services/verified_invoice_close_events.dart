import 'dart:async';

/// A durable invoice closure, committed locally or acknowledged by the backend.
/// Task completion and payment entry alone never emit this event.
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

  static void locallyCommitted(VerifiedInvoiceClosed event) => serverConfirmed(event);

  static void serverConfirmed(VerifiedInvoiceClosed event) {
    if (event.businessId.isEmpty || event.invoiceId.isEmpty) {
      return;
    }
    _events.add(event);
  }
}
