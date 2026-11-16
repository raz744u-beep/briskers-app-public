import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/offline_invoice_recovery_proof.dart';

void main() {
  Map<String, dynamic> invoice() => {
    'business_id': 'test-shop',
    'id': 'test-invoice',
    'offline_operation_id': 'test-operation',
    'status': 'issued',
    'total_amount': 100.00,
    'line_count': 2,
  };
  Map<String, dynamic> payment() => {
    'invoice_id': 'test-invoice',
    'id': 'server-receipt-test',
    'operation_id': 'test-payment-operation',
    'amount': 30.00,
    'method_id': 'method-test',
    'payment_date': '2026-10-19',
  };

  void verify({
    bool owner = true,
    Map<String, dynamic>? document,
    List<Map<String, dynamic>>? receipts,
  }) {
    OfflineInvoiceRecoveryProof.verify(
      owner: owner,
      invoice: document ?? invoice(),
      payments: receipts ?? [payment()],
      businessId: 'test-shop',
      invoiceId: 'test-invoice',
      invoiceOperationId: 'test-operation',
      paymentOperationId: 'test-payment-operation',
      totalCents: 10000,
      paymentCents: 3000,
      paymentMethodId: 'method-test',
      paymentDate: '2026-10-19',
      expectedLineCount: 2,
    );
  }

  test('accepts exact original operations', verify);
  test('rejects non-owner', () =>
      expect(() => verify(owner: false), throwsStateError));
  test('rejects wrong invoice operation', () =>
      expect(() => verify(document: invoice()..['offline_operation_id'] = 'changed'),
          throwsStateError));
  test('rejects wrong status', () =>
      expect(() => verify(document: invoice()..['status'] = 'draft'),
          throwsStateError));
  test('rejects altered amount', () =>
      expect(() => verify(document: invoice()..['total_amount'] = 99.99),
          throwsStateError));
  test('rejects wrong line count', () =>
      expect(() => verify(document: invoice()..['line_count'] = 1),
          throwsStateError));
  test('rejects changed payment date', () =>
      expect(() => verify(receipts: [payment()..['payment_date'] = '2026-10-29']),
          throwsStateError));
  test('rejects changed payment method', () =>
      expect(() => verify(receipts: [payment()..['method_id'] = 'other']),
          throwsStateError));
  test('rejects missing server payment ID', () =>
      expect(() => verify(receipts: [payment()..remove('id')]),
          throwsStateError));
  test('rejects projected local payment', () =>
      expect(() => verify(receipts: [payment()..['_local_pending_payment'] = true]),
          throwsStateError));
  test('rejects duplicate payments', () =>
      expect(() => verify(receipts: [payment(), payment()]), throwsStateError));
  test('rejects pending local projection', () =>
      expect(() => verify(receipts: [payment()..['pending_sync'] = true]),
          throwsStateError));
  test('rejects different payment operation', () =>
      expect(() => verify(receipts: [payment()..['operation_id'] = 'another']),
          throwsStateError));
}
