import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'local_mechanic_work_credit_repository.dart';
import 'local_payroll_work_source.dart';
import 'payroll_lan_peer.dart';
import 'local_invoice_task_store.dart';
import 'local_document_detail_cache.dart';

/// Business-scoped local payroll ledger. Payment recording never sends money
/// or connects to the general financial sync queue.
class LocalPayrollRepository {
  LocalPayrollRepository(
    this.db, {
    required this.business,
    required this.owner,
    this.assertOwnerGrant,
    this.deviceId,
    this.assertLanWriter,
    this.pairedEmployee,
  });
  final BriskersLocalDatabase db;
  final String business;
  final bool owner;
  final void Function()? assertOwnerGrant;
  final String? deviceId;
  final Future<void> Function()? assertLanWriter;
  final String? pairedEmployee;
  Future<void>? _prepared;
  void _authorize() {
    if (!owner || business.trim().isEmpty)
      { throw StateError('Owner payroll access required'); }
    assertOwnerGrant?.call();
  }

  Future<List<Map<String, dynamic>>> _read(
    String sql, [
    List<Object> args = const [],
  ]) async =>
      (await db
              .customSelect(
                sql,
                variables: args
                    .map(
                      (a) => a is int
                          ? Variable<int>(a)
                          : Variable<String>(a as String),
                    )
                    .toList(),
              )
              .get())
          .map((r) => r.data)
          .toList();
  Future<void> prepare() => _prepared ??= _prepare();
  Future<void> _prepare() async {
    await LocalMechanicWorkCreditRepository(database: db).prepare();
    await LocalInvoiceTaskStore(db).prepare();
    for (final sql in [
      '''CREATE TABLE IF NOT EXISTS regular_payroll_payment_authority (business_id TEXT PRIMARY KEY, device_id TEXT NOT NULL)''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_weekly_defaults (business_id TEXT NOT NULL, employee_id TEXT NOT NULL, base_cents INTEGER NOT NULL, hourly_cents INTEGER NOT NULL, adjustment_cents INTEGER NOT NULL, add_labor INTEGER NOT NULL, PRIMARY KEY(business_id,employee_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_shop_tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL, employee_id TEXT NOT NULL, description TEXT NOT NULL, category TEXT NOT NULL, due_at INTEGER, status TEXT NOT NULL DEFAULT 'planned' CHECK(status IN ('planned','in_progress','done')))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_jobs (business_id TEXT NOT NULL, id TEXT NOT NULL, label TEXT NOT NULL, PRIMARY KEY(business_id,id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_tasks (business_id TEXT NOT NULL, id TEXT NOT NULL, job_id TEXT NOT NULL, labor_id TEXT NOT NULL, description TEXT NOT NULL, planned INTEGER NOT NULL CHECK(planned>=0), PRIMARY KEY(business_id,id), UNIQUE(business_id,job_id,labor_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_portions (business_id TEXT NOT NULL, id TEXT NOT NULL, task_id TEXT NOT NULL, employee_id TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('Open','In Progress','Done')), version INTEGER NOT NULL DEFAULT 0, completed_date TEXT, PRIMARY KEY(business_id,id), UNIQUE(business_id,task_id,employee_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_employees (business_id TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL, rate INTEGER NOT NULL CHECK(rate>=0), base_enabled INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(business_id,id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_advances (business_id TEXT NOT NULL, employee_id TEXT NOT NULL, balance INTEGER NOT NULL CHECK(balance>=0), PRIMARY KEY(business_id,employee_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_payments (business_id TEXT NOT NULL, operation_id TEXT NOT NULL, employee_id TEXT NOT NULL, week TEXT NOT NULL, payload TEXT NOT NULL, gross INTEGER NOT NULL, repayment INTEGER NOT NULL, net INTEGER NOT NULL, method TEXT NOT NULL, verified_date TEXT NOT NULL, PRIMARY KEY(business_id,operation_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_paid_work (business_id TEXT NOT NULL, credit_id TEXT NOT NULL, operation_id TEXT NOT NULL, snapshot TEXT NOT NULL, PRIMARY KEY(business_id,credit_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_paid_base (business_id TEXT NOT NULL, employee_id TEXT NOT NULL, week TEXT NOT NULL, operation_id TEXT NOT NULL, amount INTEGER NOT NULL, PRIMARY KEY(business_id,employee_id,week))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_audit (id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL, operation_id TEXT NOT NULL, event TEXT NOT NULL, payload TEXT NOT NULL)''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_sync_outbox (business_id TEXT NOT NULL, operation_id TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'held_local', attempts INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(business_id,operation_id))''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_credit_frozen_update BEFORE UPDATE ON local_mechanic_work_credits_v1 WHEN OLD.paid_operation_id IS NOT NULL AND EXISTS(SELECT 1 FROM regular_payroll_paid_work WHERE business_id=OLD.business_id AND credit_id=OLD.allocation_id) BEGIN SELECT RAISE(ABORT,'Paid credit is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_credit_frozen_delete BEFORE DELETE ON local_mechanic_work_credits_v1 WHEN EXISTS(SELECT 1 FROM regular_payroll_paid_work WHERE business_id=OLD.business_id AND credit_id=OLD.allocation_id) BEGIN SELECT RAISE(ABORT,'Paid credit is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_paid_work_frozen_update BEFORE UPDATE ON regular_payroll_paid_work BEGIN SELECT RAISE(ABORT,'Paid work is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_paid_work_frozen_delete BEFORE DELETE ON regular_payroll_paid_work BEGIN SELECT RAISE(ABORT,'Paid work is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_payments_frozen_update BEFORE UPDATE ON regular_payroll_payments BEGIN SELECT RAISE(ABORT,'Payment is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_payments_frozen_delete BEFORE DELETE ON regular_payroll_payments BEGIN SELECT RAISE(ABORT,'Payment is immutable'); END''',
    ]) {
      await db.customStatement(sql);
    }
    // Retain settled coverage from earlier app versions without rewriting it.
    await db.customStatement(
      'INSERT OR IGNORE INTO regular_payroll_work_coverage '
      '(business_id,credit_id,operation_id,minutes,amount,snapshot) '
      'SELECT w.business_id,w.credit_id,w.operation_id,c.actual_minutes,'
      '(c.actual_minutes*c.rate_cents+30)/60,w.snapshot '
      'FROM regular_payroll_paid_work w JOIN local_mechanic_work_credits_v1 c '
      'ON c.business_id=w.business_id AND c.allocation_id=w.credit_id '
      'WHERE c.actual_minutes>0',
    );
  }

  Future<void> refreshInvoiceTasks() async {
    _authorize();
    await prepare();
    final details = await LocalDocumentDetailCache(database: db).loadAll(business);
    for (final detail in details) {
      _authorize();
      final id = detail['id'];
      if (id is String) await LocalInvoiceTaskStore(db).save(business, id, detail);
    }
    final candidates = await _read(
      "SELECT t.id AS task_id,a.employee_id FROM regular_payroll_tasks t "
      "JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id "
      "JOIN local_jobs j ON j.business_id=t.business_id AND j.id=t.job_id "
      "JOIN local_job_assignments a ON a.business_id=j.business_id AND a.job_id=j.id AND a.active=1 "
      "JOIN regular_payroll_employees e ON e.business_id=a.business_id AND e.id=a.employee_id "
      "WHERE t.business_id=? AND s.active=1 AND s.source_kind='invoice' AND e.rate>0 "
      "AND (a.employee_id=j.assigned_employee_id OR (j.assigned_employee_id IS NULL AND "
      "(SELECT COUNT(*) FROM local_job_assignments a2 WHERE a2.business_id=j.business_id "
      "AND a2.job_id=j.id AND a2.active=1)=1)) "
      "AND NOT EXISTS(SELECT 1 FROM regular_payroll_portions p "
      "WHERE p.business_id=t.business_id AND p.task_id=t.id)",
      [business],
    );
    await db.transaction(() async {
      for (final row in candidates) {
        _authorize();
        final exists = await _read(
          'SELECT id FROM regular_payroll_portions WHERE business_id=? AND task_id=?',
          [business, row['task_id'] as String],
        );
        if (exists.isEmpty) await _assign(row['task_id'] as String, row['employee_id'] as String);
      }
    });
    _authorize();
  }

  Future<void> saveEmployeeCompensation({
    required String employee, required String name, required int rate, required bool weeklyBase,
  }) async {
    _authorize();
    if (employee.isEmpty || name.trim().isEmpty || rate < 0) {
      throw ArgumentError('Valid employee compensation is required.');
    }
    await prepare();
    await db.transaction(() async {
      await db.customStatement(
        'INSERT INTO regular_payroll_employees VALUES(?,?,?,?,?) '
        'ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,'
        'rate=excluded.rate,base_enabled=excluded.base_enabled',
        [business, employee, name, rate, weeklyBase ? 1 : 0],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_advances VALUES(?,?,0)', [business, employee],
      );
      _authorize();
    });
  }

  Future<void> createRecheck({
    required String operation, required String job, required String description,
    required String employee, required String name, required int rate,
    required int estimatedMinutes, Future<void> Function()? queueChange,
  }) async {
    _authorize();
    if ([operation, job, employee, name, description].any((value) => value.trim().isEmpty) ||
        rate <= 0 || estimatedMinutes < 0) {
      throw ArgumentError('Invalid recheck.');
    }
    await prepare();
    await db.transaction(() async {
      final source = await _read(
        'SELECT j.title FROM local_jobs j JOIN local_job_assignments a '
        'ON a.business_id=j.business_id AND a.job_id=j.id AND a.active=1 '
        'WHERE j.business_id=? AND j.id=? AND a.employee_id=?',
        [business, job, employee],
      );
      if (source.isEmpty) throw StateError('Save the job and mechanic assignment first.');
      final task = jsonEncode([job, 'recheck', operation]);
      final labor = jsonEncode(['recheck', operation]);
      final prior = await _read(
        'SELECT description,planned FROM regular_payroll_tasks WHERE business_id=? AND id=?',
        [business, task],
      );
      if (prior.isNotEmpty) {
        if (prior.single['description'] != description.trim() ||
            prior.single['planned'] != (estimatedMinutes * 100 + 30) ~/ 60) {
          throw StateError('Conflicting recheck retry.');
        }
        await queueChange?.call();
        return;
      }
      await db.customStatement(
        'INSERT INTO regular_payroll_employees VALUES(?,?,?,?,0) '
        'ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,rate=excluded.rate',
        [business, employee, name, rate],
      );
      await db.customStatement('INSERT OR IGNORE INTO regular_payroll_advances VALUES(?,?,0)',
        [business, employee]);
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_jobs VALUES(?,?,?)',
        [business, job, source.first['title']],
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_tasks VALUES(?,?,?,?,?,?)',
        [business, task, job, labor, description.trim(), (estimatedMinutes * 100 + 30) ~/ 60],
      );
      await db.customStatement(
        "INSERT INTO regular_payroll_task_sources VALUES(?,?,NULL,NULL,'recheck',1)", [business, task],
      );
      await _assign(task, employee);
      await queueChange?.call();
      _authorize();
    });
  }

  Future<void> setEstimatedMinutes(String task, String employee, int minutes) async {
    _authorize();
    if (minutes < 0 || minutes > 600000) throw ArgumentError('Invalid estimated minutes.');
    await prepare();
    await db.transaction(() async {
      final assignment = await _read(
        'SELECT id FROM regular_payroll_portions WHERE business_id=? AND task_id=? AND employee_id=?',
        [business, task, employee],
      );
      if (assignment.isEmpty) throw StateError('This mechanic is not assigned to the task.');
      await db.customStatement(
        'INSERT INTO regular_payroll_estimates VALUES(?,?,?,?) '
        'ON CONFLICT(business_id,task_id,employee_id) DO UPDATE SET minutes=excluded.minutes',
        [business, task, employee, minutes],
      );
      _authorize();
    });
  }

  Future<List<Map<String, dynamic>>> employees() async {
    _authorize();
    await prepare();
    return _read('SELECT * FROM regular_payroll_employees WHERE business_id=? ORDER BY id', [
      business,
    ]);
  }

  Future<List<Map<String, dynamic>>> assignedEmployees(String jobId) async {
    _authorize();
    await prepare();
    final rows = await _read(
      'SELECT DISTINCT a.employee_id, a.employee_name, e.name, e.rate '
      'FROM local_job_assignments a LEFT JOIN regular_payroll_employees e '
      'ON e.business_id=a.business_id AND e.id=a.employee_id '
      'WHERE a.business_id=? AND a.job_id=? AND a.active=1',
      [business, jobId],
    );
    _authorize();
    return rows;
  }

  /// Capture the actual Job, invoice line and assignment in one transaction.
  /// The caller supplies compensation from the authorized employee profile.
  Future<void> registerAssignedLabor({
    required String jobId,
    required String invoiceId,
    required String lineId,
    required String employeeId,
    required String employeeName,
    required int rateCents,
    Future<void> Function()? queueChange,
  }) async {
    _authorize();
    if (employeeName.trim().isEmpty || rateCents <= 0) {
      throw ArgumentError('A saved employee name and hourly rate are required');
    }
    await prepare();
    await db.transaction(() async {
      final line = await LocalPayrollWorkSource(db).resolve(
        businessId: business,
        jobId: jobId,
        invoiceId: invoiceId,
        lineId: lineId,
        employeeId: employeeId,
      );
      if (line == null) {
        throw StateError('Saved invoice labor or active assignment is missing');
      }
      final job = (await _read(
        'SELECT title FROM local_jobs WHERE business_id=? AND id=?',
        [business, jobId],
      )).single;
      final laborId = jsonEncode([invoiceId, lineId]);
      final sources = await _read(
        'SELECT task_id FROM regular_payroll_task_sources '
        'WHERE business_id=? AND invoice_id=? AND line_id=?',
        [business, invoiceId, lineId]);
      if (sources.length > 1) throw StateError('Conflicting invoice task identity.');
      final task = sources.isEmpty ? jsonEncode([jobId, invoiceId, lineId])
          : sources.single['task_id'] as String;
      final description = line['description']?.toString().trim() ?? '';
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_jobs VALUES(?,?,?)',
        [business, jobId, job['title']],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_tasks VALUES(?,?,?,?,?,0)',
        [business, task, jobId, laborId,
          description.isEmpty ? 'Invoice labor' : description],
      );
      final existing = await _read(
        'SELECT id FROM regular_payroll_portions WHERE business_id=? AND task_id=? AND employee_id=?',
        [business, task, employeeId],
      );
      if (existing.isNotEmpty) {
        await queueChange?.call();
        return;
      }
      await db.customStatement(
        'INSERT INTO regular_payroll_employees VALUES(?,?,?,?,0) '
        'ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,rate=excluded.rate',
        [business, employeeId, employeeName, rateCents],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_advances VALUES(?,?,0)',
        [business, employeeId],
      );
      await _assign(task, employeeId);
      await queueChange?.call();
      _authorize();
    });
  }

  Future<void> _assign(String task, String employee) async {
    _authorize();
    await prepare();
    await db.transaction(() async {
      final tasks = await _read(
        'SELECT * FROM regular_payroll_tasks WHERE business_id=? AND id=?',
        [business, task],
      );
      final staff = await _read(
        'SELECT * FROM regular_payroll_employees WHERE business_id=? AND id=?',
        [business, employee],
      );
      if (tasks.length != 1 || staff.length != 1)
        { throw StateError('Task or employee missing'); }
      final id = jsonEncode([task, employee]);
      await db.customStatement(
        "INSERT INTO regular_payroll_portions(business_id,id,task_id,employee_id,state) VALUES(?,?,?,?,'Open')",
        [business, id, task, employee],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_estimates VALUES(?,?,?,?)',
        [business, task, employee, ((tasks.single['planned'] as int) * 60 + 50) ~/ 100],
      );
      await LocalMechanicWorkCreditRepository(database: db).createAssignment(
        businessId: business, allocationId: id, jobId: tasks.single['job_id'] as String,
        laborLineId: tasks.single['labor_id'] as String, taskId: task, employeeId: employee,
        actualMinutes: 0,
        rateCents: staff.single['rate'] as int,
      );
    });
  }

  Future<List<Map<String, dynamic>>> assignmentSnapshots(String employee) async {
    _authorize();
    await prepare();
    final rows = await _read(
      'SELECT c.allocation_id AS credit,t.job_id AS job,c.rate_cents AS rate,'
      'c.task_id,c.job_id AS credit_job,c.labor_line_id AS credit_labor,'
      't.description,t.planned,s.invoice_id AS invoice,s.line_id AS line,'
      's.source_kind AS kind,s.active,e.minutes AS estimated_minutes '
      'FROM local_mechanic_work_credits_v1 c '
      'JOIN regular_payroll_tasks t ON t.business_id=c.business_id AND t.id=c.task_id '
      'JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id '
      'LEFT JOIN regular_payroll_estimates e ON e.business_id=c.business_id '
      'AND e.task_id=c.task_id AND e.employee_id=c.employee_id '
      'WHERE c.business_id=? AND c.employee_id=? ORDER BY c.allocation_id',
      [business, employee],
    );
    return rows.map((row) {
      final task = jsonDecode(jsonDecode(row['credit'] as String)[0] as String) as List;
      return {...row, 'employee': employee,
        if (row['kind'] == 'recheck') 'operation': task[2]};
    }).toList();
  }

  Future<List<Map<String, dynamic>>> mechanicWork({
    required String? job,
    required String employee,
    required void Function() assertSession,
  }) async {
    assertSession();
    if (pairedEmployee != null && pairedEmployee != employee) {
      throw StateError('Only the paired employee can view this work.');
    }
    await prepare();
    final rows = await _read(
      'SELECT c.allocation_id AS id,t.job_id,t.description,p.state,c.actual_minutes,c.revision '
      'FROM local_mechanic_work_credits_v1 c '
      'JOIN regular_payroll_portions p ON p.business_id=c.business_id AND p.id=c.allocation_id '
      'JOIN regular_payroll_tasks t ON t.business_id=p.business_id AND t.id=p.task_id '
      "WHERE c.business_id=? AND (?='' OR t.job_id=?) AND c.employee_id=? "
      "AND (p.state!='Open' OR NOT EXISTS(SELECT 1 FROM regular_payroll_task_sources s "
      'WHERE s.business_id=t.business_id AND s.task_id=t.id AND s.active=0)) '
      'AND (?=1 OR EXISTS (SELECT 1 FROM local_job_assignments a WHERE a.business_id=c.business_id '
      'AND a.job_id=t.job_id AND a.employee_id=c.employee_id AND a.active=1)) '
      'ORDER BY c.allocation_id',
      [business, job ?? '', job ?? '', employee, pairedEmployee == employee ? 1 : 0],
    );
    assertSession();
    return rows;
  }

  Future<void> updateMechanicWork({
    required String job,
    required String employee,
    required String id,
    required String state,
    required int minutes,
    required String date,
    required int expectedRevision,
    required void Function() assertSession,
    Future<void> Function()? queueChange,
  }) async {
    assertSession();
    await prepare();
    await db.transaction(() async {
      final rows = await mechanicWork(
        job: job, employee: employee, assertSession: assertSession,
      );
      final row = rows.where((row) => row['id'] == id).firstOrNull;
      final from = row?['state'];
      if (row == null || from == 'Done' ||
          (from == 'Open' && state != 'In Progress') ||
          (from == 'In Progress' && state != 'Done')) {
        throw StateError('This labor portion is unavailable.');
      }
      await _updateWork(
        id, state, minutes, date,
        expectedRevision: expectedRevision,
        authorize: assertSession,
      );
      await queueChange?.call();
    });
  }

  Future<({int unpaid, List<Map<String, dynamic>> receipts})> mechanicReport(
    String employee, void Function() assertLink,
  ) async {
    assertLink();
    if (owner || pairedEmployee != employee) {
      throw StateError('Only the paired employee can view these receipts.');
    }
    await prepare();
    final rows = await _read(
      'SELECT COALESCE(SUM((actual_minutes * rate_cents + 30)/60 - '
      '((COALESCE((SELECT SUM(x.minutes) FROM regular_payroll_work_coverage x '
      'WHERE x.business_id=local_mechanic_work_credits_v1.business_id '
      'AND x.credit_id=local_mechanic_work_credits_v1.allocation_id),0) * rate_cents + 30)/60)),0) AS unpaid '
      'FROM local_mechanic_work_credits_v1 WHERE business_id=? AND employee_id=? '
      'AND completed=1 AND paid_operation_id IS NULL',
      [business, employee],
    );
    final receipts = await _read(
      'SELECT operation_id,net,method,verified_date FROM regular_payroll_payments '
      'WHERE business_id=? AND employee_id=? ORDER BY verified_date DESC,operation_id',
      [business, employee],
    );
    assertLink();
    return (unpaid: rows.single['unpaid'] as int, receipts: receipts);
  }

  /// Apply only after the LAN transport validates the signed shop/employee
  /// envelope. The transport commits this change and the replay receipt together.
  Future<void> applyLanChange(
    PayrollLanOperation operation,
    Map<String, dynamic> payload, {
    required String employee,
    required void Function() assertLink,
  }) async {
    assertLink();
    if (payload['employee'] != employee) {
      throw StateError('Payroll change is for a different employee.');
    }
    await prepare();
    final job = payload['job'] as String?;
    switch (operation) {
      case PayrollLanOperation.progress:
        if (!owner) throw StateError('Only the Owner receives mechanic progress.');
        await updateMechanicWork(
          job: job!, employee: employee, id: payload['id'] as String,
          state: payload['state'] as String, minutes: payload['minutes'] as int,
          date: payload['date'] as String,
          expectedRevision: payload['revision'] as int, assertSession: assertLink,
        );
      case PayrollLanOperation.assignment:
        if (owner || pairedEmployee != employee || job == null) {
          throw StateError('Labor assignment is unavailable to this device.');
        }
        final isRecheck = payload['kind'] == 'recheck';
        final invoice = isRecheck ? 'recheck' : payload['invoice'] as String;
        final line = isRecheck ? payload['operation'] as String : payload['line'] as String;
        final labor = payload['credit_labor'] as String? ?? jsonEncode([invoice, line]);
        final task = payload['task_id'] as String? ?? jsonEncode([job, invoice, line]);
        final id = jsonEncode([task, employee]);
        final rate = payload['rate'] as int;
        final incomingRevision = payload['assignment_revision'] as int? ?? 0;
        await db.customStatement(
          'CREATE TABLE IF NOT EXISTS regular_payroll_assignment_incoming '
          '(business_id TEXT NOT NULL,credit TEXT NOT NULL,revision INTEGER NOT NULL,'
          'PRIMARY KEY(business_id,credit))');
        final previousRevision = await _read(
          'SELECT revision FROM regular_payroll_assignment_incoming '
          'WHERE business_id=? AND credit=?', [business, id]);
        if (previousRevision.isNotEmpty &&
            (previousRevision.single['revision'] as int) >= incomingRevision) { return; }
        await db.customStatement('INSERT INTO regular_payroll_assignment_incoming VALUES(?,?,?) '
          'ON CONFLICT(business_id,credit) DO UPDATE SET revision=excluded.revision',
          [business, id, incomingRevision]);
        await db.customStatement(
          'INSERT OR IGNORE INTO regular_payroll_jobs VALUES(?,?,?)',
          [business, job, job],
        );
        await db.customStatement(
          'INSERT INTO regular_payroll_tasks VALUES(?,?,?,?,?,?) '
          'ON CONFLICT(business_id,id) DO UPDATE SET description=excluded.description,planned=excluded.planned,job_id=excluded.job_id',
          [business, task, job, labor, payload['description'] as String, payload['planned'] as int? ?? 0],
        );
        await db.customStatement(
          'INSERT INTO regular_payroll_task_sources VALUES(?,?,?,?,?,?) '
          'ON CONFLICT(business_id,task_id) DO UPDATE SET active=excluded.active,invoice_id=excluded.invoice_id,line_id=excluded.line_id',
          [business, task, isRecheck ? null : invoice, isRecheck ? null : line,
            isRecheck ? 'recheck' : 'invoice', payload['active'] as int? ?? 1],
        );
        await db.customStatement(
          'INSERT OR IGNORE INTO regular_payroll_estimates VALUES(?,?,?,?)',
          [business, task, employee, payload['estimated_minutes'] as int? ?? 0],
        );
        final existing = await _read(
          'SELECT id FROM regular_payroll_portions WHERE business_id=? AND id=?',
          [business, id],
        );
        if (existing.isEmpty) {
          await db.customStatement(
            "INSERT INTO regular_payroll_portions(business_id,id,task_id,employee_id,state) VALUES(?,?,?,?,'Open')",
            [business, id, task, employee],
          );
          await LocalMechanicWorkCreditRepository(database: db).createAssignment(
            businessId: business, allocationId: id, jobId: payload['credit_job'] as String? ?? job,
            laborLineId: labor, taskId: task, employeeId: employee,
            actualMinutes: 0, rateCents: rate,
          );
        }
      case PayrollLanOperation.payment:
        if (owner || pairedEmployee != employee) {
          throw StateError('Payroll receipt is unavailable to this device.');
        }
        final operationId = payload['operation'] as String;
        final existing = await _read(
          'SELECT payload FROM regular_payroll_payments WHERE business_id=? AND operation_id=?',
          [business, operationId],
        );
        if (existing.isNotEmpty) {
          if (existing.single['payload'] != jsonEncode(payload)) {
            throw StateError('Conflicting payment receipt.');
          }
          return;
        }
        final ids = (payload['work'] as List).cast<String>();
        if (ids.toSet().length != ids.length) throw StateError('Duplicate receipt work.');
        final coverage = payload['coverage'];
        final entries = coverage is List
            ? coverage.map((row) => Map<String, dynamic>.from(row as Map)).toList()
            : [
                for (final id in ids) {'credit_id': id},
              ];
        if (entries.length != ids.length ||
            entries.any((row) => !ids.contains(row['credit_id'])) ||
            entries.map((row) => row['credit_id']).toSet().length != ids.length) {
          throw StateError('Receipt coverage does not match its work.');
        }
        final staged = <Map<String, dynamic>>[];
        for (final entry in entries) {
          final id = entry['credit_id'] as String;
          final rows = await _read(
            'SELECT c.* FROM local_mechanic_work_credits_v1 c '
            'WHERE c.business_id=? AND c.allocation_id=? AND c.employee_id=?',
            [business, id, employee],
          );
          if (rows.length != 1 || rows.single['completed'] != 1 ||
              rows.single['paid_operation_id'] != null) {
            throw StateError('Receipt conflicts with local payroll work.');
          }
          final credit = rows.single;
          final paid = (await _read(
            'SELECT COALESCE(SUM(minutes),0) AS minutes,COALESCE(SUM(amount),0) AS amount '
            'FROM regular_payroll_work_coverage WHERE business_id=? AND credit_id=?',
            [business, id],
          )).single;
          final priorMinutes = paid['minutes'] as int;
          final minutes = entry['minutes'] ?? credit['actual_minutes'];
          final total = credit['actual_minutes'] as int;
          if (minutes is! int || minutes <= 0 || minutes + priorMinutes > total) {
            throw StateError('Receipt exceeds remaining work.');
          }
          final snapshot = entry['snapshot'] as Map<String, dynamic>?;
          final paymentRate = snapshot?['payment_rate_cents'] ?? credit['rate_cents'];
          if (paymentRate is! int || paymentRate < 0 || paymentRate > 10000000) {
            throw StateError('Invalid receipt labor rate.');
          }
          final amount = (((priorMinutes + minutes) * paymentRate + 30) ~/ 60) -
              ((priorMinutes * paymentRate + 30) ~/ 60);
          if (entry['amount'] != null && entry['amount'] != amount) {
            throw StateError('Receipt work amount conflicts with this ledger.');
          }
          staged.add({
            'credit_id': id, 'minutes': minutes, 'amount': amount,
            'full': priorMinutes + minutes == total,
            'snapshot': jsonEncode({
              ...credit, 'id': id, 'description': 'Paid labor',
              'actual_minutes': minutes, 'gross_cents': amount,
              ...?snapshot,
            }),
          });
        }
        if (payload['gross'] is! int || payload['repayment'] is! int || payload['net'] is! int ||
            (payload['gross'] as int) < 0 || (payload['repayment'] as int) < 0 ||
            payload['net'] != (payload['gross'] as int) - (payload['repayment'] as int)) {
          throw StateError('Invalid receipt totals.');
        }
        await db.customStatement(
          'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
          [business, operationId, employee, payload['week'], jsonEncode(payload),
            payload['gross'], payload['repayment'], payload['net'],
            payload['method'], payload['date']],
        );
        for (final entry in staged) {
          await db.customStatement(
            'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
            [business, entry['credit_id'], operationId, entry['minutes'], entry['amount'], entry['snapshot']],
          );
          if (entry['full'] == true) {
            await db.customStatement(
              'UPDATE local_mechanic_work_credits_v1 SET paid_operation_id=? '
              'WHERE business_id=? AND allocation_id=? AND employee_id=?',
              [operationId, business, entry['credit_id'], employee],
            );
          }
        }

    }
    assertLink();
  }

  /// Editing or reopening an unpaid portion increments its version. Paid
  /// portions require a new recheck labor line; their original hours stay frozen.
  Future<void> updateWork(
    String id,
    String state,
    int hours,
    String date, {
    int? expectedRevision,
  }) {
    if (hours < 0) throw ArgumentError('Invalid work hours');
    return _updateWork(
      id, state, (hours * 60 + 50) ~/ 100, date,
      expectedRevision: expectedRevision,
      authorize: _authorize,
    );
  }

  Future<void> _updateWork(
    String id,
    String state,
    int minutes,
    String date, {
    required int? expectedRevision,
    required void Function() authorize,
  }) async {
    authorize();
    await prepare();
    _date(date);
    if (!['Open', 'In Progress', 'Done'].contains(state) || minutes < 0)
      { throw ArgumentError('Invalid work'); }
    await db.transaction(() async {
      final rows = await _read(
        'SELECT c.*,p.state FROM local_mechanic_work_credits_v1 c JOIN regular_payroll_portions p ON p.business_id=c.business_id AND p.id=c.allocation_id WHERE c.business_id=? AND c.allocation_id=?',
        [business, id],
      );
      if (rows.length != 1 || rows.single['paid_operation_id'] != null)
        { throw StateError('Missing or paid work; add a recheck'); }
      if (rows.single['state'] == 'Open') {
        final removed = await _read(
          'SELECT task_id FROM regular_payroll_task_sources '
          'WHERE business_id=? AND task_id=? AND active=0',
          [business, rows.single['task_id'] as String],
        );
        if (removed.isNotEmpty) {
          throw StateError('This invoice labor was removed. Add a separate task for new work.');
        }
      }
      if (expectedRevision != null && rows.single['revision'] != expectedRevision) {
        throw StateError('Work changed. Refresh before updating it.');
      }
      if (state == 'Done' && rows.single['state'] == 'Open')
        { throw StateError('Start work before completion'); }
      await LocalMechanicWorkCreditRepository(database: db).recordWork(
        businessId: business, allocationId: id, employeeId: rows.single['employee_id'] as String,
        expectedRevision: rows.single['revision'] as int,
        actualMinutes: minutes, completed: state == 'Done',
      );
      await db.customStatement(
        'UPDATE regular_payroll_portions SET state=?,version=version+1,completed_date=? WHERE business_id=? AND id=?',
        [state, state == 'Done' ? date : null, business, id],
      );
      authorize();
    });
  }

  Future<List<Map<String, dynamic>>> jobs() async {
    _authorize();
    await prepare();
    return _read(
      '''SELECT j.*,count(t.id) total, coalesce(sum(CASE WHEN EXISTS(SELECT 1 FROM regular_payroll_portions p WHERE p.business_id=t.business_id AND p.task_id=t.id) AND NOT EXISTS(SELECT 1 FROM regular_payroll_portions p WHERE p.business_id=t.business_id AND p.task_id=t.id AND p.state!='Done') THEN 1 ELSE 0 END),0) done,
    (SELECT count(*) FROM regular_payroll_portions p JOIN regular_payroll_tasks x ON x.business_id=p.business_id AND x.id=p.task_id WHERE x.business_id=j.business_id AND x.job_id=j.id AND p.state!='Open') started
    FROM regular_payroll_jobs j LEFT JOIN regular_payroll_tasks t ON t.business_id=j.business_id AND t.job_id=j.id WHERE j.business_id=? GROUP BY j.id ORDER BY j.id''',
      [business],
    );
  }

  Future<List<Map<String, dynamic>>> tasks() async {
    _authorize();
    await prepare();
    return _read(
      'SELECT t.*,j.job_number,j.customer_name,j.vehicle_label,s.source_kind,s.active AS source_active,'
      's.invoice_id FROM regular_payroll_tasks t '
      'LEFT JOIN local_jobs j ON j.business_id=t.business_id AND j.id=t.job_id '
      'LEFT JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id '
      'WHERE t.business_id=? ORDER BY t.id', [business],
    );
  }

  Future<List<Map<String, dynamic>>> work({String? employee, String? job}) async {
    _authorize();
    await prepare();
    final rows = await _read(
      "SELECT p.business_id,p.id,p.task_id,p.employee_id,e.name AS employee_name,"
      "p.state,p.completed_date,c.revision AS version,t.description,t.job_id,"
      "j.job_number,j.customer_name,j.vehicle_label,c.completed AS credit_completed,"
      "s.source_kind,s.active AS source_active,s.invoice_id,"
      "COALESCE(est.minutes,0) AS estimated_minutes,"
      "c.actual_minutes,c.rate_cents,"
      "COALESCE((SELECT SUM(x.minutes) FROM regular_payroll_work_coverage x "
      "WHERE x.business_id=c.business_id AND x.credit_id=c.allocation_id),"
      "CASE WHEN c.paid_operation_id IS NOT NULL THEN c.actual_minutes ELSE 0 END) AS paid_minutes,"
      "COALESCE((SELECT SUM(x.amount) FROM regular_payroll_work_coverage x "
      "WHERE x.business_id=c.business_id AND x.credit_id=c.allocation_id),"
      "CASE WHEN c.paid_operation_id IS NOT NULL THEN (c.actual_minutes*c.rate_cents+30)/60 ELSE 0 END) AS paid_cents "
      "FROM regular_payroll_portions p "
      "JOIN regular_payroll_tasks t ON t.business_id=p.business_id AND t.id=p.task_id "
      "JOIN local_mechanic_work_credits_v1 c ON c.business_id=p.business_id AND c.allocation_id=p.id "
      "JOIN regular_payroll_employees e ON e.business_id=p.business_id AND e.id=p.employee_id "
      "LEFT JOIN local_jobs j ON j.business_id=t.business_id AND j.id=t.job_id "
      "LEFT JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id "
      "LEFT JOIN regular_payroll_estimates est ON est.business_id=p.business_id "
      "AND est.task_id=p.task_id AND est.employee_id=p.employee_id "
      "WHERE p.business_id=? ${employee == null ? '' : 'AND p.employee_id=?'} "
      "${job == null ? '' : 'AND t.job_id=?'} ORDER BY p.id",
      [business, ?employee, ?job],
    );
    _authorize();
    return rows.map((row) {
      final total = row['actual_minutes'] as int;
      final paid = row['paid_minutes'] as int;
      final rate = row['rate_cents'] as int;
      if (paid < 0 || paid > total) throw StateError('Conflicting payroll coverage.');
      final remaining = total - paid;
      return {
        ...row, 'hours_hundredths': (total * 100 + 30) ~/ 60,
        'remaining_minutes': remaining,
        'remaining_cents': ((total * rate + 30) ~/ 60) - ((paid * rate + 30) ~/ 60),
        'gross_cents': (total * rate + 30) ~/ 60,
        'paid': total > 0 && remaining == 0 ? 1 : 0,
        'pay_status': paid == 0 ? 'Unpaid' : remaining == 0 ? 'Paid' : 'Partially Paid',
      };
    }).toList();
  }

  Future<void> enableWeeklyBase(String employee, String name) async {
    _authorize();
    if (employee.isEmpty || name.trim().isEmpty) {
      throw ArgumentError('Employee identity is required.');
    }
    await prepare();
    await db.transaction(() async {
      await _assertPaymentAuthority();
      await db.customStatement(
        'INSERT INTO regular_payroll_employees VALUES(?,?,?,0,1) '
        'ON CONFLICT(business_id,id) DO UPDATE SET base_enabled=1',
        [business, employee, name],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_advances VALUES(?,?,0)',
        [business, employee],
      );
      _authorize();
    });
  }

  Future<Map<String, dynamic>?> weeklyDefaults(String employee) async {
    _authorize();
    await prepare();
    final rows = await _read(
      'SELECT base_cents,hourly_cents,adjustment_cents,add_labor '
      'FROM regular_payroll_weekly_defaults WHERE business_id=? AND employee_id=?',
      [business, employee],
    );
    _authorize();
    return rows.firstOrNull;
  }

  Future<void> saveWeeklyDefaults(
    String employee, int base, int hourly, int adjustment, bool addLabor,
  ) async {
    _authorize();
    if (employee.isEmpty || base < 0 || hourly < 0) {
      throw ArgumentError('Enter valid weekly amounts.');
    }
    await prepare();
    await db.transaction(() async {
      _authorize();
      await db.customStatement(
        'INSERT INTO regular_payroll_weekly_defaults VALUES(?,?,?,?,?,?) '
        'ON CONFLICT(business_id,employee_id) DO UPDATE SET '
        'base_cents=excluded.base_cents,hourly_cents=excluded.hourly_cents,'
        'adjustment_cents=excluded.adjustment_cents,add_labor=excluded.add_labor',
        [business, employee, base, hourly, adjustment, addLabor ? 1 : 0],
      );
      _authorize();
    });
  }

  Future<List<Map<String, dynamic>>> shopTasks([String? employee]) async {
    _authorize();
    await prepare();
    final rows = await _read(
      'SELECT id, employee_id, description, category, due_at, status FROM regular_payroll_shop_tasks '
      'WHERE business_id=? ${employee == null ? '' : 'AND employee_id=?'} ORDER BY id DESC',
      [business, ?employee],
    );
    _authorize();
    return rows;
  }

  Future<void> addShopTask(
    String employee, String description, String category, {DateTime? due}
  ) async {
    _authorize();
    if (employee.isEmpty || description.trim().isEmpty) {
      throw ArgumentError('Employee and task description are required.');
    }
    await prepare();
    await db.transaction(() async {
      _authorize();
      await db.customStatement(
        'INSERT INTO regular_payroll_shop_tasks (business_id,employee_id,description,category,due_at) '
        'VALUES (?,?,?,?,?)', [business, employee, description.trim(), category, due?.millisecondsSinceEpoch],
      );
      _authorize();
    });
  }

  Future<void> setShopTaskStatus(String employee, int id, String status) async {
    _authorize();
    if (!['planned', 'in_progress', 'done'].contains(status)) {
      throw ArgumentError('Unknown task status.');
    }
    await prepare();
    await db.transaction(() async {
      _authorize();
      await db.customStatement(
        'UPDATE regular_payroll_shop_tasks SET status=? WHERE business_id=? AND employee_id=? AND id=?',
        [status, business, employee, id],
      );
      _authorize();
    });
  }

  Future<int> advance(String employee) async {
    _authorize();
    await prepare();
    final r = await _read(
      'SELECT balance FROM regular_payroll_advances WHERE business_id=? AND employee_id=?',
      [business, employee],
    );
    return r.firstOrNull?['balance'] as int? ?? 0;
  }

  Future<void> addAdvance(String employee, int amount) async {
    _authorize();
    await prepare();
    if (amount <= 0) { throw ArgumentError('Positive advance required'); }
    await db.transaction(() async {
      if ((await _read(
        'SELECT id FROM regular_payroll_employees WHERE business_id=? AND id=?',
        [business, employee],
      )).isEmpty)
        { throw StateError('Employee missing'); }
      await db.customStatement(
        'UPDATE regular_payroll_advances SET balance=balance+? WHERE business_id=? AND employee_id=?',
        [amount, business, employee],
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) VALUES(?,?,?,?)',
        [
          business,
          'advance-${DateTime.now().microsecondsSinceEpoch}',
          'advance',
          jsonEncode({'employee': employee, 'amount': amount}),
        ],
      );
    });
  }

  Future<void> recordOpeningAdvance(String employee, int cents) async {
    _authorize();
    if (cents <= 0) throw ArgumentError('Enter a positive opening amount.');
    await prepare();
    await db.transaction(() async {
      await _assertPaymentAuthority();
      if (await advance(employee) != 0 ||
          (await history(employee)).isNotEmpty ||
          (await repaymentHistory(employee)).isNotEmpty) {
        throw StateError('An opening amount cannot replace existing payroll history.');
      }
      await db.customStatement(
        'INSERT INTO regular_payroll_advances VALUES(?,?,?) '
        'ON CONFLICT(business_id,employee_id) DO UPDATE SET balance=excluded.balance',
        [business, employee, cents],
      );
      await db.customStatement(
        "INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) "
        "VALUES(?,?,'opening_advance',?)",
        [business, 'opening-advance-$employee',
          jsonEncode({'employee': employee, 'cents': cents})],
      );
      _authorize();
    });
  }

  Future<int?> openingAdvance(String employee) async {
    _authorize();
    await prepare();
    final rows = await _read(
      "SELECT payload FROM regular_payroll_audit WHERE business_id=? "
      "AND event='opening_advance' AND operation_id=?",
      [business, 'opening-advance-$employee'],
    );
    _authorize();
    final row = rows.firstOrNull;
    return row == null ? null :
        (jsonDecode(row['payload'] as String) as Map)['cents'] as int;
  }

  Future<void> recordRepayment({
    required String employee,
    required String operation,
    required int amount,
    required String date,
    required String method,
    required String note,
  }) async {
    _authorize();
    _date(date);
    if (operation.isEmpty || amount <= 0 ||
        !['Cash', 'Zelle', 'Check', 'ACH'].contains(method)) {
      throw ArgumentError('Enter a positive repayment and a valid payment method.');
    }
    await prepare();
    await db.transaction(() async {
      await _assertPaymentAuthority();
      final prior = await _read(
        "SELECT payload FROM regular_payroll_audit WHERE business_id=? "
        "AND operation_id=? AND event='standalone_repayment'",
        [business, operation],
      );
      final fields = {
        'employee': employee, 'cents': amount, 'date': date,
        'method': method, 'note': note,
      };
      if (prior.isNotEmpty) {
        final recorded = jsonDecode(prior.single['payload'] as String) as Map;
        if (fields.entries.any((entry) => recorded[entry.key] != entry.value)) {
          throw StateError('Conflicting repayment retry.');
        }
        return;
      }
      final balance = await advance(employee);
      if (amount > balance) throw StateError('Repayment exceeds the balance.');
      final remaining = balance - amount;
      await db.customStatement(
        'UPDATE regular_payroll_advances SET balance=? WHERE business_id=? AND employee_id=?',
        [remaining, business, employee],
      );
      await db.customStatement(
        "INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) "
        "VALUES(?,?,'standalone_repayment',?)",
        [business, operation, jsonEncode({...fields, 'remaining_after_cents': remaining})],
      );
      _authorize();
    });
  }

  Future<List<Map<String, dynamic>>> repaymentHistory(String employee) async {
    _authorize();
    await prepare();
    final rows = await _read(
      "SELECT payload FROM regular_payroll_audit WHERE business_id=? "
      "AND event='standalone_repayment' AND json_extract(payload,'\$.employee')=? ORDER BY id DESC",
      [business, employee],
    );
    _authorize();
    return [
      for (final row in rows)
        Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
    ];
  }

  Future<List<Map<String, dynamic>>> history(String employee) async {
    _authorize();
    await prepare();
    return _read(
      'SELECT p.*, o.state AS reconciliation_state FROM regular_payroll_payments p '
      'LEFT JOIN regular_payroll_sync_outbox o ON o.business_id=p.business_id '
      'AND o.operation_id=p.operation_id WHERE p.business_id=? AND p.employee_id=? '
      'ORDER BY p.verified_date DESC,p.operation_id DESC',
      [business, employee],
    );
  }

  /// Read the settlement and its frozen allocations together. Grouping by
  /// payment date would mix disbursements from different payroll weeks.
  Future<List<Map<String, dynamic>>> historyWithWork(String employee) async {
    _authorize();
    await prepare();
    return db.transaction(() async {
      final payments = await history(employee);
      final result = <Map<String, dynamic>>[];
      for (final payment in payments) {
        final rows = await _read(
          'SELECT credit_id, snapshot FROM regular_payroll_work_coverage '
          'WHERE business_id=? AND operation_id=? ORDER BY credit_id',
          [business, payment['operation_id'] as String],
        );
        final work = <Map<String, dynamic>>[];
        for (final row in rows) {
          final snapshot = Map<String, dynamic>.from(
            jsonDecode(row['snapshot'] as String) as Map,
          );
          final taskId = snapshot['task_id'];
          // Older snapshots may predate the encoded invoice linkage.
          Object? task;
          if (taskId is String) {
            try {
              task = jsonDecode(taskId);
            } on FormatException {
              task = null;
            }
          }
          final source = taskId is String ? (await _read(
            'SELECT t.job_id,s.invoice_id,s.source_kind FROM regular_payroll_tasks t '
            'LEFT JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id '
            'WHERE t.business_id=? AND t.id=?', [business, taskId],
          )).firstOrNull : null;
          final jobId = source?['job_id'] ?? snapshot['job_id'];
          final job = jobId is String ? (await _read(
            'SELECT id, job_number, vehicle_label FROM local_jobs '
            'WHERE business_id=? AND id=?', [business, jobId],
          )).firstOrNull : null;
          final invoiceIdentity = source?['invoice_id'] ??
              (task is List && task.length == 3 ? task[1] : null);
          final invoice = (source?['source_kind'] ?? snapshot['source_kind']) != 'recheck' && invoiceIdentity is String &&
              jobId is String && (source != null ||
                (task is List && task.length == 3 && task[0] == jobId))
              ? (await _read(
                  "SELECT id AS invoice_id, document_number FROM local_documents "
                  "WHERE business_id=? AND id=? AND job_id=? AND kind='invoice'",
                  [business, invoiceIdentity, jobId],
                )).firstOrNull
              : null;
          work.add({
            ...snapshot,
            'job_id': job?['id'],
            'job_number': job?['job_number'],
            'vehicle_label': job?['vehicle_label'],
            ...?invoice,
            'credit_id': row['credit_id'],
            'operation_id': payment['operation_id'],
            'method': payment['method'],
            'verified_date': payment['verified_date'],
          });
        }
        result.add({...payment, 'work': work});
      }
      _authorize();
      return result;
    });
  }

  Future<List<Map<String, dynamic>>> recordedCoverage(String employee, String operation) async {
    _authorize();
    await prepare();
    if ((await _read(
      'SELECT operation_id FROM regular_payroll_payments '
      'WHERE business_id=? AND operation_id=? AND employee_id=?',
      [business, operation, employee],
    )).length != 1) {
      throw StateError('Payment receipt is missing.');
    }
    final rows = await _read(
      'SELECT credit_id,minutes,amount,snapshot FROM regular_payroll_work_coverage '
      'WHERE business_id=? AND operation_id=? ORDER BY credit_id',
      [business, operation],
    );
    _authorize();
    return [
      for (final row in rows) {
        ...row,
        'snapshot': Map<String, dynamic>.from(jsonDecode(row['snapshot'] as String) as Map),
      },
    ];
  }

  /// Install a verified, non-transferable payment authority. This is for
  /// trusted LAN enrollment, never self-election by a disconnected device.
  Future<void> bindPaymentAuthority({
    required String writerDeviceId,
    required void Function() assertVerifiedPairing,
  }) async {
    _authorize();
    assertVerifiedPairing();
    if (writerDeviceId.trim().isEmpty) {
      throw ArgumentError('A verified payroll device is required.');
    }
    await prepare();
    await db.transaction(() async {
      assertVerifiedPairing();
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_payment_authority VALUES(?,?)',
        [business, writerDeviceId],
      );
      final saved = await _read(
        'SELECT device_id FROM regular_payroll_payment_authority WHERE business_id=?',
        [business],
      );
      if (saved.single['device_id'] != writerDeviceId) {
        throw StateError('Conflicting payroll authority. Payments are not transferable.');
      }
      _authorize();
    });
  }

  Future<void> _assertPaymentAuthority() async {
    await assertLanWriter?.call();
    final saved = await _read(
      'SELECT device_id FROM regular_payroll_payment_authority WHERE business_id=?',
      [business],
    );
    if (deviceId == null || saved.length != 1 ||
        saved.single['device_id'] != deviceId) {
      throw StateError('Only the enrolled payroll device can record payments.');
    }
  }

  /// Sends immutable receipts by their original operation IDs. A failed or
  /// interrupted delivery remains pending, including after an app restart.
  Future<int> reconcile({
    required Future<Map<String, dynamic>> Function(
      String operation, Map<String, dynamic> payload,
    ) send,
  }) async {
    _authorize();
    await prepare();
    final pending = await _read(
      "SELECT operation_id,payload FROM regular_payroll_sync_outbox "
      "WHERE business_id=? AND state='held_local' ORDER BY operation_id",
      [business],
    );
    var acknowledged = 0;
    for (final row in pending) {
      _authorize();
      final operation = row['operation_id'] as String;
      final payload = row['payload'] as String;
      final reply = await send(
        operation,
        Map<String, dynamic>.from(jsonDecode(payload) as Map),
      );
      if (reply['operation_id'] != operation || reply['status'] != 'recorded') {
        throw StateError('Payroll reconciliation returned an invalid receipt.');
      }
      await db.transaction(() async {
        _authorize();
        await db.customStatement(
          "UPDATE regular_payroll_sync_outbox SET state='reconciled' "
          "WHERE business_id=? AND operation_id=? AND payload=? AND state='held_local'",
          [business, operation, payload],
        );
        _authorize();
      });
      acknowledged++;
    }
    return acknowledged;
  }

  void _date(String value) {
    final d = DateTime.tryParse(value);
    if (d == null || d.toIso8601String().substring(0, 10) != value)
      { throw ArgumentError('Use YYYY-MM-DD'); }
  }

  /// The selected versions, hours and rates are part of the exact replay
  /// payload. Same-ID/same-content retries return false; any conflict fails.
  Future<bool> verify({
    required String operation,
    required String employee,
    required String week,
    required String date,
    required String method,
    required List<Map<String, dynamic>> selected,
    required int base,
    required int hourlyAdjustment,
    required String adjustmentReason,
    required int repayment,
    required int confirmedNet,
    Future<void> Function()? beforeCommit,
  }) async {
    _authorize();
    await prepare();
    _date(week);
    _date(date);
    if (DateTime.parse(week).weekday != DateTime.monday ||
        operation.isEmpty ||
        !['Cash', 'Zelle', 'Check', 'ACH', 'Card', 'Other'].contains(method) ||
        base < 0 ||
        repayment < 0 ||
        confirmedNet < 0 ||
        (selected.isEmpty && base == 0) ||
        (hourlyAdjustment != 0 && adjustmentReason.trim().isEmpty))
      { throw ArgumentError('Invalid verification'); }
    final picked =
        selected
            .map(
              (w) => <String, dynamic>{
                'id': w['id'],
                'version': w['version'],
                'hours': w['hours_hundredths'],
                'minutes': w['actual_minutes'],
                'rate': w['rate_cents'],
                if (w.containsKey('pay_minutes')) 'pay_minutes': w['pay_minutes'],
                if (w.containsKey('paid_minutes')) 'paid_minutes': w['paid_minutes'],
                if (w.containsKey('payment_rate_cents')) 'payment_rate_cents': w['payment_rate_cents'],
              },
            )
            .toList()
          ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    if (picked.map((p) => p['id']).toSet().length != picked.length)
      { throw StateError('Duplicate credit'); }
    final payload = jsonEncode({
      'employee': employee,
      'week': week,
      'date': date,
      'method': method,
      'work': picked,
      'base': base,
      'adjustment': hourlyAdjustment,
      'reason': adjustmentReason,
      'repayment': repayment,
      'confirmed_net': confirmedNet,
    });
    return db.transaction(() async {
      await _assertPaymentAuthority();
      final prior = await _read(
        'SELECT payload FROM regular_payroll_payments WHERE business_id=? AND operation_id=?',
        [business, operation],
      );
      if (prior.isNotEmpty) {
        if (prior.single['payload'] != payload)
          { throw StateError('Conflicting replay'); }
        return false;
      }
      final weeklyPayments = await _read(
        'SELECT operation_id FROM regular_payroll_payments '
        'WHERE business_id=? AND employee_id=? AND week=?',
        [business, employee, week],
      );
      final recordedBase = await _read(
        'SELECT operation_id FROM regular_payroll_paid_base '
        'WHERE business_id=? AND employee_id=? AND week=?',
        [business, employee, week],
      );
      if (base > 0 && (recordedBase.isNotEmpty || weeklyPayments.isNotEmpty)) {
        throw StateError('This employee already has a settlement for that week.');
      }
      final staff = await _read(
        'SELECT * FROM regular_payroll_employees WHERE business_id=? AND id=?',
        [business, employee],
      );
      if (staff.length != 1 || (base > 0 && staff.single['base_enabled'] != 1))
        { throw StateError('Base not allowed for employee'); }
      final current = await work(employee: employee);
      if (base > 0 && selected.isEmpty) {
        final nextWeek = DateTime.parse(week).add(const Duration(days: 7));
        final unpaidWork = current.any((row) {
          final date = DateTime.tryParse(row['completed_date']?.toString() ?? '');
          return row['paid'] != 1 && (date == null || date.isBefore(nextWeek));
        });
        if (unpaidWork) {
          throw StateError('Link this employee’s outstanding labor credits before recording weekly pay.');
        }
      }
      var gross = base + hourlyAdjustment;
      final snapshots = <String>[];
      for (final p in picked) {
        final match = current.where((w) => w['id'] == p['id']).toList();
        if (match.length != 1) { throw StateError('Missing work'); }
        final w = match.single;
        if (w['state'] != 'Done' ||
            w['credit_completed'] != 1 ||
            w['paid'] != 0 ||
            (p.containsKey('paid_minutes') && w['paid_minutes'] != p['paid_minutes']) ||
            w['version'] != p['version'] ||
            w['hours_hundredths'] != p['hours'] ||
            w['actual_minutes'] != p['minutes'] ||
            w['rate_cents'] != p['rate'])
          { throw StateError('Work changed or already paid'); }
        final completed = DateTime.parse(w['completed_date'] as String);
        final start = DateTime.parse(week);
        if ((completed.isBefore(start) ||
                !completed.isBefore(start.add(const Duration(days: 7)))) &&
            adjustmentReason.trim().isEmpty)
          { throw StateError(
            'Outside-week work requires an Owner override reason',
          ); }
        final remaining = w['remaining_minutes'] as int;
        final minutes = p['pay_minutes'] ?? remaining;
        if (minutes is! int || minutes <= 0 || minutes > remaining) {
          throw StateError('Select positive unpaid minutes for each work credit.');
        }
        final previouslyPaid = w['paid_minutes'] as int;
        // Cumulative rounding ensures several partial payments equal one
        // full payment, including credits with fractional cents per minute.
        final paymentRate = p['payment_rate_cents'] ?? p['rate'];
        if (paymentRate is! int || paymentRate < 0 || paymentRate > 10000000 ||
            (paymentRate != p['rate'] && adjustmentReason.trim().isEmpty)) {
          throw StateError('An adjusted labor rate requires an Owner reason.');
        }
        final amount = (((previouslyPaid + minutes) * paymentRate + 30) ~/ 60) -
            ((previouslyPaid * paymentRate + 30) ~/ 60);
        gross += amount;
        snapshots.add(jsonEncode({
          ...w, 'employee_name': staff.single['name'],
          'actual_minutes': minutes, 'hours_hundredths': (minutes * 100 + 30) ~/ 60,
          'gross_cents': amount, 'payment_rate_cents': paymentRate,
        }));
      }
      if (gross < 0 ||
          repayment > gross ||
          repayment > await advance(employee) ||
          confirmedNet != gross - repayment)
        { throw StateError('Amount or repayment changed'); }
      if (base > 0)
        { await db.customStatement('INSERT INTO regular_payroll_paid_base VALUES(?,?,?,?,?)', [
          business,
          employee,
          week,
          operation,
          base,
        ]); }
      await db.customStatement(
        'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          business,
          operation,
          employee,
          week,
          payload,
          gross,
          repayment,
          gross - repayment,
          method,
          date,
        ],
      );
      for (var i = 0; i < picked.length; i++) {
        final snapshot = jsonDecode(snapshots[i]) as Map<String, dynamic>;
        await db.customStatement(
          'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
          [business, picked[i]['id'], operation, snapshot['actual_minutes'],
            snapshot['gross_cents'], snapshots[i]],
        );
        final total = await _read(
          'SELECT SUM(minutes) AS minutes FROM regular_payroll_work_coverage '
          'WHERE business_id=? AND credit_id=?',
          [business, picked[i]['id'] as String],
        );
        if (total.single['minutes'] == picked[i]['minutes']) {
          await db.customStatement(
            'UPDATE local_mechanic_work_credits_v1 SET paid_operation_id=? '
            'WHERE business_id=? AND allocation_id=?',
            [operation, business, picked[i]['id']],
          );
        }
      }
      await db.customStatement(
        'UPDATE regular_payroll_advances SET balance=balance-? WHERE business_id=? AND employee_id=?',
        [repayment, business, employee],
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) VALUES(?,?,?,?)',
        [business, operation, 'verify_payment', payload],
      );
      // Keep payroll reconciliation separate from ordinary shop sync.
      await db.customStatement(
        'INSERT INTO regular_payroll_sync_outbox(business_id,operation_id,payload) VALUES(?,?,?)',
        [business, operation, payload],
      );
      if (beforeCommit != null) { await beforeCommit(); }
      await _assertPaymentAuthority();
      _authorize();
      return true;
    });
  }
}
