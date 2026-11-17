import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/job_status_style.dart';

void main() {
  test('Open, In Progress and Complete get distinct stable colors', () {
    final open = operationalJobStatusColor('open', null);
    final progress = operationalJobStatusColor('in_progress', null);
    final completed = operationalJobStatusColor('completed', null);
    expect(open, const Color(0xFFD97706));
    expect(progress, const Color(0xFF1674DB));
    expect(completed, const Color(0xFF0A8F53));
    expect({open, progress, completed}.length, 3);
    expect(operationalJobStatusColor('complete', null), completed);
    expect(operationalJobStatusColor('in progress', null), progress);
  });

  test('Legacy Job statuses retain their configured colors', () {
    expect(
      operationalJobStatusColor('awaiting_parts', '#123456'),
      const Color(0xFF123456),
    );
    expect(
      operationalJobStatusColor('unknown', null),
      const Color(0xFF546E7A),
    );
  });

  test('Jobs list and Job Detail both use shared operational color', () {
    final card = File('lib/widgets/job_compact_card.dart').readAsStringSync();
    final detail = File('lib/screens/jobs/job_detail_screen.dart')
        .readAsStringSync();
    expect(card, contains('final statusColor = operationalJobStatusColor('));
    expect(detail, contains('final color = operationalJobStatusColor('));
    expect(detail, contains('final statusColor = operationalJobStatusColor('));
  });
}
