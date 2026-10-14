import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/warranty_payment_amounts.dart';
import 'package:briskers_app/services/warranty_receipt_reporting.dart';
import 'package:briskers_app/services/document_pdf_service.dart';

void main() {
  const warranty = <String, dynamic>{'extended_warranty': true,
    'approved_amount': 515, 'terminal_amount': 515,
    'processor_fee': 15, 'net_applied': 500, 'surcharge_rate': 0.03};
  const cash = <String, dynamic>{'id': 'cash-receipt', 'amount': 1545,
    'payment_method_name': 'Cash', 'state': 'posted'};
  const card = <String, dynamic>{'id': 'card-receipt', 'amount': 515,
    'payment_method_name': 'Credit card', 'state': 'posted'};
  const invoice = <String, dynamic>{'id': 'synthetic-invoice', 'total_amount': 2060,
    'paid_amount': 2060, 'pending_payment': 0, 'payments': [cash, card]};
  Map<String, dynamic> row(Map<String, dynamic> payment) =>
    {...payment, 'direction': 'income', 'signed_amount': payment['amount']};

  test('synthetic fully paid invoice keeps gross credit and deducts fee once from retained receipts', () {
    final a = WarrantyReceiptReporting.project(row(cash), invoice, warranty);
    final b = WarrantyReceiptReporting.project(row(card), invoice, warranty);
    expect(WarrantyReceiptReporting.amount(a), 1545);
    expect(WarrantyReceiptReporting.amount(b), 500);
    expect(a['amount'], 1545);
    expect(b['amount'], 515);
    expect(b['signed_amount'], 515);
    expect(b['reporting_processor_fee'], 15);
    expect(DocumentPdfService.invoicePaymentAmounts(invoice)['remaining'], 0);
    expect(invoice['paid_amount'], 2060);
  });
  test('projection repeated cannot deduct twice', () {
    final first = WarrantyReceiptReporting.project(row(card), invoice, warranty);
    final repeated = WarrantyReceiptReporting.project(first, invoice, warranty);
    expect(repeated, first);
    expect(repeated['reporting_amount'], 500);
  });
  test('equal amount with different transaction identity is not attributed', () {
    final result = WarrantyReceiptReporting.project({...row(card), 'id': 'unrelated'}, invoice, warranty);
    expect(result['reporting_status'], 'unverified');
    expect(WarrantyReceiptReporting.amount(result), 515);
  });
  test('legacy calculator net receipt is blocked for capture and never reduced again', () {
    final oldWarranty = {...warranty, 'approved_amount': 103,
      'terminal_amount': 100, 'net_applied': 100, 'processor_fee': 3};
    final oldCard = {...card, 'amount': 100};
    expect(WarrantyPaymentAmounts.hasCandidateReceipt(oldWarranty, [oldCard]), isTrue);
    expect(WarrantyPaymentAmounts.receipt(oldWarranty, [oldCard]), isNull);
    final result = WarrantyReceiptReporting.project(row(oldCard), {'payments': [oldCard]}, oldWarranty);
    expect(result['reporting_status'], 'unverified');
    expect(WarrantyReceiptReporting.amount(result), 100);
  });
  test('split and duplicate receipts are ambiguous and capture stays blocked', () {
    for (final payments in [[card, {...card, 'id': 'second'}], [card, card]]) {
      expect(WarrantyPaymentAmounts.hasCandidateReceipt(warranty, payments), isTrue);
      expect(WarrantyPaymentAmounts.receipt(warranty, payments), isNull);
      final result = WarrantyReceiptReporting.project(row(card), {'payments': payments}, warranty);
      expect(result['reporting_status'], 'unverified');
    }
  });
  test('zero-percent check has no fee and retains full receipt', () {
    final check = {...card, 'payment_method_name': 'Check'};
    final result = WarrantyReceiptReporting.project(row(check), {'payments': [check]},
      {...warranty, 'processor_fee': 0, 'surcharge_rate': 0, 'net_applied': 515});
    expect(result['reporting_amount'], 515);
    expect(result['reporting_processor_fee'], 0);
  });
  test('a partial customer check is not labeled as the warranty receipt', () {
    final check = {...card, 'amount': 100, 'payment_method_name': 'Check'};
    expect(WarrantyPaymentAmounts.receipt({...warranty,
      'surcharge_rate': 0, 'processor_fee': 0, 'net_applied': 515}, [check]), isNull);
  });
  test('pending or reversed receipt never becomes posted income', () {
    for (final state in ['pending', 'reversed', 'voided']) {
      final payment = {...card, 'state': state};
      final result = WarrantyReceiptReporting.project(row(payment), {'payments': [payment]}, warranty);
      expect(result['reporting_status'], 'unverified');
      expect(result['reporting_amount'], isNull);
    }
  });
  test('malformed/nonfinite amounts and fee above gross fail safely', () {
    for (final amount in [double.nan, double.infinity, 1e308, -1, 'bad']) {
      expect(WarrantyPaymentAmounts.cents(amount), isNull);
    }
    expect(WarrantyPaymentAmounts.fromReceipt(gross: 10, processorFee: 11), isNull);
    expect(WarrantyPaymentAmounts.fromReceipt(gross: 10.25, processorFee: 0.15)!.retained, 10.10);
  });
  test('tax-exclusive allocation net_amount never drives retained receipts', () {
    final result = WarrantyReceiptReporting.project({...row(card), 'net_amount': 476.85}, invoice, warranty);
    expect(result['reporting_amount'], 500);
    expect(result['net_amount'], 476.85);
  });
  test('newer local detail cannot be replaced by stale reporting context', () {
    final old = {...invoice, 'row_version': 12, 'offline_warranty_detail': warranty};
    final newer = {...invoice, 'row_version': 13, 'payments': [cash, card, {...card, 'id': 'second'}]};
    expect(WarrantyReceiptReporting.newerContext(newer, old), newer);
    expect(WarrantyReceiptReporting.newerContext({...newer, 'row_version': 12}, old)['payments'], newer['payments']);
    final pending = {...old, 'sync_state': 'pending'};
    expect(WarrantyReceiptReporting.newerContext(pending, old).containsKey('offline_warranty_detail'), isFalse);
  });
  test('unverified clears stale retained fields and nonwarranty still requires exact ID', () {
    final stale = {...row(card), 'reporting_amount': 500, 'reporting_processor_fee': 15};
    expect(WarrantyReceiptReporting.unverified(stale).containsKey('reporting_amount'), isFalse);
    expect(WarrantyReceiptReporting.project({...stale, 'id': 'unrelated'}, invoice,
      {'extended_warranty': false})['reporting_status'], 'unverified');
  });
  test('expense amount never uses stale income reporting fields', () {
    expect(WarrantyReceiptReporting.amount({'direction': 'expense', 'amount': 515,
      'reporting_amount': 500, 'reporting_status': 'verified'}), 515);
  });
  test('future calculator plan stays separate from actual receipt correction', () {
    final calculator = File('lib/screens/settings/warranty_payment_calculator_screen.dart').readAsStringSync();
    expect(calculator, contains('approvedCents / 1.03'));
    final panel = File('lib/screens/jobs/invoice_warranty_panel.dart').readAsStringSync();
    expect(panel, contains("receipt == null ? _number(widget.detail['terminal_amount'])"));
    expect(panel, contains("? _number(widget.detail['customer_responsibility'])"));
    final pdf = File('lib/services/document_pdf_service.dart').readAsStringSync();
    expect(pdf, contains("detail['customer_responsibility']"));
    // Planned103 approval -> base100 + fee3; customer share900 stays the quote.
    const plan = {'extended_warranty': true, 'approved_amount': 103,
      'terminal_amount': 100, 'net_applied': 100, 'processor_fee': 3,
      'customer_responsibility': 900, 'surcharge_rate': 0.03};
    expect(WarrantyPaymentAmounts.receipt(plan, []), isNull);
    expect(plan['customer_responsibility'], 900);
  });
  test('new capture uses confirmed gross and prior queue snapshot; no fee transaction', () {
    final source = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _enterWarrantyPayment()');
    final action = source.substring(start, source.indexOf('Future<void> _showPaymentContextMenu(', start));
    expect(action, contains('WarrantyReceivedPaymentDialog('));
    expect(action, contains('if (amount == null'));
    expect(action, contains('_hasWarrantyReceipt'));
    expect(action, contains('expectedQueuedOperationIds: queuedOperationIds'));
    expect(action, isNot(contains('createManualTransaction')));
    expect(action, isNot(contains('finalizePendingInvoicePayment')));
  });
}
