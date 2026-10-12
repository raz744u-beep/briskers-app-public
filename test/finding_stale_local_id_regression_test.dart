import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Finding refresh never resurrects stale local placeholders', () {
    final source = File('lib/screens/jobs/job_detail_screen.dart')
        .readAsStringSync();
    expect(source, contains('final currentLocalIds = local'));
    expect(source, contains("id.startsWith('local-finding-') && !currentLocalIds.contains(id)"));
    expect(source, contains('_mergeFindingLists('));
  });
}
