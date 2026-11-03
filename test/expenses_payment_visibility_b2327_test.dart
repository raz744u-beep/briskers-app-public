import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Payment receipts are requested before slow financial history hydration', () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    final methodStart = source.indexOf('Future<void> _load({');
    final methodEnd = source.indexOf('Future<void> _hydrateFinancialHistory(', methodStart);
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));
    final load = source.substring(methodStart, methodEnd);
    expect(load, contains('unawaited(_refreshInvoiceReceipts(businessId))'));
    expect(load, contains('offset: 0, fastFirstPaint: true'));
    expect(load, contains('unawaited(_hydrateFinancialHistory(epoch, businessId, rows));'));
    expect(load.indexOf('unawaited(_refreshInvoiceReceipts(businessId))'),
        lessThan(load.indexOf('offset: 0, fastFirstPaint: true')));
    expect(load.indexOf('setState(() {\n        _transactions = rows;'),
        lessThan(load.indexOf('unawaited(_hydrateFinancialHistory(')));
    expect(load, isNot(contains('await _api.transactions(businessId, limit: 1000)')));
    expect(load, contains('_loading = _transactions.isEmpty && _invoiceReceipts.isEmpty'));
    expect(load, contains('InvoicePaymentFeed.mergeReceipts(_invoiceReceipts, receipts)'));

  });

  test('Searching history does not cancel in-flight payment receipt refresh', () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _refreshInvoiceReceipts(String businessId)');
    final end = source.indexOf('Future<void> _openInvoiceReceipt(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final refresh = source.substring(start, end);
    expect(refresh, contains('final epoch = ++_receiptEpoch'));
    expect(refresh, contains('_isCurrentReceipt(epoch, businessId)'));
    expect(refresh, isNot(contains('_isCurrentLoad(epoch, businessId)')));
    expect(refresh, contains('if (_invoiceReceipts.isNotEmpty) _loading = false'));
    // No synthetic paid receipt or income transaction may be invented.
    expect(refresh, contains('InvoicePaymentFeed.reconcileOnlineFirstPage('));
    expect(refresh, contains('await _invoiceFeed.saveServerReceipts(businessId, rows)'));
  });

  test('Invoice expense amounts visually match main transaction amounts', () {
    final main = File('lib/screens/expenses_screen.dart').readAsStringSync();
    final invoice = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final mainStart = main.indexOf("'\${incomeRow ? '+' : '-'}\${_money(");
    expect(mainStart, greaterThanOrEqualTo(0));
    final mainAmountStyle = main.substring(mainStart, mainStart+330);
    expect(mainAmountStyle, contains('fontSize: 17.5'));
    expect(mainAmountStyle, contains('fontWeight: FontWeight.w900'));
    final invoiceStart = invoice.indexOf('// Match the main Expenses & Income card amount style.');
    expect(invoiceStart, greaterThanOrEqualTo(0));
    final invoiceAmountStyle = invoice.substring(invoiceStart, invoiceStart+500);
    expect(invoiceAmountStyle, contains('fontSize: 17.5'));
    expect(invoiceAmountStyle, contains('fontWeight: FontWeight.w900'));
    expect(invoiceAmountStyle, contains('color: color'));
    expect(invoiceAmountStyle, contains('maxLines: 1'));
  });
}
