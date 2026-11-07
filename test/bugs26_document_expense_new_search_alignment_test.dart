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

  test('Expenses New floats lower-right while Search uses its own row', () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(source, contains("ValueKey('expenses-new-floating')"));
    expect(source, contains('onPressed: _importing ? null : _showAddMenu'));
    expect(source, contains('backgroundColor: BriskersColors.expenses'));
    expect(source, contains('FloatingActionButton.extended('));
    expect(source, contains('FloatingActionButtonLocation.endFloat'));
    expect(source, contains("hintText: 'Search transactions…'"));
    expect(source, isNot(contains("ValueKey('expenses-inline-new')")));
  });
}
