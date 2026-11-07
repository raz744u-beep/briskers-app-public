import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved Owner Payroll viewing never requires a Supabase request', () {
    final auth = File('lib/services/device_owner_authorization.dart')
        .readAsStringSync();
    final viewStart = auth.indexOf(
        'Future<bool> canViewSavedOwnerPayroll(');
    final next = auth.indexOf('Future<VerifiedOwnerEnrollment> _verifyLocalOwner(',
        viewStart);
    expect(viewStart, greaterThanOrEqualTo(0));
    expect(next, greaterThan(viewStart));
    final view = auth.substring(viewStart, next);
    expect(view, contains('await _verifyLocalOwner(business)'));
    expect(view, isNot(contains('networkSupabase')));
    expect(view, isNot(contains('authenticateDevice')));

    final localStart = next;
    final remoteStart = auth.indexOf(
        'Future<VerifiedOwnerEnrollment> _verifyOwner(', localStart);
    expect(remoteStart, greaterThan(localStart));
    final local = auth.substring(localStart, remoteStart);
    expect(local, contains('SharedPreferences.getInstance()'));
    expect(local, contains("data['role_code'] != 'owner'"));
    expect(local, contains('currentIdentity()'));
    expect(local, isNot(contains('networkSupabase')));
    expect(local, isNot(contains('authenticateDevice')));
  });

  test('real payment authorization remains distinct from offline Owner view', () {
    final auth = File('lib/services/device_owner_authorization.dart')
        .readAsStringSync();
    final payroll = File('lib/screens/payroll/owner_payroll_screen.dart')
        .readAsStringSync();
    expect(auth, contains('authorizeLocal'));
    expect(auth, contains('authenticateDevice: () async {'));
    expect(payroll, contains('verifyPayment: true, rethrowError: true'));
    expect(payroll, contains('assertOwnerGrant: _assertOwner'));
  });
}
