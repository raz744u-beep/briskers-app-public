import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Expenses body stays visible instead of a full-screen loading spinner',
      () {
    final src = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(src, contains('body: RefreshIndicator('));
    expect(src, isNot(contains('body: _loading\n          ? const Center(child: CircularProgressIndicator())')));
    expect(src, contains('if (_loading && visible.isEmpty)'));
    expect(src, contains('Opening saved transactions on this device'));
    expect(src, contains('No transactions in this view.'));
  });
}
