import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flexible-weekly employees get navigation, not a dead verify action', () {
    final weekly = File('lib/tasks_lab/weekly_labor_review_screen.dart')
        .readAsStringSync();
    expect(weekly, contains('Open Flexible Payroll'));
    expect(weekly, contains('DefaultTabController.of(context).animateTo(1)'));
    expect(weekly, contains('widget.rateCents == null ||'));
    expect(weekly, contains('widget.rateCents! <= 0 ? null : _verifyPayment'));
  });

  test('flexible pay remains a locally stored preview, not an implicit payout', () {
    final profile = File('lib/tasks_lab/employee_payroll_profile.dart')
        .readAsStringSync();
    expect(profile, contains('lab_flexible_weekly_defaults'));
    expect(profile, contains('Save weekly defaults · TEST'));
    expect(profile, contains('Settings only; does not verify payment.'));
    expect(profile, contains('_approvedSupplementHours'));
  });
}
