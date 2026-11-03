import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Invoice and Estimate cards restore leading document imagery', () {
    final src = File('lib/screens/documents_screen.dart').readAsStringSync();
    final card = src.substring(src.indexOf('Widget _documentCard('));
    expect(card, contains('CircleAvatar('));
    expect(card, contains('Icons.request_quote_outlined'));
    expect(card, contains('Icons.receipt_long_outlined'));
    expect(card, contains('color.withValues(alpha: 0.13)'));
    expect(card, contains('displayNumber'));
  });
}
