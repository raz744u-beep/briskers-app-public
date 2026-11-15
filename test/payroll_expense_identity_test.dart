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

  test('financial option resolution requires exactly one saved ID', () {
    final accounts = [
      {'id': 'real-checking-id', 'name': 'Business Checking – 9858'},
      {'id': 'another-id', 'name': 'Capital One – 8938'},
    ];
    expect(PayrollExpenseIdentity.uniqueOptionId(
      accounts, 'Business Checking – 9858'), 'real-checking-id');
    expect(PayrollExpenseIdentity.uniqueOptionId(
      accounts, 'Business Checking – 0000'), isNull);
    expect(PayrollExpenseIdentity.uniqueOptionId(
      [...accounts, accounts.first], 'Business Checking – 9858'), isNull);
    expect(PayrollExpenseIdentity.uniqueOptionId(
      [{'name': 'Payroll'}], 'Payroll'), isNull);
  });

  test('backfill only when no exact operation link exists', () {
    final payment = {
      'operation_id': 'pay-1', 'verified_date': '2026-11-13',
      'gross': 70000, 'repayment': 5000, 'net': 65000,
    };
    final expense = {
      'id': 'existing-expense', 'business_id': 'shop',
      'payroll_operation_id': 'pay-1', 'direction': 'expense',
      'amount': 650.0,
    };
    expect(PayrollExpenseIdentity.classify(
      businessId: 'shop', payment: payment, existingExpenses: []),
      PayrollExpenseDecision.create);
    expect(PayrollExpenseIdentity.classify(
      businessId: 'shop', payment: payment, existingExpenses: [expense]),
      PayrollExpenseDecision.alreadyLinked);
    expect(PayrollExpenseIdentity.classify(
      businessId: 'shop', payment: payment,
      existingExpenses: [expense, {...expense, 'id': 'duplicate'}]),
      PayrollExpenseDecision.review);
    expect(PayrollExpenseIdentity.classify(
      businessId: 'shop', payment: payment,
      existingExpenses: [{...expense, 'amount': 700.0}]),
      PayrollExpenseDecision.review);
    // A coincidental employee/date/amount match is not payment proof.
    expect(PayrollExpenseIdentity.classify(
      businessId: 'shop', payment: payment,
      existingExpenses: [{'id': 'unlinked', 'direction': 'expense',
        'amount': 650.0, 'counterparty': 'Chris'}]),
      PayrollExpenseDecision.create);
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
