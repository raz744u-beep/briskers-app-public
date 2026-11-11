import 'package:drift/drift.dart' show Variable;
import '../local/briskers_local_database.dart';

class JobTaskProgress {
  const JobTaskProgress(this.done, this.total);
  final int done, total;
}

/// Read-only projections of the same task and portion IDs used by Payroll.
class JobTaskSummary {
  const JobTaskSummary(this.db);
  final BriskersLocalDatabase db;

  Future<bool> _has(String table) async =>
      await db
          .customSelect(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            variables: [Variable(table)],
          )
          .getSingleOrNull() !=
      null;

  Future<JobTaskProgress> progress(String business, String job) async =>
      (await progressForJobs(business, [job]))[job] ??
      const JobTaskProgress(0, 0);

  Future<Map<String, JobTaskProgress>> progressForJobs(
    String business,
    List<String> jobs,
  ) async {
    final result = {for (final id in jobs) id: const JobTaskProgress(0, 0)};
    final laborReady = await _has('regular_payroll_tasks');
    final generalReady = await _has('regular_payroll_shop_task_jobs');
    for (var offset = 0; offset < jobs.length; offset += 300) {
      final batch = jobs.skip(offset).take(300).toList();
      final marks = List.filled(batch.length, '?').join(',');
      final args = [Variable(business), ...batch.map(Variable<String>.new)];
      if (laborReady) {
        final tasks = await db.customSelect("""
          SELECT t.job_id, t.id, COUNT(p.id) AS portions,
                 COUNT(CASE WHEN p.state='Done' THEN 1 END) AS finished
          FROM regular_payroll_tasks t
          JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id AND s.active=1
          LEFT JOIN regular_payroll_portions p ON p.business_id=t.business_id AND p.task_id=t.id
            AND NOT EXISTS (SELECT 1 FROM regular_payroll_assignment_meta m WHERE
              m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id AND m.active=0 AND p.state!='Done')
          WHERE t.business_id=? AND t.job_id IN ($marks) GROUP BY t.job_id,t.id
        """, variables: args).get();
        for (final row in tasks) {
          final id = row.read<String>('job_id');
          final old = result[id]!;
          final done =
              row.read<int>('portions') > 0 &&
              row.read<int>('portions') == row.read<int>('finished');
          result[id] = JobTaskProgress(
            old.done + (done ? 1 : 0),
            old.total + 1,
          );
        }
      }
      if (generalReady) {
        final general = await db.customSelect("""
          SELECT j.job_id,t.status FROM regular_payroll_shop_tasks t
          JOIN regular_payroll_shop_task_jobs j ON j.business_id=t.business_id AND j.task_id=t.id
          WHERE j.business_id=? AND j.job_id IN ($marks)
        """, variables: args).get();
        for (final row in general) {
          final id = row.read<String>('job_id');
          final old = result[id]!;
          result[id] = JobTaskProgress(
            old.done + (row.read<String>('status') == 'done' ? 1 : 0),
            old.total + 1,
          );
        }
      }
    }
    return result;
  }

  Future<Map<String, Map<String, int>>> hours(
    String business,
    List<String> jobs,
  ) async {
    final result = <String, Map<String, int>>{};
    if (jobs.isEmpty || !await _has('regular_payroll_assignment_meta')) {
      return result;
    }
    // Nicknames are keyed by immutable employee ID in the local shop DB.
    // Use them for display only; never rewrite assignment or payroll identity.
    final nicknamesReady = await _has('local_employee_nicknames');
    final rows = await db
        .customSelect(
          """
      SELECT t.job_id,p.employee_id,e.name,
        ${nicknamesReady ? "n.nickname" : "NULL"} AS nickname,
        SUM(COALESCE(v.minutes,0)) AS minutes
      FROM regular_payroll_tasks t
      JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id AND s.active=1
      JOIN regular_payroll_portions p ON p.business_id=t.business_id AND p.task_id=t.id
      JOIN regular_payroll_employees e ON e.business_id=p.business_id AND e.id=p.employee_id
      ${nicknamesReady ? "LEFT JOIN local_employee_nicknames n ON n.business_id=p.business_id AND n.employee_id=p.employee_id" : ""}
      LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id
      LEFT JOIN regular_payroll_estimates v ON v.business_id=p.business_id AND v.task_id=p.task_id AND v.employee_id=p.employee_id
      WHERE t.business_id=? AND t.job_id IN (${List.filled(jobs.length, '?').join(',')})
        AND (COALESCE(m.active,1)=1 OR p.state='Done')
      GROUP BY t.job_id,p.employee_id,e.name${nicknamesReady ? ",n.nickname" : ""} ORDER BY e.name,p.employee_id
    """,
          variables: [Variable(business), ...jobs.map(Variable<String>.new)],
        )
        .get();
    for (final r in rows) {
      final people = result.putIfAbsent(r.read<String>('job_id'), () => {});
      final savedNickname = r.readNullable<String>('nickname')?.trim() ?? '';
      final name = savedNickname.isNotEmpty
          ? savedNickname
          : r.read<String>('name');
      final label = people.containsKey(name)
          ? '$name (${r.read<String>('employee_id')})'
          : name;
      people[label] = r.read<int>('minutes');
    }
    return result;
  }
}
