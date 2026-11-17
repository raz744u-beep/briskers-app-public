import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/job_status_style.dart';

void main() {
  test('offline Job cards distinguish all three automatic statuses', () {
    final open = operationalJobStatusColor('open', null);
    final progress = operationalJobStatusColor('in_progress', null);
    final complete = operationalJobStatusColor('completed', null);
    expect(open, const Color(0xFFD97706));
    expect(progress, const Color(0xFF1674DB));
    expect(complete, const Color(0xFF0A8F53));
    expect({open, progress, complete}.length, 3);
    final card = File('lib/widgets/job_compact_card.dart').readAsStringSync();
    expect(card, contains('operationalJobStatusColor('));
    expect(card, contains('statusColor.withValues(alpha: 0.14)'));
  });
}
