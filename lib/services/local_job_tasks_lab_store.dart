import 'package:drift/drift.dart' show Variable;
import '../local/briskers_local_database.dart';

/// Test-phone-only store. No invoice, payroll, Supabase or outbox writes.
class LocalJobTasksLabStore {
  const LocalJobTasksLabStore(this.db);
  final BriskersLocalDatabase db;

  static Future<void> ensureTables(BriskersLocalDatabase db) async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_job_tasks_lab (
        business_id TEXT NOT NULL, job_id TEXT NOT NULL,
        document_id TEXT NOT NULL, line_id TEXT NOT NULL,
        source_description TEXT NOT NULL, custom_description TEXT,
        employee_id TEXT, payroll_hours REAL, source_invoice_hours REAL,
        status TEXT NOT NULL DEFAULT 'planned',
        completed_at INTEGER, source_missing INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (business_id, job_id, document_id, line_id)
      )
    ''');
    // Safe upgrade for the already-installed isolated test database.
    // Keep billed labor quantity separate from payroll allocation totals.
    final columns = await db.customSelect(
      'PRAGMA table_info(local_job_tasks_lab)',
    ).get();
    if (!columns.any((row) =>
        row.read<String>('name') == 'source_invoice_hours')) {
      await db.customStatement(
        'ALTER TABLE local_job_tasks_lab '
        'ADD COLUMN source_invoice_hours REAL',
      );
    }
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_job_tasks_lab_job
      ON local_job_tasks_lab (business_id, job_id, status)
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_task_allocations_lab (
        business_id TEXT NOT NULL, job_id TEXT NOT NULL,
        document_id TEXT NOT NULL, line_id TEXT NOT NULL,
        employee_id TEXT NOT NULL, hours REAL NOT NULL,
        PRIMARY KEY(business_id, job_id, document_id, line_id, employee_id)
      )
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_job_status_lab (
        business_id TEXT NOT NULL, job_id TEXT NOT NULL,
        status_code TEXT NOT NULL, updated_at INTEGER NOT NULL,
        PRIMARY KEY (business_id, job_id)
      )
    ''');
    // Keep the prior completion in the Work Log when a completed job reopens.
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_task_completion_history_lab (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id TEXT NOT NULL, job_id TEXT NOT NULL,
        document_id TEXT NOT NULL, line_id TEXT NOT NULL,
        description TEXT NOT NULL,
        employee_id TEXT, payroll_hours REAL, assignment_summary TEXT,
        completed_at INTEGER NOT NULL, reopened_at INTEGER NOT NULL
      )
    ''');
    // One immutable earned-hours snapshot per original labor task.
    // Re-completing a reopened task must not credit the same labor twice.
    // This is a read-only payroll PREVIEW ledger, not a payment record.
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_payroll_preserved_tasks_lab (
        business_id TEXT NOT NULL, job_id TEXT NOT NULL,
        document_id TEXT NOT NULL, line_id TEXT NOT NULL,
        captured_at INTEGER NOT NULL,
        PRIMARY KEY (business_id, job_id, document_id, line_id)
      )
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_payroll_preserved_hours_lab (
        business_id TEXT NOT NULL, job_id TEXT NOT NULL,
        document_id TEXT NOT NULL, line_id TEXT NOT NULL,
        employee_id TEXT NOT NULL, hours REAL NOT NULL,
        PRIMARY KEY (business_id, job_id, document_id, line_id, employee_id)
      )
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_job_lead_lab (
        business_id TEXT NOT NULL, job_id TEXT NOT NULL,
        employee_id TEXT, updated_at INTEGER NOT NULL,
        PRIMARY KEY (business_id, job_id)
      )
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_employee_nicknames_lab (
        business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
        nickname TEXT NOT NULL, PRIMARY KEY (business_id, employee_id)
      )
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_employee_full_names_lab (
        business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
        full_name TEXT NOT NULL, PRIMARY KEY (business_id, employee_id)
      )
    ''');
  }

  static const validJobStatuses = <String>{
    'open', 'in_progress', 'pending_approval', 'waiting_parts',
    'needs_recheck', 'completed', 'cancelled',
  };

  /// Existing installed test tasks are migrated without overwriting work.
  /// A prior Done task does not silently close a job or invoice.
  Future<String> jobStatus(String businessId, String jobId) async {
    await ensureTables(db);
    final recorded = await db.customSelect(
      'SELECT status_code FROM local_job_status_lab '
      'WHERE business_id=? AND job_id=?',
      variables: [Variable<String>(businessId), Variable<String>(jobId)],
    ).getSingleOrNull();
    if (recorded != null) return recorded.read<String>('status_code');
    final active = await db.customSelect(
      "SELECT 1 FROM local_job_tasks_lab "
      "WHERE business_id=? AND job_id=? AND source_missing=0 "
      "AND status!='planned' LIMIT 1",
      variables: [Variable<String>(businessId), Variable<String>(jobId)],
    ).getSingleOrNull();
    return active == null ? 'open' : 'in_progress';
  }

  Future<List<Map<String, dynamic>>> priorCompletions(
      String businessId, String jobId) async {
    await ensureTables(db);
    final rows = await db.customSelect(
      'SELECT * FROM local_task_completion_history_lab '
      'WHERE business_id=? AND job_id=? ORDER BY completed_at DESC, id DESC',
      variables: [Variable<String>(businessId), Variable<String>(jobId)],
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  // Older Tasks TEST builds archived completed work before earned-hours
  // snapshots existed. Backfill the FIRST archived completion for each task,
  // never replacing it with a later recheck completion.
  Future<void> _backfillPreservedHoursFromHistory(
      String businessId, String jobId) async {
    final older = await db.customSelect(
      'SELECT document_id, line_id, employee_id, payroll_hours, '
      'assignment_summary FROM local_task_completion_history_lab '
      'WHERE business_id=? AND job_id=? '
      'ORDER BY completed_at ASC, id ASC',
      variables: [Variable<String>(businessId), Variable<String>(jobId)],
    ).get();
    for (final entry in older) {
      final doc = entry.read<String>('document_id');
      final line = entry.read<String>('line_id');
      final known = await db.customSelect(
        'SELECT 1 FROM local_payroll_preserved_tasks_lab '
        'WHERE business_id=? AND job_id=? AND document_id=? AND line_id=?',
        variables: [
          Variable<String>(businessId), Variable<String>(jobId),
          Variable<String>(doc), Variable<String>(line),
        ],
      ).getSingleOrNull();
      if (known != null) continue;
      final summary = entry.readNullable<String>('assignment_summary') ?? '';
      final hoursByMechanic = <String, double>{};
      final pattern = RegExp(r'([^,\s]+):\s*(\d+(?:\.\d+)?)\s*hrs');
      for (final match in pattern.allMatches(summary)) {
        final id = match.group(1);
        final hours = double.tryParse(match.group(2) ?? '');
        if (id != null && hours != null && hours.isFinite && hours > 0) {
          hoursByMechanic[id] = (hoursByMechanic[id] ?? 0) + hours;
        }
      }
      if (hoursByMechanic.isEmpty) {
        final id = entry.readNullable<String>('employee_id');
        final hours = entry.readNullable<double>('payroll_hours') ?? 0;
        if (id != null && id.isNotEmpty && hours.isFinite && hours > 0) {
          hoursByMechanic[id] = hours;
        }
      }
      await db.customStatement(
        'INSERT INTO local_payroll_preserved_tasks_lab '
        '(business_id, job_id, document_id, line_id, captured_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [businessId, jobId, doc, line, DateTime.now().millisecondsSinceEpoch],
      );
      for (final allocation in hoursByMechanic.entries) {
        await db.customStatement(
          'INSERT INTO local_payroll_preserved_hours_lab '
          '(business_id, job_id, document_id, line_id, employee_id, hours) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [businessId, jobId, doc, line, allocation.key, allocation.value],
        );
      }
    }
  }

  /// Immutable snapshots from the first completed work cycle. The marker
  /// exists even when a task had no mechanic, preventing later double credit.
  Future<({Map<String, double> hoursByMechanic, Set<String> taskKeys})>
      preservedPayrollPreview(String businessId, String jobId) async {
    await ensureTables(db);
    await db.transaction(() async =>
      _backfillPreservedHoursFromHistory(businessId, jobId));
    String key(String doc, String line) => '${doc.length}:$doc$line';
    final tasks = await db.customSelect(
      'SELECT document_id, line_id FROM local_payroll_preserved_tasks_lab '
      'WHERE business_id=? AND job_id=?',
      variables: [Variable<String>(businessId), Variable<String>(jobId)],
    ).get();
    final allocations = await db.customSelect(
      'SELECT employee_id, hours FROM local_payroll_preserved_hours_lab '
      'WHERE business_id=? AND job_id=?',
      variables: [Variable<String>(businessId), Variable<String>(jobId)],
    ).get();
    final byMechanic = <String, double>{};
    for (final allocation in allocations) {
      final id = allocation.read<String>('employee_id');
      byMechanic[id] = (byMechanic[id] ?? 0) +
          allocation.read<double>('hours');
    }
    return (
      hoursByMechanic: byMechanic,
      taskKeys: {
        for (final task in tasks)
          key(task.read<String>('document_id'),
              task.read<String>('line_id')),
      },
    );
  }

  /// Freeze the original per-mechanic hours when a Completed job is reopened.
  /// A unique task marker prevents any later completion cycle crediting the
  /// original labor again. Additional recheck work needs a distinct task.
  Future<void> _preservePayrollOnReopen(
      String businessId, String jobId, int capturedAt) async {
    await _backfillPreservedHoursFromHistory(businessId, jobId);
    final completed = await db.customSelect(
      'SELECT document_id, line_id, employee_id, payroll_hours '
      'FROM local_job_tasks_lab WHERE business_id=? AND job_id=? '
      "AND source_missing=0 AND status='done'",
      variables: [Variable<String>(businessId), Variable<String>(jobId)],
    ).get();
    for (final row in completed) {
      final doc = row.read<String>('document_id');
      final line = row.read<String>('line_id');
      final previous = await db.customSelect(
        'SELECT 1 FROM local_payroll_preserved_tasks_lab '
        'WHERE business_id=? AND job_id=? AND document_id=? AND line_id=?',
        variables: [Variable<String>(businessId), Variable<String>(jobId),
          Variable<String>(doc), Variable<String>(line)],
      ).getSingleOrNull();
      if (previous != null) continue;
      final allocations = await db.customSelect(
        'SELECT employee_id, hours FROM local_task_allocations_lab '
        'WHERE business_id=? AND job_id=? AND document_id=? AND line_id=?',
        variables: [Variable<String>(businessId), Variable<String>(jobId),
          Variable<String>(doc), Variable<String>(line)],
      ).get();
      await db.customStatement(
        'INSERT INTO local_payroll_preserved_tasks_lab '
        '(business_id, job_id, document_id, line_id, captured_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [businessId, jobId, doc, line, capturedAt],
      );
      if (allocations.isNotEmpty) {
        for (final allocation in allocations) {
          await db.customStatement(
            'INSERT INTO local_payroll_preserved_hours_lab '
            '(business_id, job_id, document_id, line_id, employee_id, hours) '
            'VALUES (?, ?, ?, ?, ?, ?)',
            [businessId, jobId, doc, line,
              allocation.read<String>('employee_id'),
              allocation.read<double>('hours')],
          );
        }
      } else {
        final id = row.readNullable<String>('employee_id');
        final hours = row.readNullable<double>('payroll_hours') ?? 0;
        if (id != null && id.isNotEmpty && hours > 0) {
          await db.customStatement(
            'INSERT INTO local_payroll_preserved_hours_lab '
            '(business_id, job_id, document_id, line_id, employee_id, hours) '
            'VALUES (?, ?, ?, ?, ?, ?)',
            [businessId, jobId, doc, line, id, hours],
          );
        }
      }
    }
  }

  /// Payroll PREVIEW, not real payment: frozen original earned hours plus
  /// currently Done tasks that have never been credited. Reopening the same
  /// labor line does not credit it again. Distinct recheck tasks can earn hours.
  Future<Map<String, double>> earnedHoursPreview(
      String businessId, String jobId) async {
    final frozen = await preservedPayrollPreview(businessId, jobId);
    final result = <String, double>{...frozen.hoursByMechanic};
    final done = await db.customSelect(
      'SELECT document_id, line_id, employee_id, payroll_hours '
      'FROM local_job_tasks_lab WHERE business_id=? AND job_id=? '
      "AND source_missing=0 AND status='done'",
      variables: [Variable<String>(businessId), Variable<String>(jobId)],
    ).get();
    for (final row in done) {
      final doc = row.read<String>('document_id');
      final line = row.read<String>('line_id');
      if (frozen.taskKeys.contains('${doc.length}:$doc$line')) continue;
      final allocations = await db.customSelect(
        'SELECT employee_id, hours FROM local_task_allocations_lab '
        'WHERE business_id=? AND job_id=? AND document_id=? AND line_id=?',
        variables: [Variable<String>(businessId), Variable<String>(jobId),
          Variable<String>(doc), Variable<String>(line)],
      ).get();
      if (allocations.isNotEmpty) {
        for (final allocation in allocations) {
          final id = allocation.read<String>('employee_id');
          final hours = allocation.read<double>('hours');
          result[id] = (result[id] ?? 0) + hours;
        }
      } else {
        final id = row.readNullable<String>('employee_id');
        final hours = row.readNullable<double>('payroll_hours') ?? 0;
        if (id != null && id.isNotEmpty && hours > 0) {
          result[id] = (result[id] ?? 0) + hours;
        }
      }
    }
    return result;
  }

  /// An explicit Job status change has the same effect from the Jobs list,
  /// Job Detail and Tasks. Completing is atomic with all active task statuses.
  /// Reopening creates permanent Work Log snapshots, but never touches money.
  Future<int> changeJobStatus({
    required String businessId, required String jobId,
    required String statusCode,
    List<Map<String, String>>? confirmedTasks,
  }) async {
    await ensureTables(db);
    if (businessId.trim().isEmpty || jobId.trim().isEmpty ||
        !validJobStatuses.contains(statusCode)) {
      throw ArgumentError('Invalid job status or identity');
    }
    return db.transaction(() async {
      final previous = await jobStatus(businessId, jobId);
      if (statusCode == previous) return 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      int affected = 0;
      if (statusCode == 'completed') {
        final requested = confirmedTasks ?? const <Map<String, String>>[];
        final confirmed = <String>{};
        String id(String doc, String line) => '${doc.length}:$doc$line';
        for (final task in requested) {
          final doc = task['document_id']?.trim() ?? '';
          final line = task['line_id']?.trim() ?? '';
          if (doc.isEmpty || line.isEmpty ||
              !confirmed.add(id(doc, line))) {
            throw ArgumentError('Invalid or duplicate confirmed task');
          }
        }
        final tasks = await db.customSelect(
          'SELECT document_id, line_id, status FROM local_job_tasks_lab '
          'WHERE business_id=? AND job_id=? AND source_missing=0',
          variables: [Variable<String>(businessId),
            Variable<String>(jobId)],
        ).get();
        final actual = {
          for (final task in tasks)
            id(task.read<String>('document_id'), task.read<String>('line_id')),
        };
        if (actual.isEmpty || actual.length != confirmed.length ||
            !actual.containsAll(confirmed)) {
          throw StateError('Job tasks changed. Review before completing.');
        }
        affected = tasks.where((task) =>
            task.read<String>('status') != 'done').length;
        await db.customStatement(
          "UPDATE local_job_tasks_lab SET status='done', "
          "completed_at=COALESCE(completed_at, ?), updated_at=? "
          "WHERE business_id=? AND job_id=? AND source_missing=0 "
          "AND status!='done'",
          [now, now, businessId, jobId],
        );
      } else if (previous == 'completed') {
        // Snapshot earned hours before task reactivation. This runs inside
        // the same transaction as archived completion and status changes.
        await _preservePayrollOnReopen(businessId, jobId, now);
        // Preserve previous completion events in history for audit/work log.
        await db.customStatement('''
          INSERT INTO local_task_completion_history_lab
          (business_id, job_id, document_id, line_id, description,
           employee_id, payroll_hours, assignment_summary,
           completed_at, reopened_at)
          SELECT t.business_id, t.job_id, t.document_id, t.line_id,
            COALESCE(t.custom_description, t.source_description),
            t.employee_id, t.payroll_hours,
            COALESCE(
              (SELECT group_concat(a.employee_id || ': ' || a.hours || ' hrs', ', ')
               FROM local_task_allocations_lab a
               WHERE a.business_id=t.business_id AND a.job_id=t.job_id
                 AND a.document_id=t.document_id AND a.line_id=t.line_id),
              t.employee_id || ': ' || t.payroll_hours || ' hrs',
              'Unassigned'
            ),
            t.completed_at, ?
          FROM local_job_tasks_lab t WHERE t.business_id=? AND t.job_id=?
            AND t.source_missing=0 AND t.status='done'
            AND t.completed_at IS NOT NULL
        ''', [now, businessId, jobId]);
        final completed = await db.customSelect(
          "SELECT COUNT(*) AS count FROM local_job_tasks_lab "
          "WHERE business_id=? AND job_id=? AND source_missing=0 "
          "AND status='done'",
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        ).getSingle();
        affected = completed.read<int>('count');
        await db.customStatement(
          "UPDATE local_job_tasks_lab SET status='in_progress', "
          "completed_at=NULL, updated_at=? "
          "WHERE business_id=? AND job_id=? AND source_missing=0 "
          "AND status='done'",
          [now, businessId, jobId],
        );
      }
      await db.customStatement(
        'INSERT INTO local_job_status_lab '
        '(business_id, job_id, status_code, updated_at) VALUES (?,?,?,?) '
        'ON CONFLICT(business_id, job_id) DO UPDATE SET '
        'status_code=excluded.status_code, updated_at=excluded.updated_at',
        [businessId, jobId, statusCode, now],
      );
      return affected;
    });
  }

  Future<String?> leadMechanic(String businessId, String jobId) async {
    await ensureTables(db);
    final row = await db.customSelect(
      'SELECT employee_id FROM local_job_lead_lab '
      'WHERE business_id=? AND job_id=?',
      variables: [Variable<String>(businessId), Variable<String>(jobId)],
    ).getSingleOrNull();
    return row?.readNullable<String>('employee_id');
  }

  /// Assign uncustomized task labor to the job lead automatically.
  /// Explicit invoice allocations are never rewritten by lead changes.
  Future<void> saveLeadMechanic(
    String businessId, String jobId, String? employeeId,
  ) async {
    await ensureTables(db);
    if (businessId.trim().isEmpty || jobId.trim().isEmpty) {
      throw ArgumentError('Business and job required');
    }
    await db.transaction(() async {
      final previous = await leadMechanic(businessId, jobId);
      final newLead = employeeId == null || employeeId.isEmpty
          ? null : employeeId;
      await db.customStatement(
        'INSERT INTO local_job_lead_lab '
        '(business_id, job_id, employee_id, updated_at) VALUES (?, ?, ?, ?) '
        'ON CONFLICT(business_id, job_id) '
        'DO UPDATE SET employee_id=excluded.employee_id, '
        'updated_at=excluded.updated_at',
        [businessId, jobId, newLead,
          DateTime.now().millisecondsSinceEpoch],
      );
      // Only tasks without manual splits/allocations, and either previously
      // unassigned or inheriting the former lead, receive the new lead.
      await db.customStatement('''
        UPDATE local_job_tasks_lab SET employee_id=?, updated_at=?
        WHERE business_id=? AND job_id=?
          AND (employee_id IS NULL OR employee_id=?)
          AND NOT EXISTS (
            SELECT 1 FROM local_task_allocations_lab a
            WHERE a.business_id=local_job_tasks_lab.business_id
              AND a.job_id=local_job_tasks_lab.job_id
              AND a.document_id=local_job_tasks_lab.document_id
              AND a.line_id=local_job_tasks_lab.line_id
          )
      ''', [newLead, DateTime.now().millisecondsSinceEpoch,
        businessId, jobId, previous]);
    });
  }

  Future<List<Map<String, dynamic>>> list(String businessId, String jobId) async {
    await ensureTables(db);
    final rows = await db.customSelect(
      'SELECT * FROM local_job_tasks_lab WHERE business_id=? AND job_id=? '
      'ORDER BY document_id, line_id',
      variables: [Variable<String>(businessId), Variable<String>(jobId)],
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  /// Update source description, but preserve edited text, assigned employee,
  /// hours, completion time and status. Invoice deletion is non-destructive.
  Future<void> reconcileDocument({
    required String businessId, required String jobId,
    required String documentId,
    required List<Map<String, dynamic>> laborLines,
  }) async {
    await ensureTables(db);
    if ([businessId, jobId, documentId].any((v) => v.trim().isEmpty)) {
      throw ArgumentError('Missing shop, job or invoice identity');
    }
    await db.transaction(() async {
      await db.customStatement(
        'UPDATE local_job_tasks_lab SET source_missing=1 '
        'WHERE business_id=? AND job_id=? AND document_id=?',
        [businessId, jobId, documentId],
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final lead = await leadMechanic(businessId, jobId);
      for (final line in laborLines) {
        final id = line['id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        final description = (line['description'] ?? line['name'] ?? '')
            .toString().trim();
        if (description.isEmpty) continue;
        final qty = _numeric(line['quantity']);
        await db.customStatement('''
          INSERT INTO local_job_tasks_lab
            (business_id, job_id, document_id, line_id,
             source_description, source_invoice_hours, payroll_hours,
             employee_id, status, updated_at, source_missing)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'planned', ?, 0)
          ON CONFLICT(business_id, job_id, document_id, line_id)
          DO UPDATE SET source_description=excluded.source_description,
                        source_invoice_hours=excluded.source_invoice_hours,
                        source_missing=0
        ''', [businessId, jobId, documentId, id, description, qty, qty, lead, now]);
      }
    });
  }

  static double? _numeric(dynamic value) {
    final n = value is num ? value.toDouble() :
        double.tryParse(value?.toString() ?? '');
    if (n == null || !n.isFinite || n < 0) return null;
    return n;
  }

  Future<void> editTask({
    required String businessId, required String jobId,
    required String documentId, required String lineId,
    String? employeeId, String? status, String? description, double? hours,
    bool editEmployee = false, bool editDescription = false,
    bool editHours = false,
  }) async {
    await ensureTables(db);
    if (hours != null && (!hours.isFinite || hours < 0)) {
      throw ArgumentError('Invalid hours');
    }
    if (status != null &&
        !const {'planned', 'in_progress', 'done'}.contains(status)) {
      throw ArgumentError('Invalid task status');
    }
    if (editDescription && (description?.trim().isEmpty ?? true)) {
      throw ArgumentError('Description required');
    }
    await db.transaction(() async {
      if (status != null && status != 'done' &&
          await jobStatus(businessId, jobId) == 'completed') {
        throw StateError('Reopen the job before changing completed tasks');
      }
      final row = await db.customSelect(
        'SELECT status, completed_at FROM local_job_tasks_lab '
        'WHERE business_id=? AND job_id=? AND document_id=? AND line_id=?',
        variables: [
          Variable<String>(businessId), Variable<String>(jobId),
          Variable<String>(documentId), Variable<String>(lineId),
        ],
      ).getSingleOrNull();
      if (row == null) throw StateError('Task not found');
      final previousStatus = row.read<String>('status');
      final finished = status == 'done'
          ? (previousStatus == 'done'
              ? row.readNullable<int>('completed_at') ??
                  DateTime.now().millisecondsSinceEpoch
              : DateTime.now().millisecondsSinceEpoch)
          : status == null ? row.readNullable<int>('completed_at') : null;
      final changes = <String>['updated_at=?'];
      final args = <Object?>[DateTime.now().millisecondsSinceEpoch];
      if (editEmployee) {
        changes.add('employee_id=?');
        args.add(employeeId == null || employeeId.isEmpty ? null : employeeId);
      }
      if (editHours) {
        changes.add('payroll_hours=?'); args.add(hours);
      }
      if (editDescription) {
        changes.add('custom_description=?'); args.add(description!.trim());
      }
      if (status != null) {
        changes.add('status=?'); args.add(status);
        changes.add('completed_at=?'); args.add(finished);
      }
      await db.customStatement(
        "UPDATE local_job_tasks_lab SET ${changes.join(', ')} "
        "WHERE business_id=? AND job_id=? AND document_id=? AND line_id=?",
        [...args, businessId, jobId, documentId, lineId],
      );
      // Only the Open status auto-promotes; pause/recheck statuses remain.
      if (status == 'in_progress' || status == 'done') {
        if (await jobStatus(businessId, jobId) == 'open') {
          await db.customStatement(
            'INSERT INTO local_job_status_lab '
            '(business_id, job_id, status_code, updated_at) '
            "VALUES (?, ?, 'in_progress', ?) "
            'ON CONFLICT(business_id, job_id) DO UPDATE SET '
            'status_code=excluded.status_code, updated_at=excluded.updated_at',
            [businessId, jobId, DateTime.now().millisecondsSinceEpoch],
          );
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> allocations({
    required String businessId, required String jobId,
    required String documentId, required String lineId,
  }) async {
    await ensureTables(db);
    final rows = await db.customSelect(
      'SELECT employee_id, hours FROM local_task_allocations_lab '
      'WHERE business_id=? AND job_id=? AND document_id=? AND line_id=? '
      'ORDER BY employee_id',
      variables: [Variable<String>(businessId), Variable<String>(jobId),
        Variable<String>(documentId), Variable<String>(lineId)],
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  /// One authoritative allocation per invoice labor line, shared by invoice,
  /// task editor and payroll preview. Never modifies invoice price or quantity.
  Future<void> saveAllocations({
    required String businessId, required String jobId,
    required String documentId, required String lineId,
    required Map<String, double> hoursByEmployee,
  }) async {
    await ensureTables(db);
    if ([businessId, jobId, documentId, lineId]
        .any((value) => value.trim().isEmpty)) {
      throw ArgumentError('Missing task identity');
    }
    if (hoursByEmployee.length > 2 ||
        hoursByEmployee.keys.any((id) => id.trim().isEmpty) ||
        hoursByEmployee.values.any((hours) => !hours.isFinite || hours <= 0)) {
      throw ArgumentError('Choose one or two mechanics with positive hours');
    }
    await db.transaction(() async {
      final task = await db.customSelect(
        'SELECT line_id, source_invoice_hours FROM local_job_tasks_lab '
        'WHERE business_id=? AND job_id=? AND document_id=? AND line_id=?',
        variables: [Variable<String>(businessId), Variable<String>(jobId),
          Variable<String>(documentId), Variable<String>(lineId)],
      ).getSingleOrNull();
      if (task == null) throw StateError('Labor task not found');
      final invoiceHours = task.readNullable<double>('source_invoice_hours');
      if (invoiceHours == null || !invoiceHours.isFinite ||
          invoiceHours < 0) {
        throw StateError('Invoice labor hours unavailable; refresh invoice');
      }
      final allocatedHours = hoursByEmployee.values.fold<double>(
        0, (total, hours) => total + hours);
      if (allocatedHours > invoiceHours + 0.000001) {
        throw ArgumentError('Mechanic hours cannot exceed '
          'invoice labor hours ($invoiceHours hrs)');
      }
      await db.customStatement(
        'DELETE FROM local_task_allocations_lab '
        'WHERE business_id=? AND job_id=? AND document_id=? AND line_id=?',
        [businessId, jobId, documentId, lineId],
      );
      for (final item in hoursByEmployee.entries) {
        await db.customStatement(
          'INSERT INTO local_task_allocations_lab '
          '(business_id, job_id, document_id, line_id, employee_id, hours) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [businessId, jobId, documentId, lineId, item.key, item.value],
        );
      }
      // Avoid double counting: the existing single-mechanic columns become
      // an aggregate/compatibility view, NOT additional payroll credit.
      await db.customStatement(
        'UPDATE local_job_tasks_lab SET employee_id=?, payroll_hours=?, '
        'updated_at=? WHERE business_id=? AND job_id=? '
        'AND document_id=? AND line_id=?',
        [hoursByEmployee.length == 1 ? hoursByEmployee.keys.first : null,
          hoursByEmployee.values.fold<double>(0, (total, h) => total + h),
          DateTime.now().millisecondsSinceEpoch,
          businessId, jobId, documentId, lineId],
      );
    });
  }

  /// Bulk task completion is one atomic local transaction. Every visible
  /// active task must be acknowledged in the confirmation first. Existing
  /// completion times are preserved; invoices and payment state are untouched.
  Future<int> completeConfirmedJobTasks({
    required String businessId,
    required String jobId,
    required List<Map<String, String>> confirmedTasks,
  }) async {
    await ensureTables(db);
    if (businessId.trim().isEmpty || jobId.trim().isEmpty ||
        confirmedTasks.isEmpty) {
      throw ArgumentError('Confirm the active job tasks first');
    }
    String identity(String documentId, String lineId) =>
        '${documentId.length}:$documentId$lineId';
    final acknowledged = <String>{};
    for (final task in confirmedTasks) {
      final doc = task['document_id']?.trim() ?? '';
      final line = task['line_id']?.trim() ?? '';
      if (doc.isEmpty || line.isEmpty ||
          !acknowledged.add(identity(doc, line))) {
        throw ArgumentError('Invalid or duplicate confirmed task');
      }
    }
    return db.transaction(() async {
      final rows = await db.customSelect(
        'SELECT document_id, line_id, status FROM local_job_tasks_lab '
        'WHERE business_id=? AND job_id=? AND source_missing=0',
        variables: [
          Variable<String>(businessId), Variable<String>(jobId),
        ],
      ).get();
      final current = {
        for (final row in rows)
          identity(row.read<String>('document_id'), row.read<String>('line_id')),
      };
      if (current.length != acknowledged.length ||
          !current.containsAll(acknowledged)) {
        throw StateError('Tasks changed. Review the list and confirm again.');
      }
      final remaining = rows.where((row) =>
          row.read<String>('status') != 'done').length;
      if (remaining == 0) return 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.customStatement(
        "UPDATE local_job_tasks_lab SET status='done', "
        "completed_at=?, updated_at=? "
        "WHERE business_id=? AND job_id=? AND source_missing=0 "
        "AND status!='done'",
        [now, now, businessId, jobId],
      );
      return remaining;
    });
  }

  Future<Map<String, String>> nicknames(String businessId) async {
    await ensureTables(db);
    final rows = await db.customSelect(
      'SELECT employee_id, nickname FROM local_employee_nicknames_lab '
      'WHERE business_id=?', variables: [Variable<String>(businessId)],
    ).get();
    return {for (final row in rows)
      row.read<String>('employee_id'): row.read<String>('nickname')};
  }

  Future<void> saveNickname(
      String businessId, String employeeId, String nickname) async {
    await ensureTables(db);
    if (employeeId.isEmpty || nickname.trim().isEmpty) {
      throw ArgumentError('Nickname and employee required');
    }
    await db.customStatement(
      'INSERT INTO local_employee_nicknames_lab '
      '(business_id, employee_id, nickname) VALUES (?, ?, ?) '
      'ON CONFLICT(business_id, employee_id) '
      'DO UPDATE SET nickname=excluded.nickname',
      [businessId, employeeId, nickname.trim()],
    );
  }

  Future<Map<String, String>> fullNames(String businessId) async {
    await ensureTables(db);
    final rows = await db.customSelect(
      'SELECT employee_id, full_name FROM local_employee_full_names_lab '
      'WHERE business_id=?', variables: [Variable<String>(businessId)],
    ).get();
    return {for (final row in rows)
      row.read<String>('employee_id'): row.read<String>('full_name')};
  }

  /// Only changes the local display profile for a synthetic test employee.
  /// Employee IDs and job/task assignments remain unchanged.
  Future<void> saveEmployeeProfile({
    required String businessId, required String employeeId,
    required String fullName, required String displayName,
  }) async {
    await ensureTables(db);
    if ([businessId, employeeId, fullName, displayName]
        .any((part) => part.trim().isEmpty)) {
      throw ArgumentError('Employee name and display name are required');
    }
    await db.transaction(() async {
      await db.customStatement(
        'INSERT INTO local_employee_full_names_lab '
        '(business_id, employee_id, full_name) VALUES (?, ?, ?) '
        'ON CONFLICT(business_id, employee_id) '
        'DO UPDATE SET full_name=excluded.full_name',
        [businessId, employeeId, fullName.trim()],
      );
      await db.customStatement(
        'INSERT INTO local_employee_nicknames_lab '
        '(business_id, employee_id, nickname) VALUES (?, ?, ?) '
        'ON CONFLICT(business_id, employee_id) '
        'DO UPDATE SET nickname=excluded.nickname',
        [businessId, employeeId, displayName.trim()],
      );
    });
  }

  /// Labor only: never parts, discounts, tax or price-only invoice lines.
  static List<Map<String, dynamic>> laborLines(Map<String, dynamic> invoice) {
    if (invoice['kind']?.toString() != 'invoice') return const [];
    final raw = invoice['lines'] ?? invoice['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((x) =>
        Map<String, dynamic>.from(x)).where((row) {
      final kind = (row['line_kind'] ?? row['item_type'] ??
          row['type'] ?? row['category'] ?? '').toString().toLowerCase();
      if (const {'part', 'parts', 'discount', 'tax', 'fee'}.contains(kind)) {
        return false;
      }
      final name = row['name']?.toString().trim().toLowerCase() ?? '';
      return kind == 'labor' || kind == 'labour' ||
          name == 'labor' || name == 'labour';
    }).where((line) =>
        line['id']?.toString().trim().isNotEmpty == true).toList();
  }

  static String displayName(String name, String? nickname) {
    if (nickname?.trim().isNotEmpty == true) return nickname!.trim();
    final word = name.trim().split(RegExp(r'\s+')).first;
    return word.isEmpty ? 'Unassigned' : word;
  }
}
