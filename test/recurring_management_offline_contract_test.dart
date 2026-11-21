import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Force Offline does not call recurring server and avoids false empty', () {
    final screen = File('lib/screens/settings/expense_settings_screen.dart')
        .readAsStringSync();
    final beginning = screen.indexOf('class _RecurringTransactionsScreenState');
    final end = screen.indexOf('class _RecurringDialog', beginning);
    expect(beginning, greaterThan(0));
    expect(end, greaterThan(beginning));
    final source = screen.substring(beginning, end);
    final offline = source.indexOf(
        'if (BriskersConnectionModeController.instance.forceOffline)');
    final fetch = source.indexOf('_api.recurringTransactions(widget.businessId)');
    expect(offline, greaterThan(0));
    expect(fetch, greaterThan(offline));
    expect(source, contains('rows = saved ?? <Map<String, dynamic>>[];'));
    expect(source, contains('_offlineUnavailable = saved == null;'));
    expect(source, contains('Recurring transactions unavailable offline.'));
    expect(source, contains('networkSupabase.auth.currentUser?.id'));
    expect(source, contains('if (_canEdit)'));
  });
}
