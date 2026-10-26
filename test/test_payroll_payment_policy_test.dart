import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/test_payroll_payment_policy.dart';

void main() {
  test('check payments require proof', () {
    expect(() => TestPayrollPaymentPolicy.validate(
      cents: 10000, method: 'check', kind: 'pay'), throwsStateError);
    TestPayrollPaymentPolicy.validate(cents: 10000, method: 'check',
      kind: 'pay', checkProofReference: 'test-image-1');
  });
  test('ACH and Zelle accepted separately', () {
    for (final method in ['ach', 'zelle']) {
      TestPayrollPaymentPolicy.validate(
        cents: 100, method: method, kind: 'advance');
    }
  });
  test('manual payroll amount override requires a reason', () {
    expect(() => TestPayrollPaymentPolicy.validate(
      cents: 12000, method: 'cash', kind: 'pay', amountOverridden: true),
      throwsStateError);
    TestPayrollPaymentPolicy.validate(cents: 12000, method: 'cash',
      kind: 'pay', amountOverridden: true, overrideReason: 'Approved bonus');
  });
  test('invalid amounts cannot post', () {
    expect(() => TestPayrollPaymentPolicy.validate(
      cents: 0, method: 'cash', kind: 'pay'), throwsArgumentError);
  });
}
