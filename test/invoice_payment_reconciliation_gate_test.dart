import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/invoice_payment_reconciliation_gate.dart';

void main() {
  const first = 'receipt-original-3000';
  const second = 'receipt-original-4882';
  final local = <String, int>{first: 300000, second: 488211};
  final posted = <String, int>{first: 300000, second: 488211};

  bool allowed({
    Map<String, int>? localRows,
    Map<String, int>? postedRows,
    int allocated = 788211,
    bool pendingServer = false,
    bool pendingLocal = false,
  }) => InvoicePaymentReconciliationGate.canClose(
    invoiceTotalCents: 788211,
    localReceiptsByOperationId: localRows ?? local,
    postedReceiptsByOperationId: postedRows ?? posted,
    postedAllocationCents: allocated,
    hasPendingServerPayments: pendingServer,
    hasPendingLocalOperations: pendingLocal,
  );

  test('two uniquely matched posted receipts and exact allocations allow closure', () {
    expect(allowed(), isTrue);
  });
  test('zero displayed balance with no posted allocation fails closed', () {
    expect(allowed(allocated: 0), isFalse);
  });
  test('one server payment missing fails closed', () {
    expect(allowed(postedRows: {first: 300000}), isFalse);
  });
  test('same amount with different operation identity fails closed', () {
    expect(allowed(postedRows: {first: 300000, 'other': 488211}), isFalse);
  });
  test('changed amount on matching identity fails closed', () {
    expect(allowed(postedRows: {first: 300000, second: 488210}), isFalse);
  });
  test('local or server pending payment prevents closure', () {
    expect(allowed(pendingLocal: true), isFalse);
    expect(allowed(pendingServer: true), isFalse);
  });
  test('extra server payment prevents duplicate reconciliation', () {
    expect(allowed(postedRows: {...posted, 'duplicate': 300000}), isFalse);
  });
  test('blank identities and empty ledger are rejected', () {
    expect(allowed(localRows: {'': 300000, second: 488211}), isFalse);
    expect(allowed(localRows: <String, int>{}, postedRows: <String, int>{}), isFalse);
  });
}
