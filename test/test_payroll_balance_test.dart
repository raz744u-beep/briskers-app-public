import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/test_payroll_balance.dart';

void main() {
  test('bonus increases and negative correction decreases amount owed', () {
    expect(TestPayrollBalance.remainingCents(
      earnedCents: 40000, adjustmentCents: 1500, paidCents: 20000), 21500);
    expect(TestPayrollBalance.remainingCents(
      earnedCents: 40000, adjustmentCents: -2000, paidCents: 20000), 18000);
  });
  test('advance can create a credit, not extra earned task hours', () {
    expect(TestPayrollBalance.remainingCents(
      earnedCents: 10000, adjustmentCents: 0, paidCents: 15000), -5000);
  });
  test('invalid cash and earned totals fail closed', () {
    expect(() => TestPayrollBalance.remainingCents(
      earnedCents: -1, adjustmentCents: 0, paidCents: 0), throwsArgumentError);
  });
}
