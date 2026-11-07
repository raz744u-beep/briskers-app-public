import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/screens/payroll/owner_payroll_screen.dart')
      .readAsStringSync();

  test('Owner navigation and local refresh never use a payment unlock', () {
    // Opening a task form, returning from the weekly review, changing
    // employees and refreshing after General Tasks must not call _run.
    expect(source, isNot(contains('_run(() async {})')));
    expect(source, contains('if (!mounted || !_canView) return;'));
    expect(source, contains('if (mounted && _canView) await _load();'));
    expect(source, contains('if (_canView) unawaited(_load());'));
  });

  test('payment, repayments and opening advances still require owner proof', () {
    final weeklyStart = source.indexOf('Future<void> _recordWeekly(');
    final weeklyEnd = source.indexOf('String _operationId()', weeklyStart);
    expect(weeklyStart, greaterThanOrEqualTo(0));
    expect(weeklyEnd, greaterThan(weeklyStart));
    expect(source.substring(weeklyStart, weeklyEnd),
        contains('verifyPayment: true, rethrowError: true'));

    final ledgerStart = source.indexOf(
        'Future<LocalPayrollRepository> _localPaymentLedger(');
    final ledgerEnd = source.indexOf('Future<void> _saveOpening()', ledgerStart);
    expect(ledgerStart, greaterThanOrEqualTo(0));
    expect(ledgerEnd, greaterThan(ledgerStart));
    final ledger = source.substring(ledgerStart, ledgerEnd);
    expect(ledger, contains('_assertOwner();'));
    expect(ledger, contains('assertOwnerGrant: _assertOwner'));

    for (final startMarker in [
      'Future<void> _saveOpening()',
      'Future<void> _saveRepayment()',
    ]) {
      final start = source.indexOf(startMarker);
      expect(start, greaterThanOrEqualTo(0));
      final next = source.indexOf('\n  }', start);
      expect(source.substring(start, next), contains('verifyPayment: true'));
    }
  });
}
