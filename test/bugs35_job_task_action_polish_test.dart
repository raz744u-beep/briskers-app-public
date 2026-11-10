import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Job-only task cards match status/action colors and reclaim arrow space',
      () async {
    final source = await File('lib/screens/payroll/job_scoped_tasks.dart')
        .readAsString();

    expect(source, contains("static const orange = Color(0xFFD97608)"));
    expect(source, contains("static const blue = Color(0xFF1479D8)"));
    expect(source, contains("static const green = Color(0xFF078C49)"));
    expect(source, contains('OutlinedButton.styleFrom(foregroundColor: orange'));
    expect(source, contains('FilledButton.styleFrom(backgroundColor: blue'));
    expect(source, contains('decoration: BoxDecoration(color: green'));
    expect(source, isNot(contains('Icons.chevron_right')));
    expect(source, contains('onTap: () => _toggle(key)'));
    expect(source, contains('onLongPress: () => _longPress(key, row, general)'));
  });
}
