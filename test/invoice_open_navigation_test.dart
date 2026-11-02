import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/local_document_repository.dart';

void main() {
  Map<String, dynamic> invoice({
    num total = 100,
    String status = 'issued',
    String? hint,
  }) => <String, dynamic>{
    'kind': 'invoice',
    'id': 'i1',
    'status': status,
    'display_status_code': hint,
    'total_amount': total,
    'paid_amount': 0,
    'pending_payment': 0,
    '_local_snapshot': true,
  };

  test('Open invoices exclude fully received cash/card before finalization', () {
    expect(invoiceNeedsPayment(invoice(), receipts: 0), isTrue);
    expect(invoiceNeedsPayment(invoice(), receipts: 20), isTrue);
    expect(invoiceNeedsPayment(invoice(), receipts: 100), isFalse);
    expect(invoiceNeedsPayment(invoice(), receipts: 125), isFalse);
  });

  test('local receipt aggregation respects individual invoice identities', () {
    final amounts = invoiceRecordedReceiptTotals([
      {'invoice_id': 'i1', 'amount': 20},
      {'invoice_id': 'i1', 'amount': 80},
      {'invoice_id': 'i2', 'amount': 17.5},
      {'invoice_id': 'i1', 'amount': 0},
    ]);
    expect(amounts['i1'], 100);
    expect(amounts['i2'], 17.5);
    expect(invoiceNeedsPayment(invoice(), receipts: amounts['i1']!), isFalse);
  });

  test('server pending-close and paid hints exclude covered local index', () {
    expect(invoiceNeedsPayment(invoice(hint: 'pending_close')), isFalse);
    expect(invoiceNeedsPayment(invoice(hint: 'paid')), isFalse);
    expect(invoiceNeedsPayment(invoice(hint: 'open')), isTrue);
  });

  test('closed and void invoices remain outside Open regardless of receipts', () {
    expect(invoiceNeedsPayment(invoice(status: 'void')), isFalse);
    expect(invoiceNeedsPayment(invoice(status: 'closed')), isFalse);
    expect(invoiceNeedsPayment(invoice()..['closed_at']='2026-10-17'), isFalse);
  });

  test('uncertain invoice payment coverage stays in Open; no fabricated paid balance', () {
    expect(invoiceNeedsPayment(invoice(total: 0)), isTrue);
    final ambiguous = invoice(total: 100)..['display_status_code']='paid';
    ambiguous['_payment_reconciliation_required'] = true;
    expect(invoiceNeedsPayment(ambiguous), isTrue);
  });
}
