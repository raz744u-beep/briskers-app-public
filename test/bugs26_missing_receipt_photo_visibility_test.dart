import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Missing local receipts are not mistaken for nonexistent pictures', () {
    final src = File('lib/screens/expenses/expense_detail_screen.dart')
        .readAsStringSync();
    expect(src, contains("widget.cachedDetail?['receipt_count']"));
    expect(src, contains('receiptReferenceCount > 0'));
    expect(src, contains('the images are not available in this'));
    expect(src, contains('does not prove'));
    expect(src, contains("const Text('No receipt photos attached.')"));
    expect(src, contains('_localExpenseIqPhoto == null'));
    expect(src, contains('ExpenseIqLocalPhotoSync'));
  });
}
