import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expense and income share safe local receipt selections', () {
    final source = File('lib/screens/expenses/expense_entry_screen.dart')
        .readAsStringSync();
    expect(source, contains('child: ExpenseReceiptAttachments('));
    expect(source, contains('enabled: !_saving && !_readingReceipt'));
    expect(source, isNot(contains('item.path != file.path')));
    expect(source, contains("widget.initialDirection == 'income'"));

    // Keep the selected photos on the existing online/offline save paths.
    expect(source, contains('for (final receipt in _receipts)'));
    expect(source, contains("'bytes': await receipt.readAsBytes()"));
    expect(source, contains('receipts: stagedReceipts'));
    expect(RegExp('receipts: stagedReceipts').allMatches(source), hasLength(2));
    expect(source, contains('await _api.uploadExpensePhoto('));
    expect(source, contains('bytes: await receipt.readAsBytes()'));
  });

  test('receipt selection has no persisted deletion or role permission effects', () {
    final source = File('lib/screens/expenses/expense_receipt_attachments.dart')
        .readAsStringSync();
    expect(source, contains('identical(item, selected)'));
    expect(source, contains('..removeAt(index)'));
    expect(source, isNot(contains('deleteExpensePhoto')));
    expect(source, isNot(contains('BriskersApi')));
    expect(source, isNot(contains('OfflineFinancialWriteService')));
    expect(source, isNot(contains('.delete(')));
    expect(source, isNot(contains('file.name')));
    expect(source, isNot(contains('file.path')));
  });

  test('transaction date stays beneath a bold high-contrast translated label', () {
    final source = File('lib/screens/expenses/expense_entry_screen.dart')
        .readAsStringSync();
    final start = source.indexOf("tr('transactionDate')");
    final end = source.indexOf('onTap: _saving ? null : _pickDate', start);
    final dateTile = source.substring(start, end);
    expect(dateTile, contains('fontWeight: FontWeight.w800'));
    expect(dateTile, contains('colorScheme.onSurface'));
    expect(dateTile, contains('subtitle: Text('));
    expect(source, contains('backgroundColor: BriskersColors.expenses'));
  });
}
