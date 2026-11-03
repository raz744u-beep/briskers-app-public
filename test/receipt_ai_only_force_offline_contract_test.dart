import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI parse is the only authorized Supabase call in Force Offline', () {
    final api = File('lib/services/briskers_api.dart').readAsStringSync();
    final start = api.indexOf('Future<Map<String, dynamic>> parseReceiptImage(');
    final end = api.indexOf('Future<Map<String, dynamic>> applyExpenseReceiptExtraction(',start);
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final parsing = api.substring(start, end);
    expect(parsing, contains("await supabase.functions.invoke("));
    expect(parsing, contains("'receipt-parse'"));
    expect(parsing, isNot(contains('networkSupabase.functions.invoke(')));
    expect(parsing, isNot(contains('.rpc(')));
    expect(parsing, isNot(contains('flush(')));
    final remainder = api.substring(end);
    expect(remainder, contains('networkSupabase.rpc('));

    final connection = File('lib/core/supabase_config.dart').readAsStringSync();
    expect(connection, contains('ensureNetworkAllowed()'));
  });

  test('receipt scanning in Force Offline does not unblock sync or direct save', () {
    final source = File('lib/screens/expenses/expense_entry_screen.dart')
        .readAsStringSync();
    final start = source.indexOf('Future<void> _readReceipt(');
    final end = source.indexOf('void _applyQuickTemplate(', start);
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final reader = source.substring(start, end);
    expect(reader, contains('await _api.parseReceiptImage('));
    expect(reader, isNot(contains('if (BriskersConnectionModeController.instance.forceOffline)')));
    expect(source, contains("if (forceOffline) {"));
    expect(source, contains('if (widget.autoScanReceipt'));
    expect(source, contains('_takeReceiptPhoto(scanWithAi: true)'));
    expect(source, contains('receiptExtraction: _receiptExtraction == null ? null : {'));
    expect(source, contains("'review_confirmed': true"));
    expect(source, contains('_offlineFinancial.createLocalTransaction('));
    expect(source, contains('_offlineFinancial.updateLocalTransaction('));
    expect(source, contains(
        'if (!BriskersConnectionModeController.instance.forceOffline) {'));
    expect(source, isNot(contains('BriskersConnectionMode.offline = false')));
  });

  test('receipt sync queue remains a distinct deferred operation', () {
    final writer = File('lib/services/offline_financial_write_service.dart')
        .readAsStringSync();
    expect(writer, contains('financial_receipt_extraction'));
    expect(writer, contains('receipt_items'));
    expect(writer, contains('receipt_details'));
    expect(writer, contains('receiptExtraction'));
    expect(writer, contains("'review_confirmed'"));
    expect(writer, contains('LocalJobQuarantine.guardReplay'));
  });
}
