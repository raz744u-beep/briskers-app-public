import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/core/employee_role_style.dart';

void main() {
  test('Jobs quick assignment uses the same position-based icons as Employees',
      () {
    final source = File('lib/screens/jobs_screen.dart').readAsStringSync();
    final start = source.indexOf(
        'Future<void> _quickEditMechanic(Map<String, dynamic> job) async');
    final end = source.indexOf(
        'Future<void> _quickEditPlannedTime(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final picker = source.substring(start, end);

    expect(source, contains("import '../core/employee_role_style.dart';"));
    expect(picker, contains('employeeRoleStyle(position)'));
    expect(picker, contains('roleStyle.icon'));
    expect(picker, contains('roleStyle.color.withValues(alpha: 0.14)'));
    expect(picker, contains('fontWeight: FontWeight.w600'));
    expect(picker, contains('queueAssignment('));
    expect(picker, contains('cachedEmployees('));
    expect(picker, contains('refreshEmployees('));
    expect(picker, contains("'Unassigned'"));
    expect(picker, isNot(contains('leading: const Icon(Icons.person_outline)')));
  });

  test('Porter Mechanic Owner Secretary keep recognizable shared icon styles',
      () {
    expect(employeeRoleStyle('Porter').icon, Icons.local_shipping_outlined);
    expect(employeeRoleStyle('Mechanic').icon, Icons.build_outlined);
    expect(employeeRoleStyle('Owner').icon, Icons.workspace_premium_outlined);
    expect(employeeRoleStyle('Secretary').icon, Icons.support_agent_outlined);
    for (final role in ['Porter', 'Mechanic', 'Owner', 'Secretary']) {
      expect(employeeRoleStyle(role).color, isNot(const Color(0xFF64748B)));
    }
  });
}
