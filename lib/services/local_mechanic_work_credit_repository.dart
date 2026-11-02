import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Integration candidate: business-scoped mechanic portions, NOT connected
/// to live Job writes until the mapping is independently verified.
class LocalMechanicWorkCreditRepository {
  LocalMechanicWorkCreditRepository({BriskersLocalDatabase? database})
      : _db = database ?? localDatabase;
  final BriskersLocalDatabase _db;

  Future<void> prepare() => _db.customStatement('''
    CREATE TABLE IF NOT EXISTS local_mechanic_work_credits_v1 (
      business_id TEXT NOT NULL,
      allocation_id TEXT NOT NULL,
      job_id TEXT NOT NULL,
      labor_line_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      employee_id TEXT NOT NULL,
      actual_minutes INTEGER NOT NULL CHECK (actual_minutes >= 0),
      rate_cents INTEGER NOT NULL CHECK (rate_cents >= 0),
      completed INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1)),
      paid_operation_id TEXT,
      revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1),
      PRIMARY KEY (business_id, allocation_id),
      UNIQUE (business_id, task_id, employee_id, allocation_id)
    )
  ''');

  /// The caller supplies a stable allocation identity originating in the
  /// actual labor task / mechanic assignment. This does not infer worked time.
  /// Replaying an identical creation is harmless; changed identity fails.
  Future<bool> createAssignment({
    required String businessId,
    required String allocationId,
    required String jobId,
    required String laborLineId,
    required String taskId,
    required String employeeId,
    required int actualMinutes,
    required int rateCents,
  }) async {
    final ids = [businessId, allocationId, jobId, laborLineId, taskId, employeeId];
    if (ids.any((id) => id.trim().isEmpty) ||
        actualMinutes < 0 || rateCents < 0) {
      throw ArgumentError('Invalid work allocation');
    }
    await prepare();
    return _db.transaction(() async {
      final rows = await _db.customSelect('''
        SELECT job_id, labor_line_id, task_id, employee_id,
               actual_minutes, rate_cents
        FROM local_mechanic_work_credits_v1
        WHERE business_id = ? AND allocation_id = ?
      ''', variables: [Variable<String>(businessId),
        Variable<String>(allocationId)]).get();
      if (rows.isNotEmpty) {
        final row = rows.single;
        if (row.read<String>('job_id') != jobId ||
            row.read<String>('labor_line_id') != laborLineId ||
            row.read<String>('task_id') != taskId ||
            row.read<String>('employee_id') != employeeId ||
            row.read<int>('actual_minutes') != actualMinutes ||
            row.read<int>('rate_cents') != rateCents) {
          throw StateError('Conflicting work allocation replay');
        }
        return false;
      }
      await _db.customStatement('''
        INSERT INTO local_mechanic_work_credits_v1
        (business_id, allocation_id, job_id, labor_line_id, task_id,
         employee_id, actual_minutes, rate_cents)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''', [businessId, allocationId, jobId, laborLineId, taskId,
        employeeId, actualMinutes, rateCents]);
      return true;
    });
  }

  /// One mechanic can finish without completing another mechanic's portion.
  /// A paid allocation is immutable even when a job is reopened.
  Future<bool> markDone({
    required String businessId,
    required String allocationId,
    required String employeeId,
  }) async {
    if ([businessId, allocationId, employeeId]
        .any((id) => id.trim().isEmpty)) {
      throw ArgumentError('Missing work allocation identity');
    }
    await prepare();
    return _db.transaction(() async {
      final rows = await _db.customSelect('''
        SELECT completed, paid_operation_id
        FROM local_mechanic_work_credits_v1
        WHERE business_id = ? AND allocation_id = ? AND employee_id = ?
      ''', variables: [Variable<String>(businessId),
        Variable<String>(allocationId), Variable<String>(employeeId)]).get();
      if (rows.isEmpty || rows.single.read<int>('completed') == 1 ||
          rows.single.read<String?>('paid_operation_id') != null) {
        return false;
      }
      await _db.customStatement('''
        UPDATE local_mechanic_work_credits_v1
        SET completed = 1, revision = revision + 1
        WHERE business_id = ? AND allocation_id = ? AND employee_id = ?
          AND completed = 0 AND paid_operation_id IS NULL
      ''', [businessId, allocationId, employeeId]);
      return true;
    });
  }

  /// Version-checked local editing for the isolated integration workflow.
  /// A paid portion is frozen. Completion of one employee never completes
  /// another employee's portion on a shared task.
  Future<void> recordWork({
    required String businessId,
    required String allocationId,
    required String employeeId,
    required int expectedRevision,
    required int actualMinutes,
    required bool completed,
  }) async {
    if ([businessId, allocationId, employeeId].any((id) => id.trim().isEmpty) || actualMinutes < 0) {
      throw ArgumentError('Invalid work identity or minutes');
    }
    await prepare();
    await _db.transaction(() async {
      final rows = await _db.customSelect(
        'SELECT revision, paid_operation_id FROM local_mechanic_work_credits_v1 WHERE business_id=? AND allocation_id=? AND employee_id=?',
        variables: [Variable<String>(businessId), Variable<String>(allocationId), Variable<String>(employeeId)],
      ).get();
      if (rows.length != 1 || rows.single.read<int>('revision') != expectedRevision || rows.single.read<String?>('paid_operation_id') != null) {
        throw StateError('Work changed or is already paid');
      }
      await _db.customStatement(
        'UPDATE local_mechanic_work_credits_v1 SET actual_minutes=?, completed=?, revision=revision+1 WHERE business_id=? AND allocation_id=? AND employee_id=?',
        [actualMinutes, completed ? 1 : 0, businessId, allocationId, employeeId],
      );
    });
  }

  Future<List<Map<String, Object?>>> completedUnpaid({
    required String businessId,
    required String employeeId,
  }) async {
    if (businessId.trim().isEmpty || employeeId.trim().isEmpty) {
      throw ArgumentError('Business and employee required');
    }
    await prepare();
    final rows = await _db.customSelect('''
      SELECT allocation_id, job_id, labor_line_id, task_id,
             employee_id, actual_minutes, rate_cents, revision
      FROM local_mechanic_work_credits_v1
      WHERE business_id = ? AND employee_id = ? AND completed = 1
        AND paid_operation_id IS NULL ORDER BY allocation_id
    ''', variables: [Variable<String>(businessId),
      Variable<String>(employeeId)]).get();
    return rows.map((row) => Map<String, Object?>.unmodifiable({
      for (final name in ['allocation_id', 'job_id', 'labor_line_id',
        'task_id', 'employee_id'])
        name: row.read<String>(name),
      for (final name in ['actual_minutes', 'rate_cents', 'revision'])
        name: row.read<int>(name),
    })).toList(growable: false);
  }
}
