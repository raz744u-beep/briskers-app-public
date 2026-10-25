import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/test_payroll_adjustment_policy.dart';

void main() {
  test('bonus requires positive amount, reason and approver', () {
    TestPayrollAdjustmentPolicy.validate(
      kind: TestPayrollAdjustmentKind.bonus,
      signedCents: 1500, reason: 'Extra work', approvedBy: 'owner');
    expect(() => TestPayrollAdjustmentPolicy.validate(
      kind: TestPayrollAdjustmentKind.bonus,
      signedCents: -1500, reason: 'Oops', approvedBy: 'owner'),
      throwsArgumentError);
  });
  test('correction supports signed amounts with audit reason', () {
    TestPayrollAdjustmentPolicy.validate(
      kind: TestPayrollAdjustmentKind.correction,
      signedCents: -200, reason: 'Reversal', approvedBy: 'owner');
    expect(() => TestPayrollAdjustmentPolicy.validate(
      kind: TestPayrollAdjustmentKind.correction,
      signedCents: -200, reason: '', approvedBy: 'owner'),
      throwsStateError);
  });
}
