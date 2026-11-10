/// A read-only identity bridge for receipt capture -> pending payment ->
/// posted transaction. No amount-only reconciliation is permitted.
class InvoicePaymentIdentityBridge {
  const InvoicePaymentIdentityBridge._();

  /// Returns the posted transaction IDs in receipt order only when every
  /// original operation maps uniquely to a server pending payment and posted
  /// transaction, with exact cent amounts. Null means manual reconciliation.
  static List<String>? verifiedTransactions({
    required Map<String, int> localReceiptCents,
    required Map<String, String> pendingIdByOperation,
    required Map<String, String> transactionIdByPendingId,
    required Map<String, int> postedCentsByTransactionId,
  }) {
    if (localReceiptCents.isEmpty ||
        localReceiptCents.length != pendingIdByOperation.length ||
        pendingIdByOperation.length != transactionIdByPendingId.length ||
        transactionIdByPendingId.length != postedCentsByTransactionId.length) {
      return null;
    }
    final pendingIds = <String>{};
    final transactionIds = <String>{};
    final result = <String>[];
    for (final receipt in localReceiptCents.entries) {
      final operation = receipt.key.trim();
      final pending = pendingIdByOperation[operation]?.trim() ?? '';
      final transaction = transactionIdByPendingId[pending]?.trim() ?? '';
      if (operation.isEmpty || receipt.value <= 0 || pending.isEmpty ||
          transaction.isEmpty || !pendingIds.add(pending) ||
          !transactionIds.add(transaction) ||
          postedCentsByTransactionId[transaction] != receipt.value) {
        return null;
      }
      result.add(transaction);
    }
    return result;
  }
}
