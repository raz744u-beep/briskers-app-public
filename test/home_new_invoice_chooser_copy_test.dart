import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Home New Invoice chooser displays agreed wording, not Blank', () async {
    final source = await File('lib/screens/home_screen.dart').readAsString();

    expect(source, contains("title: const Text('New Invoice')"));
    expect(
      source,
      contains('Use an existing Job or create a new invoice for a customer.'),
    );
    expect(
      source,
      contains('Start a new invoice and choose a customer.'),
    );
    expect(source, isNot(contains("title: const Text('New Blank Invoice')")));
    expect(
      source,
      isNot(contains('create a blank invoice for a customer.')),
    );
    expect(
      source,
      isNot(contains('Start a blank invoice and choose a customer.')),
    );
  });
}
