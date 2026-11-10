import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/invoice_payment_identity_bridge.dart';

void main() {
  const local = {'op-a': 300000, 'op-b': 488211};
  const pending = {'op-a': 'pending-a', 'op-b': 'pending-b'};
  const posted = {'pending-a': 'tx-a', 'pending-b': 'tx-b'};
  const cents = {'tx-a': 300000, 'tx-b': 488211};
  List<String>? verify({
    Map<String, int> receipts = local,
    Map<String, String> pendingIds = pending,
    Map<String, String> transactions = posted,
    Map<String, int> amounts = cents,
  }) => InvoicePaymentIdentityBridge.verifiedTransactions(
    localReceiptCents: receipts,
    pendingIdByOperation: pendingIds,
    transactionIdByPendingId: transactions,
    postedCentsByTransactionId: amounts,
  );

  test('exact identity chain accepts both original receipts', () {
    expect(verify(), ['tx-a', 'tx-b']);
  });
  test('missing pending identity fails closed', () {
    expect(verify(pendingIds: {'op-a': 'pending-a'}), isNull);
  });
  test('duplicate pending ID fails closed', () {
    expect(verify(pendingIds: {'op-a': 'pending-a', 'op-b': 'pending-a'}), isNull);
  });
  test('duplicate transaction ID fails closed', () {
    expect(verify(transactions: {'pending-a': 'tx-a', 'pending-b': 'tx-a'}), isNull);
  });
  test('mismatched posted amount fails closed', () {
    expect(verify(amounts: {'tx-a': 300000, 'tx-b': 488210}), isNull);
  });
  test('amount-only match without original operation identity fails closed', () {
    expect(verify(pendingIds: {'other': 'pending-a', 'op-b': 'pending-b'}), isNull);
  });
  test('extra posted transaction fails closed', () {
    expect(verify(amounts: {...cents, 'tx-extra': 300000}), isNull);
  });
  test('empty receipt ledger fails closed', () {
    expect(verify(receipts: {}), isNull);
  });
}
