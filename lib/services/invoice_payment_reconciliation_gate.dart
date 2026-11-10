/// Pure, read-only decision gate for offline invoice-payment reconciliation.
///
/// This does not finalize, post, close, or change any payment. It prevents
/// a displayed zero balance from being mistaken for a reconciled ledger.
class InvoicePaymentReconciliationGate {
  const InvoicePaymentReconciliationGate._();

  /// Returns true only if every locally recorded receipt has a unique,
  /// matching server operation identity and amount, and posted allocations
  /// exactly cover the invoice. Unknown/missing identities fail closed.
  static bool canClose({
    required int invoiceTotalCents,
    required Map<String, int> localReceiptsByOperationId,
    required Map<String, int> postedReceiptsByOperationId,
    required int postedAllocationCents,
    required bool hasPendingServerPayments,
    required bool hasPendingLocalOperations,
  }) {
    if (invoiceTotalCents <= 0 || hasPendingServerPayments ||
        hasPendingLocalOperations || postedAllocationCents != invoiceTotalCents ||
        localReceiptsByOperationId.isEmpty ||
        localReceiptsByOperationId.length != postedReceiptsByOperationId.length) {
      return false;
    }
    var localTotal = 0;
    var postedTotal = 0;
    for (final entry in localReceiptsByOperationId.entries) {
      if (entry.key.trim().isEmpty || entry.value <= 0 ||
          postedReceiptsByOperationId[entry.key] != entry.value) {
        return false;
      }
      localTotal += entry.value;
    }
    for (final entry in postedReceiptsByOperationId.entries) {
      if (entry.key.trim().isEmpty || entry.value <= 0 ||
          !localReceiptsByOperationId.containsKey(entry.key)) {
        return false;
      }
      postedTotal += entry.value;
    }
    return localTotal == invoiceTotalCents &&
        postedTotal == invoiceTotalCents;
  }
}
