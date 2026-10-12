import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Manual expense photos never invoke OCR by default', () {
    final source = File('lib/screens/expenses/expense_entry_screen.dart')
        .readAsStringSync();
    expect(source, contains('_addReceipts({bool scanWithAi = false})'));
    expect(source, contains('_takeReceiptPhoto({bool scanWithAi = false})'));
    expect(source, contains('if (scanWithAi) await _readReceipt(file)'));
    expect(source, contains('if (scanWithAi) await _readReceipt(files.first)'));
    expect(source, contains("'Attach photo'"));
    expect(source, contains("'Scan with AI'"));
    expect(source, contains('_takeReceiptPhoto(scanWithAi: true)'));
  });

  test('Manual unlinked expense always receives balanced allocation', () {
    final sql = File('tools/migrations/manual_expense_always_allocated_20261012.sql')
        .readAsStringSync();
    expect(sql, contains("supplier_expense"));
    expect(sql, contains("other_expense"));
    expect(sql, contains("supplier_refund"));
  });
}
