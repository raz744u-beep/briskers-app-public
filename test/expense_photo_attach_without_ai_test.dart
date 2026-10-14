import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'manual expense photo paths are explicitly separate from AI scanning',
    () {
      final source = File('lib/screens/expenses/expense_entry_screen.dart')
          .readAsStringSync();
      expect(source, contains('_addReceipts({bool scanWithAi = false})'));
      expect(source, contains('_takeReceiptPhoto({bool scanWithAi = false})'));
      expect(source, contains('if (scanWithAi) await _readReceipt(file)'));
      expect(
        source,
        contains('if (scanWithAi) await _readReceipt(files.first)'),
      );
      expect(source, contains("tr('attachPhoto')"));
      expect(source, contains("tr('scanWithAi')"));
      expect(source, contains('_takeReceiptPhoto(scanWithAi: true)'));
      expect(source, contains('backgroundColor: BriskersColors.expenses'));
    },
  );
}
