import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/expenses/expense_detail_screen.dart';

void main() {
  test('Three-button Android navigation inset keeps Save above system bar', () {
    final inset = expenseEditSheetBottomInset(
      keyboardInset: 0,
      systemNavigationInset: 48,
    );
    expect(inset, 64);
    expect(expenseEditSheetHeight(
      screenHeight: 820,
      bottomInset: inset,
    ), closeTo(672.4, 0.01));
  });

  test('Keyboard gets priority over system bar without additive double inset', () {
    final inset = expenseEditSheetBottomInset(
      keyboardInset: 320,
      systemNavigationInset: 48,
    );
    expect(inset, 336);
    expect(expenseEditSheetHeight(
      screenHeight: 820,
      bottomInset: inset,
    ), 452);
  });

  test('Gesture navigation and zero-inset layouts keep breathing room', () {
    expect(expenseEditSheetBottomInset(
      keyboardInset: 0,
      systemNavigationInset: 24,
    ), 40);
    expect(expenseEditSheetBottomInset(
      keyboardInset: 0,
      systemNavigationInset: 0,
    ), 16);
  });

  test('Expense edit footer remains fixed while fields scroll', () {
    final source = File('lib/screens/expenses/expense_detail_screen.dart')
        .readAsStringSync();
    final edit = source.substring(
      source.indexOf('final saved = await showModalBottomSheet<bool>('),
      source.indexOf('amount.dispose();'),
    );
    expect(edit, contains('MediaQuery.viewPaddingOf(sheetContext).bottom'));
    expect(edit, contains('MediaQuery.viewInsetsOf(sheetContext).bottom'));
    expect(edit, contains('padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset)'));
    expect(edit, contains('height: height'));
    expect(RegExp(r'Expanded\(\s*child:\s*SingleChildScrollView\(').hasMatch(edit), isTrue);
    expect(edit, contains("label: const Text('Save changes')"));
  });
}
