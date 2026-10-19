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
