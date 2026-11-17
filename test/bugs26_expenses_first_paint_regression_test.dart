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
    final firstPaintGuard = RegExp(
      r'if\s*\(_isCurrentLoad\(epoch, businessId\)\s*&&\s*'
      r'\(localRows\.isNotEmpty\s*\|\|\s*'
      r'BriskersConnectionModeController\.instance\.forceOffline\)\)',
    );
    expect(firstPaintGuard.hasMatch(source.substring(0, paint)), isTrue);
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
