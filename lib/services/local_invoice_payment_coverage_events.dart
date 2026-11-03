import 'dart:async';

/// A local payment entry has been durably recorded. This event is only a
/// presentation hint, NOT a finalized payment or a verified invoice close.
class LocalInvoicePaymentCoverageChanged {
  const LocalInvoicePaymentCoverageChanged({
    required this.businessId,
    required this.invoiceId,
    required this.coversRemainingBalance,
  });

  final String businessId;
  final String invoiceId;
  final bool coversRemainingBalance;
}

class LocalInvoicePaymentCoverageEvents {
  const LocalInvoicePaymentCoverageEvents._();

  static final StreamController<LocalInvoicePaymentCoverageChanged> _changes =
      StreamController<LocalInvoicePaymentCoverageChanged>.broadcast(sync: true);

  static Stream<LocalInvoicePaymentCoverageChanged> get changes =>
      _changes.stream;

  /// Call only AFTER a successful durable payment queue mutation.
  static void committed(LocalInvoicePaymentCoverageChanged event) {
    if (event.businessId.isEmpty || event.invoiceId.isEmpty) return;
    _changes.add(event);
  }
}
