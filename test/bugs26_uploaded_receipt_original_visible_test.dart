import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Uploaded original photo remains accessible alongside cloud reference',
      () {
    final source =
        File('lib/screens/expenses/expense_detail_screen.dart')
            .readAsStringSync();
    expect(source, contains('if (_localExpenseIqPhoto != null)'));
    expect(source, isNot(contains(
      "_localExpenseIqPhoto!['state'] != 'uploaded'",
    )));
    expect(source, contains('onTap: uri.isEmpty ? null : () => _openLocalExpenseIqPhoto(uri)'));
    expect(source, contains('snapshot.hasError'));
    expect(source, contains('Icons.image_not_supported_outlined'));
    expect(source, contains('Synced to cloud'));
  });
}
