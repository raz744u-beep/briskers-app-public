import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'local_financial_cache.dart';
import 'payroll_expense_identity.dart';

/// A read-only comparison of saved disbursements and Expenses. Similar rows
/// are evidence for review only, never an instruction to post or link money.
class LocalPayrollExpenseReview {
  const LocalPayrollExpenseReview(this.database);
  final BriskersLocalDatabase database;

  Future<List<Map<String, dynamic>>> forWeek(
    String business,
    String week, {
    String? employeeId,
  }) => database.transaction(() async {
    final tables =
        (await database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name IN ("
                  "'regular_payroll_payments','regular_payroll_employees','regular_payroll_reversals_v1',"
                  "'payroll_expense_links_v1','payroll_expense_projection_pending_v1')",
                )
                .get())
            .map((row) => row.read<String>('name'))
            .toSet();
    if (!tables.contains('regular_payroll_payments') ||
        !tables.contains('regular_payroll_employees')) {
      return [];
    }
    final payments = await database
        .customSelect(
          'SELECT p.operation_id,p.employee_id,p.gross,p.repayment,p.net,p.method,p.verified_date,'
          'e.name AS employee_name '
          '${tables.contains('regular_payroll_reversals_v1') ? ',r.recorded_at AS reversed_at ' : ''}'
          'FROM regular_payroll_payments p LEFT JOIN regular_payroll_employees e '
          'ON e.business_id=p.business_id AND e.id=p.employee_id '
          '${tables.contains('regular_payroll_reversals_v1') ? 'LEFT JOIN regular_payroll_reversals_v1 r ON r.business_id=p.business_id AND r.operation_id=p.operation_id ' : ''}'
          'WHERE p.business_id=? AND p.week=? AND (? IS NULL OR p.employee_id=?) '
          'ORDER BY e.name,p.verified_date,p.operation_id',
          variables: [
            Variable(business),
            Variable(week),
            Variable(employeeId),
            Variable(employeeId),
          ],
        )
        .get();
    if (payments.isEmpty) return [];
    final cache = LocalFinancialCache(database: database);
    final expenses = await cache.loadTransactions(
      business,
      direction: 'expense',
    );
    final links = tables.contains('payroll_expense_links_v1')
        ? {
            for (final row
                in await database
                    .customSelect(
                      'SELECT payroll_operation_id,transaction_id FROM payroll_expense_links_v1 WHERE business_id=?',
                      variables: [Variable(business)],
                    )
                    .get())
              row.read<String>('payroll_operation_id'): row.read<String>(
                'transaction_id',
              ),
          }
        : <String, String>{};
    final pending = tables.contains('payroll_expense_projection_pending_v1')
        ? {
            for (final row
                in await database
                    .customSelect(
                      'SELECT operation_id FROM payroll_expense_projection_pending_v1 WHERE business_id=?',
                      variables: [Variable(business)],
                    )
                    .get())
              row.read<String>('operation_id'),
          }
        : <String>{};
    final options = await cache.loadOptions(business);
    List<Map<String, dynamic>> choices(String key) =>
        (options[key] as List? ?? [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
    final postingOptions =
        PayrollExpenseIdentity.uniqueOptionId(
              choices('accounts'),
              'Business Checking - 9858',
            ) !=
            null &&
        PayrollExpenseIdentity.uniqueOptionId(
              choices('categories'),
              'Payroll',
            ) !=
            null;

    final result = <Map<String, dynamic>>[];
    for (final payment in payments) {
      final operation = payment.read<String>('operation_id');
      final name =
          payment.data['employee_name']?.toString() ?? 'Saved employee';
      final net = PayrollExpenseIdentity.verifiedNetCents(payment.data);
      final paidOn = payment.read<String>('verified_date');
      final link = links[operation];
      final linked = expenses
          .where(
            (row) =>
                row['id'] == link ||
                row['payroll_operation_id'] == operation ||
                row['id'] ==
                    PayrollExpenseIdentity.transactionId(business, operation),
          )
          .toList();
      final exact =
          linked.length == 1 &&
          _cents(linked.single['amount']) == net &&
          (linked.single['transaction_date'] ?? linked.single['date']) ==
              paidOn;
      final matches = <Map<String, dynamic>>[
        for (final row in expenses)
          if (linked.contains(row) ||
              row['payroll_operation_id'] == null &&
                  LocalFinancialCache.requiresOwnerAccountEdit(row) &&
                  _cents(row['amount']) == net &&
                  row['transaction_date']?.toString() == paidOn &&
                  row['counterparty']?.toString().trim().toLowerCase() ==
                      name.trim().toLowerCase())
            {
              'expense_reference': row['id'],
              'account': row['account'],
              'date': row['transaction_date'],
              'amount_cents': _cents(row['amount']),
              'same_saved_reference': linked.contains(row),
            },
      ];
      final status = switch ((
        payment.data['reversed_at'] != null,
        net,
        exact,
        linked.isNotEmpty || link != null,
      )) {
        (true, _, _, _) => 'Reversed',
        (_, 0, _, _) => 'No payout',
        (_, _, true, _) => 'In Expenses',
        (_, _, _, true) => 'Saved expense link needs review',
        _ when pending.contains(operation) && !postingOptions =>
          'Waiting for saved payroll account or category',
        _ when pending.contains(operation) =>
          'Saved payroll expense waiting to post',
        _ => 'Verified payment with no linked expense',
      };
      result.add({
        'employee': name,
        'payroll_reference': operation,
        'payment_date': paidOn,
        'net_cents': net,
        'payment_method': payment.read<String>('method'),
        'status': status,
        'possible_expenses': matches,
      });
    }
    return result;
  });

  static int? _cents(Object? amount) {
    final parsed = num.tryParse(amount?.toString() ?? '');
    return parsed == null || !(parsed * 100).isFinite
        ? null
        : (parsed.abs() * 100).round();
  }
}
