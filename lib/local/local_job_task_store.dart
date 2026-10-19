import 'package:drift/drift.dart';
import 'briskers_local_database.dart';

/// Local-only task storage. Deliberately does not enqueue SyncOutbox rows:
/// a corresponding server endpoint must be available before synchronization.
class LocalJobTaskStore {
  const LocalJobTaskStore(this.db);
  final BriskersLocalDatabase db;

  Future<List<Map<String, Object?>>> listForJob(
    String businessId,
    String jobId,
  ) async {
    final rows = await db.customSelect(
      'SELECT id, business_id, job_id, description, source_line_id, '
      'is_billable, is_required, status, billed_hours, payroll_hours, '
      'sync_state FROM local_job_tasks '
      'WHERE business_id = ? AND job_id = ? ORDER BY created_at, id',
      variables: [Variable.withString(businessId), Variable.withString(jobId)],
    ).get();
    return rows.map((r) => r.data).toList();
  }

  /// Save an entire task allocation atomically, on this device only.
  /// Existing invoiced/billed hours are never modified.
  Future<void> replaceLocalAssignees({
    required String businessId,
    required String jobId,
    required String taskId,
    required Map<String, double> hoursByEmployeeId,
  }) async {
    if (businessId.trim().isEmpty || jobId.trim().isEmpty ||
        taskId.trim().isEmpty) {
      throw ArgumentError('Job and task identity required');
    }
    for (final entry in hoursByEmployeeId.entries) {
      if (entry.key.trim().isEmpty || !entry.value.isFinite ||
          entry.value < 0) {
        throw ArgumentError('Each mechanic needs valid payroll hours');
      }
    }
    await db.transaction(() async {
      final rows = await db.customSelect(
        'SELECT id FROM local_job_tasks '
        'WHERE id = ? AND business_id = ? AND job_id = ?',
        variables: [
          Variable.withString(taskId),
          Variable.withString(businessId),
          Variable.withString(jobId),
        ],
      ).get();
      if (rows.length != 1) {
        throw StateError('Task not found in this shop and job');
      }
      await db.customStatement(
        'DELETE FROM local_job_task_assignees WHERE task_id = ?',
        [taskId],
      );
      for (final entry in hoursByEmployeeId.entries) {
        await db.customStatement(
          'INSERT INTO local_job_task_assignees '
          '(task_id, employee_id, payroll_hours) VALUES (?, ?, ?)',
          [taskId, entry.key, entry.value],
        );
      }
      final total = hoursByEmployeeId.values.fold<double>(
        0, (sum, value) => sum + value,
      );
      await db.customStatement(
        'UPDATE local_job_tasks SET payroll_hours = ?, '
        "sync_state = 'local_only', "
        "updated_at = CAST(strftime('%s','now') AS INTEGER) "
        'WHERE id = ? AND business_id = ? AND job_id = ?',
        [total, taskId, businessId, jobId],
      );
    });
  }

  Future<Map<String, double>> assigneesForTask({
    required String businessId,
    required String jobId,
    required String taskId,
  }) async {
    final rows = await db.customSelect(
      'SELECT a.employee_id, a.payroll_hours '
      'FROM local_job_task_assignees a '
      'JOIN local_job_tasks t ON t.id = a.task_id '
      'WHERE t.business_id = ? AND t.job_id = ? AND t.id = ?',
      variables: [
        Variable.withString(businessId),
        Variable.withString(jobId),
        Variable.withString(taskId),
      ],
    ).get();
    return {
      for (final row in rows)
        row.read<String>('employee_id'):
            row.read<double>('payroll_hours'),
    };
  }

  /// Uses the same canonical line ID for estimate-to-invoice conversions.
  /// Existing task IDs and manually adjusted payroll hours are retained.
  Future<void> createIfMissing({
    required String id,
    required String businessId,
    required String jobId,
    required String description,
    required String sourceLineId,
    required double billedHours,
    required double payrollHours,
  }) async {
    if (!billedHours.isFinite || billedHours < 0 ||
        !payrollHours.isFinite || payrollHours < 0) {
      throw ArgumentError('Labor hours must be finite and nonnegative');
    }
    await db.customStatement(
      'INSERT OR IGNORE INTO local_job_tasks '
      '(id, business_id, job_id, description, source_line_id, is_billable, '
      'is_required, status, billed_hours, payroll_hours, sync_state, '
      'created_at, updated_at) '
      "VALUES (?, ?, ?, ?, ?, 1, 1, 'not_started', ?, ?, 'local_only', "
      "CAST(strftime('%s','now') AS INTEGER), "
      "CAST(strftime('%s','now') AS INTEGER))",
      [id, businessId, jobId, description, sourceLineId, billedHours, payrollHours],
    );
  }
}
