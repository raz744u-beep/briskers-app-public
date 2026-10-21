import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Expenses cached-first Auto does not show a false offline banner', () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(source, contains('bool _transactionRefreshFailed = false;'));
    expect(source, contains('_transactionRefreshFailed = !forceOffline;'));
    expect(source, contains('.instance.forceOffline ||'));
    expect(source, contains('_transactionRefreshFailed))'));
    expect(source, contains('Offline mode • showing saved transactions'));
    expect(source,
        contains('Unable to refresh transactions • showing saved data'));
    expect(source, contains('No tall banner in Auto: preserve list position.'));
    expect(source, contains('Tooltip('));
    expect(source,
        isNot(contains('Showing saved transactions • reconnect to refresh, add or edit')));
    // A successful server page, and a fresh attempt, must clear stale warning.
    expect(source, contains('_transactionRefreshFailed = false;'));
    // The read-only server confirmation logic remains intact.
    expect(source, contains('_previousServerTransactionProofs'));
    expect(source, contains('saveServerConfirmedTransactions('));
  });

  test('Appointments without bootstrap show unresolved status, never Total 0', () {
    final source = File('lib/screens/appointments_screen.dart').readAsStringSync();
    expect(source, contains('final total = _appointments?.length;'));
    expect(source, contains("'${tr('total')} ${total ?? '—'}'"));
    expect(source, contains("ValueKey('appointment-awaiting-server')"));
    expect(source,
        contains('Checking appointments in the background. No saved list is available yet.'));
    expect(source, contains('No saved appointments are available offline.'));
    expect(source,
        contains('Could not refresh appointments. Pull down to retry.'));
    expect(source,
        isNot(contains('if (_appointments == null)\n                  const Center(')));
    // Sync and local first-paint still run: hiding a spinner is not a sync fix.
    expect(source, contains('await _appointmentSync.flush(businessId)'));
    expect(source, contains('final localAvailable = !forceOnline && await _loadLocal();'));
  });
}
