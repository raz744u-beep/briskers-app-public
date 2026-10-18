import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee cache identity is obtained locally, not through network guard',
      () async {
    final source = await File('lib/services/employee_roster_cache.dart')
        .readAsString();
    expect(source, contains('supabase.auth.currentUser?.id'));
    expect(source, isNot(contains('networkSupabase.auth.currentUser')));
    final readStart = source.indexOf('Future<EmployeeRosterSnapshot?> _read(');
    final readEnd = source.indexOf('Future<EmployeeRosterSnapshot?> cachedSettings(', readStart);
    expect(readStart, greaterThanOrEqualTo(0));
    expect(readEnd, greaterThan(readStart));
    final read = source.substring(readStart, readEnd);
    expect(read.indexOf('try {'), lessThan(read.indexOf('_key(businessId, scope)')));
    expect(read, contains('return null;'));
  });

  test('Employees screen must not spin forever on unavailable cache', () async {
    final source = await File('lib/screens/settings/employees_settings_screen.dart')
        .readAsString();
    final load = source.substring(
      source.indexOf('Future<void> _load() async'),
      source.indexOf('String _pay(', source.indexOf('Future<void> _load() async')),
    );
    expect(load, contains('EmployeeRosterSnapshot? fullCached;'));
    expect(load, contains("timeout(const Duration(seconds: 5))"));
    expect(load, contains('_employees ??= const [];'));
    expect(load, contains('_offlineUnavailable = cached == null;'));
    expect(load, contains('BriskersConnectionModeController.instance.forceOffline'));
  });
}
