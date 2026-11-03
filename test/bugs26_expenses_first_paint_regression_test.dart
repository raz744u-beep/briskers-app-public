import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Expenses paints durable transaction rows before metadata/options',
      () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    final paint = source.indexOf('_transactions = localRows;');
    final options = source.indexOf(
      'final localOptions = await _localFinancial.loadOptions(',
    );
    expect(paint, greaterThan(0));
    expect(options, greaterThan(paint));
    expect(source, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(source, contains('if (_isCurrentLoad(epoch, businessId) && localRows.isNotEmpty)'));
  });

  test('Expenses first paint retains existing ledger and receipt safeguards',
      () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(source, contains('_invoiceReceipts ='));
    expect(source, contains('WarrantyReceiptReporting.unverified'));
    expect(source, contains('_showingLocal = true'));
    expect(source, contains('_transactionRefreshFailed'));
  });
}
