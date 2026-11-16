/// Validates a previously uploaded invoice before local records are reconciled.
/// No persistent writes or network calls are performed.
class OfflineInvoiceRecoveryProof {
  static void verify({
    required bool owner,
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> payments,
    required String businessId,
    required String invoiceId,
    required String invoiceOperationId,
    required String paymentOperationId,
    required int totalCents,
    required int paymentCents,
    required String paymentMethodId,
    required String paymentDate,
    required int expectedLineCount,
  }) {
    void check(bool valid, String description) {
      if (!valid) throw StateError('Recovery verification failed: $description');
    }

    int cents(Object? value) {
      final amount = value is num
          ? value
          : num.tryParse(value?.toString() ?? '');
      check(amount != null && amount.isFinite, 'invalid currency');
      return (amount! * 100).round();
    }

    check(owner, 'owner approval required');
    check(invoice['business_id'] == businessId, 'business mismatch');
    check(invoice['id'] == invoiceId, 'invoice mismatch');
    check(invoice['offline_operation_id'] == invoiceOperationId,
        'invoice operation mismatch');
    check(invoice['status'] == 'issued', 'invoice status mismatch');
    check(cents(invoice['total_amount']) == totalCents, 'total mismatch');
    check(invoice['line_count'] == expectedLineCount,
        'invoice line count mismatch');
    final matched = payments.where((payment) =>
        payment['invoice_id'] == invoiceId &&
        payment['operation_id'] == paymentOperationId &&
        payment['pending_sync'] != true).toList();
    check(payments.length == 1 && matched.length == 1,
        'payment identity or count mismatch');
    check(matched.single['id']?.toString().isNotEmpty == true &&
        matched.single['id']?.toString().startsWith('local-') != true,
        'authoritative payment ID missing');
    check(matched.single['_local_pending_payment'] != true,
        'projected payment cannot acknowledge server receipt');
    check(cents(matched.single['amount']) == paymentCents,
        'payment amount mismatch');
    check(matched.single['method_id'] == paymentMethodId,
        'payment method mismatch');
    check(matched.single['payment_date'] == paymentDate,
        'original payment date mismatch');
  }
}
