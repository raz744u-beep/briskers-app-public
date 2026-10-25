import 'dart:io';

import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Create estimate/invoice is above dock, not beside Search', () {
    final src = File('lib/screens/documents_screen.dart').readAsStringSync();
    expect(src, contains("tooltip: _estimate ? 'New Estimate' : 'New Invoice'"));
    expect(src, contains("key: const ValueKey('persistent-document-search')"));
    expect(src, contains('floatingActionButton:'));
    expect(src, contains('FloatingActionButton.extended('));
    expect(src, contains('shape: RoundedRectangleBorder('));
    expect(src, contains("label: const Text('New'"));
    expect(src, isNot(contains('IconButton.filled(\n                    tooltip: _estimate')));
    expect(src, contains('bottomNavigationBar: widget.customerId != null &&'));
  });

  test('Ordinary Customers dock is immediate, new badge selects review inbox', () {
    final shell = File('lib/screens/shell_screen.dart').readAsStringSync();
    final dock = File('lib/widgets/briskers_module_dock.dart')
        .readAsStringSync();
    final retained = File('lib/widgets/retained_module_stack.dart')
        .readAsStringSync();
    final goTo = shell.substring(shell.indexOf('void _goTo(int index)'),
        shell.indexOf('String get _roleLabel'));
    expect(goTo, contains('if (index == 1) {'));
    expect(goTo, contains('_focusedCustomerIds = null;'));
    expect(goTo, contains('_customersRefreshToken++;'));
    expect(goTo, isNot(contains('unawaited(_openCustomers(request))')));
    expect(shell, contains('onBadgeSelected: (index)'));
    expect(shell, contains('unawaited(_openCustomers(request))'));
    expect(dock, contains('widget.onBadgeSelected!(index)'));
    expect(retained, contains('retainedIndices = const {1, 2, 3, 4, 5, 6}'));
  });

  test('Expense proof signatures include identity amount date and direction', () {
    final row = <String, dynamic>{
      'id': 'worldpac-1',
      'amount': 145.91,
      'direction': 'expense',
      'transaction_date': '2026-10-20',
    };
    final proof = LocalFinancialCache.serverTransactionSignature(row);
    expect(LocalFinancialCache.serverTransactionSignature({...row}), proof);
    expect(LocalFinancialCache.serverTransactionSignature(
        {...row, 'amount': 145.92}), isNot(proof));
    expect(LocalFinancialCache.serverTransactionSignature(
        {...row, 'direction': 'income'}), isNot(proof));
    expect(LocalFinancialCache.serverTransactionSignature(
        {...row, 'transaction_date': '2026-10-21'}), isNot(proof));
    expect(LocalFinancialCache.serverTransactionSignature(
        {...row, 'id': 'worldpac-2'}), isNot(proof));
  });

  test('Expense cloud proofs must be server-returned and expire by business', () {
    final src = File('lib/screens/expenses_screen.dart').readAsStringSync();
    final cache = File('lib/services/local_financial_cache.dart')
        .readAsStringSync();
    expect(cache, contains("Duration(days: 7)"));
    expect(cache, contains("serverRows"));
    expect(cache, contains("_serverTransactionProofKey"));
    expect(cache, contains("now - stamp > _proofTtl.inMilliseconds"));
    expect(cache, contains("'pending_sync'"));
    expect(cache, contains("'conflict'"));
    expect(src, contains('loadServerConfirmedTransactions('));
    expect(src, contains('saveServerConfirmedTransactions('));
    expect(src, contains('serverTransactionSignature('));
    expect(src, contains('currentConfirmed ||'));
    expect(src, contains('previouslyConfirmed'));
    expect(src, contains('!pending && !failed'));
    expect(src, contains('Previously confirmed on server; refresh to recheck'));
    expect(src, contains('_previousServerTransactionProofs = {};'));
  });
}
