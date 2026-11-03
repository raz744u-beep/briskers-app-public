import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Invoices and Estimates New is aligned beside Search', () {
    final source = File('lib/screens/documents_screen.dart').readAsStringSync();
    expect(source, contains("ValueKey('documents-inline-new')"));
    expect(source, contains("key: const ValueKey('persistent-document-search')"));
    expect(source, contains('onPressed: _estimate'));
    expect(source, contains('backgroundColor: accent'));
    expect(source, contains('borderRadius: BorderRadius.circular(14)'));
    expect(source, isNot(contains('FloatingActionButton.extended(')));
  });

  test('Expenses New stays beside Search and opens without waiting for list', () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(source, contains("ValueKey('expenses-inline-new')"));
    expect(source, contains('onPressed: _importing ? null : _showAddMenu'));
    expect(source, contains('backgroundColor: BriskersColors.expenses'));
    expect(source, contains('minimumSize: const Size(91, 52)'));
    expect(source, isNot(contains('FloatingActionButton.extended(')));
  });
}
