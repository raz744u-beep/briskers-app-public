import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Invoice Expenses tab exposes saved receipt picture metadata', () {
    final screen = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final start = screen.indexOf('Widget _invoiceExpensesTab()');
    final end = screen.indexOf('Future<void> _showInvoiceExpenses()', start);
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final tab = screen.substring(start, end);
    expect(tab, contains("item['receipt_count']"));
    expect(tab, contains("item['attachments']"));
    expect(tab, contains('if (receiptCount > 0)'));
    expect(tab, contains('Icons.photo_outlined'));
    expect(tab, contains('ExpenseDetailScreen('));
    expect(tab, contains('cachedDetail: Map<String, dynamic>.from(item)'));
  });
}
