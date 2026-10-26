import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Owner expense financial summary reserves height across async status', () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    final status = source.indexOf('if (_showFinancialSummary)\n                    SizedBox(');
    expect(status, greaterThan(0));
    final recurring = source.indexOf('if (_allowRecurring)', status);
    expect(recurring, greaterThan(status));
    final block = source.substring(status, recurring);
    expect(block, contains('height: 54'));
    expect(block, contains('maxLines: 3'));
    expect(block, contains('TextOverflow.ellipsis'));
    expect(block, contains('_periodError ??'));
    expect(block, contains('Posted totals for $_rangeLabel'));
    expect(source, contains('if (_showFinancialSummary)\n                    Card('),
        reason: 'Finance visibility and accounting verification remain unchanged.');
  });

  test('Expense cached thumbnails are preserved and warmed concurrently', () {
    final source = File(
      'lib/screens/expenses/expense_detail_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _cacheExpenseDetail(');
    final end = source.indexOf('Future<void> _loadLocalExpenseIqPhoto(', start);
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final cache = source.substring(start, end);
    final prefetch = cache.indexOf('unawaited(_prefetchLocalAttachments(');
    final save = cache.indexOf('await _localFinancial.saveTransactionDetail(');
    expect(prefetch, greaterThan(0));
    expect(save, greaterThan(prefetch),
        reason: 'Images must warm while the detail snapshot is saved.');
    expect(cache, isNot(contains('_attachmentFiles.clear')),
        reason: 'Finishing a photo download must not erase active thumbnail futures.');
    expect(source, contains('future: _localAttachment(attachment)'));
    expect(source, contains('if (localSnapshot.connectionState != ConnectionState.done)'));
    expect(source, contains('if (BriskersConnectionModeController.instance.forceOffline)'));
    expect(source, contains('if (local != null)'));
    expect(source, contains('_attachmentUrl(attachment)'),
        reason: 'Uncached receipts retain the normal authenticated cloud fallback.');
  });
}
