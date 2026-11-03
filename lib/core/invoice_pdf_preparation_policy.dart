/// Read-only safeguards for document PDF preparation.
///
/// A numbered invoice may have an older cached `draft` status. Issuing that
/// record again on every preview/send can fail when Auto network is unstable.
/// A *new* document with no permanent number still requires server issuance.
class InvoicePdfPreparationPolicy {
  const InvoicePdfPreparationPolicy._();

  static bool needsIssue(Map<String, dynamic>? detail) {
    final number = detail?['document_number']?.toString().trim() ?? '';
    return number.isEmpty;
  }

  static bool isTransportFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('clientexception') ||
        message.contains('socketexception') ||
        message.contains('connection abort') ||
        message.contains('connection reset') ||
        message.contains('connection closed') ||
        message.contains('failed host lookup') ||
        message.contains('timeout') ||
        message.contains('network is unreachable');
  }

  static bool canOfferCachedPdf(Map<String, dynamic>? detail) {
    if (detail == null) return false;
    final number = detail['document_number']?.toString().trim() ?? '';
    final lines = detail['lines'];
    final customer = detail['customer_id']?.toString().trim() ?? '';
    final vehicle = detail['vehicle_id']?.toString().trim() ?? '';
    return number.isNotEmpty && customer.isNotEmpty && vehicle.isNotEmpty &&
        lines is List && lines.isNotEmpty &&
        detail['kind']?.toString() != 'estimate' &&
        detail['status']?.toString().toLowerCase() != 'void';
  }
}
