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

  test('projection preserves verified net, method, date and operation', () {
    final payment = {
      'operation_id': 'paid-7', 'verified_date': '2026-11-13',
      'gross': 80000, 'repayment': 15000, 'net': 65000,
      'method': 'Zelle',
    };
    final row = PayrollExpenseIdentity.expenseProjection(
      businessId: 'shop', payment: payment, employeeName: 'Chris',
      accountId: 'saved-checking', categoryId: 'saved-payroll');
    expect(row['id'], PayrollExpenseIdentity.transactionId('shop', 'paid-7'));
    expect(row['payroll_operation_id'], 'paid-7');
    expect(row['amount'], 650.0);
    expect(row['signed_amount'], -650.0);
    expect(row['transaction_date'], '2026-11-13');
    expect(row['payment_method'], 'Zelle');
    expect(row['account_id'], 'saved-checking');
    expect(row['category_id'], 'saved-payroll');
    expect(PayrollExpenseIdentity.classify(
      businessId: 'shop', payment: payment, existingExpenses: [row]),
      PayrollExpenseDecision.alreadyLinked);
  });

  test('zero-net settlement cannot produce a cash expense', () {
    final payment = {
      'operation_id': 'paid-zero', 'verified_date': '2026-11-13',
      'gross': 10000, 'repayment': 10000, 'net': 0,
    };
    expect(() => PayrollExpenseIdentity.expenseProjection(
      businessId: 'shop', payment: payment, employeeName: 'Chris',
      accountId: 'saved-checking', categoryId: 'saved-payroll'),
      throwsStateError);
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
