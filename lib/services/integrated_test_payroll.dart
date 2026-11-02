import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'local_mechanic_work_credit_repository.dart';

/// Local integration harness. Requires an explicitly supplied isolated database.
/// No production database defaults, server client, or financial posting path.
class IntegratedTestPayroll {
  IntegratedTestPayroll(
    this.db, {
    this.business = 'isolated-payroll-test',
    this.owner = true,
  });
  final BriskersLocalDatabase db;
  final String business;
  final bool owner;
  Future<void>? _prepared;
  void _authorize() {
    if (!owner || business.trim().isEmpty)
      { throw StateError('Local TEST Owner required'); }
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
    for (final sql in [
      '''CREATE TABLE IF NOT EXISTS it_jobs (business_id TEXT NOT NULL, id TEXT NOT NULL, label TEXT NOT NULL, PRIMARY KEY(business_id,id))''',
      '''CREATE TABLE IF NOT EXISTS it_tasks (business_id TEXT NOT NULL, id TEXT NOT NULL, job_id TEXT NOT NULL, labor_id TEXT NOT NULL, description TEXT NOT NULL, planned INTEGER NOT NULL CHECK(planned>=0), PRIMARY KEY(business_id,id), UNIQUE(business_id,job_id,labor_id))''',
      '''CREATE TABLE IF NOT EXISTS it_portions (business_id TEXT NOT NULL, id TEXT NOT NULL, task_id TEXT NOT NULL, employee_id TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('Open','In Progress','Done')), version INTEGER NOT NULL DEFAULT 0, completed_date TEXT, PRIMARY KEY(business_id,id), UNIQUE(business_id,task_id,employee_id))''',
      '''CREATE TABLE IF NOT EXISTS it_employees (business_id TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL, rate INTEGER NOT NULL CHECK(rate>=0), base_enabled INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(business_id,id))''',
      '''CREATE TABLE IF NOT EXISTS it_advances (business_id TEXT NOT NULL, employee_id TEXT NOT NULL, balance INTEGER NOT NULL CHECK(balance>=0), PRIMARY KEY(business_id,employee_id))''',
      '''CREATE TABLE IF NOT EXISTS it_payments (business_id TEXT NOT NULL, operation_id TEXT NOT NULL, employee_id TEXT NOT NULL, week TEXT NOT NULL, payload TEXT NOT NULL, gross INTEGER NOT NULL, repayment INTEGER NOT NULL, net INTEGER NOT NULL, method TEXT NOT NULL, verified_date TEXT NOT NULL, PRIMARY KEY(business_id,operation_id))''',
      '''CREATE TABLE IF NOT EXISTS it_paid_work (business_id TEXT NOT NULL, credit_id TEXT NOT NULL, operation_id TEXT NOT NULL, snapshot TEXT NOT NULL, PRIMARY KEY(business_id,credit_id))''',
      '''CREATE TABLE IF NOT EXISTS it_paid_base (business_id TEXT NOT NULL, employee_id TEXT NOT NULL, week TEXT NOT NULL, operation_id TEXT NOT NULL, amount INTEGER NOT NULL, PRIMARY KEY(business_id,employee_id,week))''',
      '''CREATE TABLE IF NOT EXISTS it_audit (id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL, operation_id TEXT NOT NULL, event TEXT NOT NULL, payload TEXT NOT NULL)''',
      '''CREATE TABLE IF NOT EXISTS it_sync_outbox (business_id TEXT NOT NULL, operation_id TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'blocked_test', attempts INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(business_id,operation_id))''',
      '''CREATE TRIGGER IF NOT EXISTS it_credit_frozen_update BEFORE UPDATE ON local_mechanic_work_credits_v1 WHEN OLD.paid_operation_id IS NOT NULL AND EXISTS(SELECT 1 FROM it_paid_work WHERE business_id=OLD.business_id AND credit_id=OLD.allocation_id) BEGIN SELECT RAISE(ABORT,'Paid credit is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS it_credit_frozen_delete BEFORE DELETE ON local_mechanic_work_credits_v1 WHEN EXISTS(SELECT 1 FROM it_paid_work WHERE business_id=OLD.business_id AND credit_id=OLD.allocation_id) BEGIN SELECT RAISE(ABORT,'Paid credit is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS it_paid_work_frozen_update BEFORE UPDATE ON it_paid_work BEGIN SELECT RAISE(ABORT,'Paid work is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS it_paid_work_frozen_delete BEFORE DELETE ON it_paid_work BEGIN SELECT RAISE(ABORT,'Paid work is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS it_payments_frozen_update BEFORE UPDATE ON it_payments BEGIN SELECT RAISE(ABORT,'Payment is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS it_payments_frozen_delete BEFORE DELETE ON it_payments BEGIN SELECT RAISE(ABORT,'Payment is immutable'); END''',
    ]) {
      await db.customStatement(sql);
    }
  }

  Future<void> initializeEmployees() async {
    _authorize();
    await prepare();
    await db.transaction(() async {
      for (final e in [
        ('chris', 'Chris TEST', 4000, 0),
        ('kam', 'Kam TEST', 3500, 0),
        ('base', 'Weekly Base TEST', 2500, 1),
      ]) {
        await db.customStatement(
          'INSERT OR IGNORE INTO it_employees VALUES(?,?,?,?,?)',
          [business, e.$1, e.$2, e.$3, e.$4],
        );
        await db.customStatement(
          'INSERT OR IGNORE INTO it_advances VALUES(?,?,0)',
          [business, e.$1],
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> employees() async {
    _authorize();
    await prepare();
    return _read('SELECT * FROM it_employees WHERE business_id=? ORDER BY id', [
      business,
    ]);
  }

  Future<void> createJob(String id, String label) async {
    _authorize();
    await prepare();
    if (id.isEmpty || label.trim().isEmpty)
      { throw ArgumentError('Job identity and description required'); }
    await db.customStatement('INSERT INTO it_jobs VALUES(?,?,?)', [
      business,
      id,
      label,
    ]);
  }

  /// Each local invoice labor line creates one linked service task. Replaying
  /// the same line is harmless; changed content under the same identity fails.
  Future<void> addLabor(
    String job,
    String line,
    String description,
    int hours,
  ) async {
    _authorize();
    await prepare();
    if (line.isEmpty || description.trim().isEmpty || hours < 0)
      { throw ArgumentError('Invalid labor'); }
    await db.transaction(() async {
      if ((await _read('SELECT id FROM it_jobs WHERE business_id=? AND id=?', [
            business,
            job,
          ])).length !=
          1)
        { throw StateError('Job missing'); }
      final existing = await _read(
        'SELECT * FROM it_tasks WHERE business_id=? AND job_id=? AND labor_id=?',
        [business, job, line],
      );
      if (existing.isNotEmpty) {
        if (existing.single['description'] != description ||
            existing.single['planned'] != hours)
          { throw StateError('Conflicting labor replay'); }
        return;
      }
      await db.customStatement('INSERT INTO it_tasks VALUES(?,?,?,?,?,?)', [
        business,
        '$job/$line',
        job,
        line,
        description,
        hours,
      ]);
    });
  }

  Future<void> assign(String task, String employee) async {
    _authorize();
    await prepare();
    await db.transaction(() async {
      final tasks = await _read(
        'SELECT * FROM it_tasks WHERE business_id=? AND id=?',
        [business, task],
      );
      final staff = await _read(
        'SELECT * FROM it_employees WHERE business_id=? AND id=?',
        [business, employee],
      );
      if (tasks.length != 1 || staff.length != 1)
        { throw StateError('Task or employee missing'); }
      final id = '$task/$employee';
      await db.customStatement(
        "INSERT INTO it_portions(business_id,id,task_id,employee_id,state) VALUES(?,?,?,?,'Open')",
        [business, id, task, employee],
      );
      await LocalMechanicWorkCreditRepository(database: db).createAssignment(
        businessId: business, allocationId: id, jobId: tasks.single['job_id'] as String,
        laborLineId: tasks.single['labor_id'] as String, taskId: task, employeeId: employee,
        actualMinutes: ((tasks.single['planned'] as int) * 60 + 50) ~/ 100,
        rateCents: staff.single['rate'] as int,
      );
    });
  }

  /// Editing or reopening an unpaid portion increments its version. Paid
  /// portions require a new recheck labor line; their original hours stay frozen.
  Future<void> updateWork(
    String id,
    String state,
    int hours,
    String date,
  ) async {
    _authorize();
    await prepare();
    _date(date);
    if (!['Open', 'In Progress', 'Done'].contains(state) || hours < 0)
      { throw ArgumentError('Invalid work'); }
    await db.transaction(() async {
      final rows = await _read(
        'SELECT c.*,p.state FROM local_mechanic_work_credits_v1 c JOIN it_portions p ON p.business_id=c.business_id AND p.id=c.allocation_id WHERE c.business_id=? AND c.allocation_id=?',
        [business, id],
      );
      if (rows.length != 1 || rows.single['paid_operation_id'] != null)
        { throw StateError('Missing or paid work; add a recheck'); }
      if (state == 'Done' && rows.single['state'] == 'Open')
        { throw StateError('Start work before completion'); }
      await LocalMechanicWorkCreditRepository(database: db).recordWork(
        businessId: business, allocationId: id, employeeId: rows.single['employee_id'] as String,
        expectedRevision: rows.single['revision'] as int,
        actualMinutes: (hours * 60 + 50) ~/ 100, completed: state == 'Done',
      );
      await db.customStatement(
        'UPDATE it_portions SET state=?,version=version+1,completed_date=? WHERE business_id=? AND id=?',
        [state, state == 'Done' ? date : null, business, id],
      );
    });
  }

  Future<List<Map<String, dynamic>>> jobs() async {
    _authorize();
    await prepare();
    return _read(
      '''SELECT j.*,count(t.id) total, coalesce(sum(CASE WHEN EXISTS(SELECT 1 FROM it_portions p WHERE p.business_id=t.business_id AND p.task_id=t.id) AND NOT EXISTS(SELECT 1 FROM it_portions p WHERE p.business_id=t.business_id AND p.task_id=t.id AND p.state!='Done') THEN 1 ELSE 0 END),0) done,
    (SELECT count(*) FROM it_portions p JOIN it_tasks x ON x.business_id=p.business_id AND x.id=p.task_id WHERE x.business_id=j.business_id AND x.job_id=j.id AND p.state!='Open') started
    FROM it_jobs j LEFT JOIN it_tasks t ON t.business_id=j.business_id AND t.job_id=j.id WHERE j.business_id=? GROUP BY j.id ORDER BY j.id''',
      [business],
    );
  }

  Future<List<Map<String, dynamic>>> tasks() async {
    _authorize();
    await prepare();
    return _read('SELECT * FROM it_tasks WHERE business_id=? ORDER BY id', [
      business,
    ]);
  }

  Future<List<Map<String, dynamic>>> work({String? employee}) async {
    _authorize();
    await prepare();
    return _read(
      '''SELECT p.business_id,p.id,p.task_id,p.employee_id,p.state,p.completed_date,c.revision AS version,t.description,t.job_id,c.actual_minutes,(c.actual_minutes*100+30)/60 AS hours_hundredths,c.rate_cents,(c.actual_minutes*c.rate_cents+30)/60 AS gross_cents,CASE WHEN c.paid_operation_id IS NULL THEN 0 ELSE 1 END AS paid FROM it_portions p JOIN it_tasks t ON t.business_id=p.business_id AND t.id=p.task_id JOIN local_mechanic_work_credits_v1 c ON c.business_id=p.business_id AND c.allocation_id=p.id WHERE p.business_id=? ${employee == null ? '' : 'AND p.employee_id=?'} ORDER BY p.id''',
      [business, ?employee],
    );
  }

  Future<int> advance(String employee) async {
    _authorize();
    await prepare();
    final r = await _read(
      'SELECT balance FROM it_advances WHERE business_id=? AND employee_id=?',
      [business, employee],
    );
    return r.single['balance'] as int;
  }

  Future<void> addAdvance(String employee, int amount) async {
    _authorize();
    await prepare();
    if (amount <= 0) { throw ArgumentError('Positive advance required'); }
    await db.transaction(() async {
      if ((await _read(
        'SELECT id FROM it_employees WHERE business_id=? AND id=?',
        [business, employee],
      )).isEmpty)
        { throw StateError('Employee missing'); }
      await db.customStatement(
        'UPDATE it_advances SET balance=balance+? WHERE business_id=? AND employee_id=?',
        [amount, business, employee],
      );
      await db.customStatement(
        'INSERT INTO it_audit(business_id,operation_id,event,payload) VALUES(?,?,?,?)',
        [
          business,
          'advance-${DateTime.now().microsecondsSinceEpoch}',
          'advance',
          jsonEncode({'employee': employee, 'amount': amount}),
        ],
      );
    });
  }

  Future<List<Map<String, dynamic>>> history(String employee) async {
    _authorize();
    await prepare();
    return _read(
      'SELECT * FROM it_payments WHERE business_id=? AND employee_id=? ORDER BY verified_date DESC,operation_id DESC',
      [business, employee],
    );
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
        !['Cash', 'Zelle', 'Check', 'Card', 'Other'].contains(method) ||
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
      final prior = await _read(
        'SELECT payload FROM it_payments WHERE business_id=? AND operation_id=?',
        [business, operation],
      );
      if (prior.isNotEmpty) {
        if (prior.single['payload'] != payload)
          { throw StateError('Conflicting replay'); }
        return false;
      }
      final staff = await _read(
        'SELECT * FROM it_employees WHERE business_id=? AND id=?',
        [business, employee],
      );
      if (staff.length != 1 || (base > 0 && staff.single['base_enabled'] != 1))
        { throw StateError('Base not allowed for employee'); }
      final current = await work(employee: employee);
      var gross = base + hourlyAdjustment;
      final snapshots = <String>[];
      for (final p in picked) {
        final match = current.where((w) => w['id'] == p['id']).toList();
        if (match.length != 1) { throw StateError('Missing work'); }
        final w = match.single;
        if (w['state'] != 'Done' ||
            w['paid'] != 0 ||
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
        gross += ((p['minutes'] as int) * (p['rate'] as int) + 30) ~/ 60;
        snapshots.add(jsonEncode(w));
      }
      if (gross < 0 ||
          repayment > gross ||
          repayment > await advance(employee) ||
          confirmedNet != gross - repayment)
        { throw StateError('Amount or repayment changed'); }
      if (base > 0)
        { await db.customStatement('INSERT INTO it_paid_base VALUES(?,?,?,?,?)', [
          business,
          employee,
          week,
          operation,
          base,
        ]); }
      await db.customStatement(
        'INSERT INTO it_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
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
        await db.customStatement('INSERT INTO it_paid_work VALUES(?,?,?,?)', [
          business,
          picked[i]['id'],
          operation,
          snapshots[i],
        ]);
        await db.customStatement(
          'UPDATE local_mechanic_work_credits_v1 SET paid_operation_id=? WHERE business_id=? AND allocation_id=?',
          [operation, business, picked[i]['id']],
        );
      }
      await db.customStatement(
        'UPDATE it_advances SET balance=balance-? WHERE business_id=? AND employee_id=?',
        [repayment, business, employee],
      );
      await db.customStatement(
        'INSERT INTO it_audit(business_id,operation_id,event,payload) VALUES(?,?,?,?)',
        [business, operation, 'verify_payment', payload],
      );
      // Deliberately separate from the production outbox: delivery is disabled
      // until TEST acceptance and a server idempotency contract exist.
      await db.customStatement(
        'INSERT INTO it_sync_outbox(business_id,operation_id,payload) VALUES(?,?,?)',
        [business, operation, payload],
      );
      if (beforeCommit != null) { await beforeCommit(); }
      return true;
    });
  }
}
