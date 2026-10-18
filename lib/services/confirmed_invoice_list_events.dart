import 'dart:async';

/// A presentation notification, never an instruction to close an invoice.
/// Published ONLY after the backend confirms a permanent closed_at timestamp.
class ConfirmedInvoiceClosed {
  const ConfirmedInvoiceClosed({
    required this.businessId,
    required this.invoiceId,
    required this.closedAt,
    required this.rowVersion,
  });
  final String businessId;
  final String invoiceId;
  final String closedAt;
  final int rowVersion;
}

class ConfirmedInvoiceListEvents {
  static final StreamController<ConfirmedInvoiceClosed> _closed =
      StreamController<ConfirmedInvoiceClosed>.broadcast(sync: true);
  static Stream<ConfirmedInvoiceClosed> get closed => _closed.stream;

  static void publishClosed(ConfirmedInvoiceClosed event) {
    if (event.businessId.isEmpty ||
        event.invoiceId.isEmpty ||
        DateTime.tryParse(event.closedAt) == null ||
        event.rowVersion < 1) {
      throw StateError('Confirmed invoice closure requires server evidence.');
    }
    _closed.add(event);
  }
}
