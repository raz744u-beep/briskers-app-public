import 'package:drift/drift.dart' show Variable;
import '../local/briskers_local_database.dart';

/// Read-only completion evidence. Customer invoice payments, employee names,
/// dates alone and unrelated Expenses never establish mechanic settlement.
class VerifiedPaidLabor {
  const VerifiedPaidLabor(this.db);
  final BriskersLocalDatabase db;

  Future<Set<String>> allocations(String business) async {
    final tables =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table'",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    if (!tables.containsAll({
      'regular_payroll_portions',
      'local_mechanic_work_credits_v1',
    })) {
      return {};
    }
    final clauses = <String>[];
    if (tables.contains('regular_payroll_owner_prior_paid_v1')) {
      clauses.add(
        '''EXISTS(SELECT 1 FROM regular_payroll_owner_prior_paid_v1 h
        WHERE h.business_id=p.business_id AND h.allocation_id=p.id AND h.employee_id=p.employee_id)''',
      );
    }
    if (tables.containsAll({
      'regular_payroll_work_coverage',
      'regular_payroll_payments',
    })) {
      clauses.add(
        '''c.actual_minutes>0 AND
        (SELECT COALESCE(SUM(w.minutes),0) FROM regular_payroll_work_coverage w
         JOIN regular_payroll_payments paid ON paid.business_id=w.business_id
           AND paid.operation_id=w.operation_id AND paid.employee_id=p.employee_id
         WHERE w.business_id=p.business_id AND w.credit_id=p.id)=c.actual_minutes''',
      );
    }
    if (clauses.isEmpty) return {};
    final rows = await db
        .customSelect(
          '''SELECT p.id FROM regular_payroll_portions p
      JOIN local_mechanic_work_credits_v1 c ON c.business_id=p.business_id
        AND c.allocation_id=p.id AND c.employee_id=p.employee_id AND c.task_id=p.task_id
      WHERE p.business_id=? AND (${clauses.map((c) => '($c)').join(' OR ')})''',
          variables: [Variable(business)],
        )
        .get();
    return rows.map((r) => r.read<String>('id')).toSet();
  }
}
