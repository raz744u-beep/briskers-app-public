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
        employee_id TEXT, payroll_hours REAL,
        status TEXT NOT NULL DEFAULT 'planned',
        completed_at INTEGER, source_missing INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (business_id, job_id, document_id, line_id)
      )
    ''');
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_job_tasks_lab_job
      ON local_job_tasks_lab (business_id, job_id, status)
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_employee_nicknames_lab (
        business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
        nickname TEXT NOT NULL, PRIMARY KEY (business_id, employee_id)
      )
    ''');
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
             source_description, payroll_hours, status, updated_at, source_missing)
          VALUES (?, ?, ?, ?, ?, ?, 'planned', ?, 0)
          ON CONFLICT(business_id, job_id, document_id, line_id)
          DO UPDATE SET source_description=excluded.source_description,
                        source_missing=0
        ''', [businessId, jobId, documentId, id, description, qty, now]);
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
        'UPDATE local_job_tasks_lab SET ' + changes.join(', ') +
        ' WHERE business_id=? AND job_id=? AND document_id=? AND line_id=?',
        [...args, businessId, jobId, documentId, lineId],
      );
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
