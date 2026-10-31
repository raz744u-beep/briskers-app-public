/// A fail-closed proof gate for the one-off Gloria recovery.
////
/// This does not change the database or acknowledge any queued operation.
/// The caller must independently obtain an authoritative server snapshot
/// (never from a locally projected payment or unverified user-entered IDs).
/// Once the gate passes, the existing offline repositories must perform
/// remapping and queue retirement atomically, under Owner authorization.
class GloriaReconciliationGuard {
  static const operationId = 'f9eaf3b3-3a9c-427a-8c8f-8f01d0fa6385';
  static const paymentOperationId =
      '3c62a672-fd29-4133-af10-7c568a61f3f3';
  static const localCustomerId = 'local-customer-1793301637612107';
  static const localVehicleId = 'local-vehicle-1793301794872090';
  static const localInvoiceId =
      'local-invoice-f9eaf3b3-3a9c-427a-8c8f-8f01d0fa6385';
  static const localJobId =
      'local-job-f9eaf3b3-3a9c-427a-8c8f-8f01d0fa6385';
  static const businessId = '93403e82-42b4-465c-b539-b5e127104f1b';
  static const invoiceId = '4bc125a0-7954-4036-82f2-4650847463f3';
  static const jobId = 'c6a23164-c09a-490d-8b00-c3e84e7282fb';

  static void validate({
    required bool isOwner,
    required String requestedBusinessId,
    required Map<String, dynamic> localInvoice,
    required Map<String, dynamic> authoritativeInvoice,
    required List<Map<String, dynamic>> authoritativePayments,
    required Map<String, dynamic> localPaymentOutbox,
  }) {
    void check(bool ok, String why) {
      if (!ok) throw StateError('Gloria reconciliation refused: $why');
    }

    int cents(Object? value) {
      final n = value is num ? value : num.tryParse(value?.toString() ?? '');
      check(n != null && n.isFinite, 'invalid amount');
      return (n! * 100).round();
    }

    check(isOwner, 'Owner authorization required');
    check(requestedBusinessId == businessId, 'business mismatch');
    check(localInvoice['id'] == localInvoiceId, 'local invoice mismatch');
    check(localInvoice['customer_id'] == localCustomerId,
        'local customer mismatch');
    check(localInvoice['job_id'] == localJobId, 'local job mismatch');
    check(localInvoice['total'] != null &&
        cents(localInvoice['total']) == 788211, 'local total mismatch');
    check(authoritativeInvoice['id'] == invoiceId,
        'server invoice mismatch');
    check(authoritativeInvoice['job_id'] == jobId,
        'server job mismatch');
    check(authoritativeInvoice['business_id'] == businessId,
        'server business mismatch');
    check(authoritativeInvoice['document_number']?.toString() == '6359',
        'invoice number mismatch');
    check(authoritativeInvoice['status'] == 'issued',
        'server invoice not issued');
    check(cents(authoritativeInvoice['net_amount']) == 718188,
        'net mismatch');
    check(cents(authoritativeInvoice['tax_amount']) == 70023,
        'tax mismatch');
    check(cents(authoritativeInvoice['total_amount']) == 788211,
        'gross mismatch');
    check(authoritativeInvoice['line_count'] == 18,
        'line count mismatch');
    check(authoritativeInvoice['offline_operation_id'] == operationId,
        'invoice operation mismatch');
    check(localPaymentOutbox['operation_id'] == paymentOperationId,
        'local payment operation mismatch');
    check(localPaymentOutbox['invoice_id'] == localInvoiceId,
        'local payment invoice mismatch');
    check(localPaymentOutbox['amount_cents'] == 300000,
        'local payment amount mismatch');
    check(localPaymentOutbox['method_id'] ==
        '67018807-21a1-4a60-87dd-a5b90b662b05',
        'local payment method mismatch');
    check(localPaymentOutbox['payment_date'] == '2026-10-19',
        'local payment date mismatch');
    // There must be exactly one server record with the same operation ID.
    // Amount matching alone is never sufficient.
    final matching = authoritativePayments.where((payment) =>
        payment['operation_id'] == paymentOperationId &&
        payment['invoice_id'] == invoiceId &&
        payment['method_id'] ==
            '67018807-21a1-4a60-87dd-a5b90b662b05' &&
        payment['payment_date'] == '2026-10-19' &&
        payment['pending_sync'] != true &&
        cents(payment['amount']) == 300000).toList();
    check(matching.length == 1 && authoritativePayments.length == 1,
        'payment identity or count mismatch');
  }
}
