import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline Job cards distinguish all three automatic statuses', () {
    final source = File('lib/widgets/job_compact_card.dart').readAsStringSync();
    expect(source, contains("'open' => const Color(0xFF2864A5)"));
    expect(source, contains("'in_progress' || 'in progress' => const Color(0xFFB66D13)"));
    expect(source, contains("'complete' || 'completed' => const Color(0xFF26844D)"));
    expect(source, contains("statusColor.withValues(alpha: 0.14)"));
  });
}
