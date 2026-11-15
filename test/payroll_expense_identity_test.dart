import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/payroll_expense_identity.dart';

void main() {
  test('stable identity is distinct across businesses and operations', () {
    final first = PayrollExpenseIdentity.transactionId('shop', 'pay-1');
    expect(first, PayrollExpenseIdentity.transactionId('shop', 'pay-1'));
    expect(first, isNot(PayrollExpenseIdentity.transactionId('shop', 'pay-2')));
    expect(first, isNot(PayrollExpenseIdentity.transactionId('other', 'pay-1')));
    expect(PayrollExpenseIdentity.transactionId('a:b', 'c'),
        isNot(PayrollExpenseIdentity.transactionId('a', 'b:c')));
  });

  test('verified payroll expense uses net sent, not gross wages', () {
    final payment = {
      'operation_id': 'verified-1', 'verified_date': '2026-11-13',
      'gross': 70000, 'repayment': 5000, 'net': 65000,
    };
    expect(PayrollExpenseIdentity.verifiedNetCents(payment), 65000);
  });

  test('rejects draft, incomplete, or inconsistent payments', () {
    final valid = {
      'operation_id': 'verified-1', 'verified_date': '2026-11-13',
      'gross': 70000, 'repayment': 5000, 'net': 65000,
    };
    for (final invalid in [
      {...valid, 'operation_id': ''},
      {...valid, 'verified_date': ''},
      {...valid, 'net': 70000},
      {...valid, 'net': -1},
      {...valid}..remove('verified_date'),
    ]) {
      expect(() => PayrollExpenseIdentity.verifiedNetCents(invalid),
          throwsStateError);
    }
  });
}
