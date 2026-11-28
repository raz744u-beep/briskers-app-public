import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_document_identity.dart';

/// Read-only aliases for the same ordered labor line of an independently
/// verified invoice identity. Never merges tasks, wages, or payment coverage.
class LocalPayrollTaskIdentity {
  const LocalPayrollTaskIdentity(this.db);
  final BriskersLocalDatabase db;

  Future<Map<String, String>> aliases(String business, {bool refreshDocumentAliases = true}) async {
    if (refreshDocumentAliases) {
      await LocalDocumentIdentity(db).prepare();
    } else if (await db.customSelect(
      "SELECT 1 FROM sqlite_master WHERE name='local_document_identity_aliases'",
    ).getSingleOrNull() == null) {
      return {};
    }
    final matches = await db.customSelect('''
      SELECT duplicate.id AS alias_id, original.id AS canonical_id
      FROM local_document_identity_aliases identity
      JOIN local_documents rd ON rd.business_id=identity.business_id AND rd.id=identity.alias_id
      JOIN local_documents cd ON cd.business_id=identity.business_id AND cd.id=identity.canonical_id
      JOIN regular_payroll_task_sources rs ON rs.business_id=identity.business_id AND rs.invoice_id=rd.id AND rs.source_kind='invoice' AND rs.active=1
      JOIN regular_payroll_task_sources cs ON cs.business_id=identity.business_id AND cs.invoice_id=cd.id AND cs.source_kind='invoice' AND cs.active=1
      JOIN regular_payroll_tasks duplicate ON duplicate.business_id=rs.business_id AND duplicate.id=rs.task_id AND duplicate.job_id=rd.job_id
      JOIN regular_payroll_tasks original ON original.business_id=cs.business_id AND original.id=cs.task_id AND original.job_id=cd.job_id
      JOIN regular_payroll_task_order ro ON ro.business_id=rs.business_id AND ro.task_id=rs.task_id
      JOIN regular_payroll_task_order co ON co.business_id=cs.business_id AND co.task_id=cs.task_id AND co.line_position=ro.line_position
      WHERE identity.business_id=? AND duplicate.id<>original.id
        AND rd.kind='invoice' AND cd.kind='invoice'
        AND duplicate.description=original.description AND duplicate.planned=original.planned
        AND NOT EXISTS (
          SELECT p.employee_id,COALESCE(e.minutes,0) FROM regular_payroll_portions p
          LEFT JOIN regular_payroll_estimates e ON e.business_id=p.business_id AND e.task_id=p.task_id AND e.employee_id=p.employee_id
          WHERE p.business_id=identity.business_id AND p.task_id=duplicate.id
          EXCEPT
          SELECT p.employee_id,COALESCE(e.minutes,0) FROM regular_payroll_portions p
          LEFT JOIN regular_payroll_estimates e ON e.business_id=p.business_id AND e.task_id=p.task_id AND e.employee_id=p.employee_id
          WHERE p.business_id=identity.business_id AND p.task_id=original.id)
        AND NOT EXISTS (
          SELECT p.employee_id,COALESCE(e.minutes,0) FROM regular_payroll_portions p
          LEFT JOIN regular_payroll_estimates e ON e.business_id=p.business_id AND e.task_id=p.task_id AND e.employee_id=p.employee_id
          WHERE p.business_id=identity.business_id AND p.task_id=original.id
          EXCEPT
          SELECT p.employee_id,COALESCE(e.minutes,0) FROM regular_payroll_portions p
          LEFT JOIN regular_payroll_estimates e ON e.business_id=p.business_id AND e.task_id=p.task_id AND e.employee_id=p.employee_id
          WHERE p.business_id=identity.business_id AND p.task_id=duplicate.id)
    ''', variables: [Variable(business)]).get();
    final candidates = <String, Set<String>>{};
    for (final match in matches) {
      candidates.putIfAbsent(match.read<String>('alias_id'), () => {}).add(match.read<String>('canonical_id'));
    }
    return {for (final entry in candidates.entries)
      if (entry.value.length == 1) entry.key: entry.value.single};
  }

  static Map<String, dynamic> project(Map<String, dynamic> row, Map<String, String> aliases, {bool task = false}) {
    final canonical = aliases[(task ? row['id'] : row['task_id'])?.toString()];
    return canonical == null ? row : {
      ...row, 'source_active': 0, 'duplicate_of_task_id': canonical,
    };
  }
}
