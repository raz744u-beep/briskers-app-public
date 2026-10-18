import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/employee_role_style.dart';

void main() {
  test('offline employee Settings reads the saved position_name and uses the same role icon', () {
    final source = File('lib/screens/settings/employees_settings_screen.dart')
        .readAsStringSync();
    expect(source, contains("(employee['position'] ?? employee['position_name'])"));
    expect(source, contains('employeeRoleStyle(position)'));
    expect(source, contains('roleStyle.color.withValues'));
    expect(source, contains('roleStyle.icon'));
    expect(source, contains('trailing: _showingSaved ? null'));
    expect(source, contains("if (!_showingSaved)"));
    expect(source, contains("floatingActionButton: _offlineUnavailable || _showingSaved"));
    expect(source, isNot(contains("' • Offline roster'")));
  });

  test('role-specific icons and colors are identical for offline role names', () {
    const rows = <String, IconData>{
      'Porter': Icons.local_shipping_outlined,
      'Mechanic': Icons.build_outlined,
      'Owner': Icons.workspace_premium_outlined,
      'Secretary': Icons.support_agent_outlined,
    };
    for (final entry in rows.entries) {
      final actual = employeeRoleStyle(entry.key);
      expect(actual.icon, entry.value);
      expect(actual.color, isNot(const Color(0xFF64748B)));
    }
  });
}
