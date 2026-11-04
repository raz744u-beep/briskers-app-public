import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'local_mechanic_work_credit_repository.dart';
import 'local_payroll_work_source.dart';

/// Business-scoped local payroll ledger. Payment recording never sends money
/// or connects to the general financial sync queue.
class LocalPayrollRepository {
  LocalPayrollRepository(
    this.db, {
    required this.business,
    required this.owner,
    this.assertOwnerGrant,
    this.deviceId,
  });
  final BriskersLocalDatabase db;
  final String business;
  final bool owner;
  final void Function()? assertOwnerGrant;
  final String? deviceId;
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
    for (final sql in [
      '''CREATE TABLE IF NOT EXISTS regular_payroll_payment_authority (business_id TEXT PRIMARY KEY, device_id TEXT NOT NULL)''',
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
      final task = jsonEncode([jobId, invoiceId, lineId]);
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
      if (existing.isNotEmpty) return;
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
      await LocalMechanicWorkCreditRepository(database: db).createAssignment(
        businessId: business, allocationId: id, jobId: tasks.single['job_id'] as String,
        laborLineId: tasks.single['labor_id'] as String, taskId: task, employeeId: employee,
        actualMinutes: ((tasks.single['planned'] as int) * 60 + 50) ~/ 100,
        rateCents: staff.single['rate'] as int,
      );
    });
  }

  Future<List<Map<String, dynamic>>> mechanicWork({
    required String job,
    required String employee,
    required void Function() assertSession,
  }) async {
    assertSession();
    await prepare();
    final rows = await _read(
      'SELECT c.allocation_id AS id,t.description,p.state,c.actual_minutes,c.revision '
      'FROM local_mechanic_work_credits_v1 c '
      'JOIN regular_payroll_portions p ON p.business_id=c.business_id AND p.id=c.allocation_id '
      'JOIN regular_payroll_tasks t ON t.business_id=p.business_id AND t.id=p.task_id '
      'WHERE c.business_id=? AND c.job_id=? AND c.employee_id=? '
      'AND EXISTS (SELECT 1 FROM local_job_assignments a WHERE a.business_id=c.business_id '
      'AND a.job_id=c.job_id AND a.employee_id=c.employee_id AND a.active=1) '
      'ORDER BY c.allocation_id',
      [business, job, employee],
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
    });
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
    return _read('SELECT * FROM regular_payroll_tasks WHERE business_id=? ORDER BY id', [
      business,
    ]);
  }

  Future<List<Map<String, dynamic>>> work({String? employee, String? job}) async {
    _authorize();
    await prepare();
    return _read(
      '''SELECT p.business_id,p.id,p.task_id,p.employee_id,e.name AS employee_name,p.state,p.completed_date,c.revision AS version,t.description,t.job_id,c.completed AS credit_completed,c.actual_minutes,(c.actual_minutes*100+30)/60 AS hours_hundredths,c.rate_cents,(c.actual_minutes*c.rate_cents+30)/60 AS gross_cents,CASE WHEN c.paid_operation_id IS NULL THEN 0 ELSE 1 END AS paid FROM regular_payroll_portions p JOIN regular_payroll_tasks t ON t.business_id=p.business_id AND t.id=p.task_id JOIN local_mechanic_work_credits_v1 c ON c.business_id=p.business_id AND c.allocation_id=p.id JOIN regular_payroll_employees e ON e.business_id=p.business_id AND e.id=p.employee_id WHERE p.business_id=? ${employee == null ? '' : 'AND p.employee_id=?'} ${job == null ? '' : 'AND t.job_id=?'} ORDER BY p.id''',
      [business, ?employee, ?job],
    );
  }

  Future<int> advance(String employee) async {
    _authorize();
    await prepare();
    final r = await _read(
      'SELECT balance FROM regular_payroll_advances WHERE business_id=? AND employee_id=?',
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
      final staff = await _read(
        'SELECT * FROM regular_payroll_employees WHERE business_id=? AND id=?',
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
            w['credit_completed'] != 1 ||
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
        snapshots.add(jsonEncode({...w, 'employee_name': staff.single['name']}));
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
        await db.customStatement('INSERT INTO regular_payroll_paid_work VALUES(?,?,?,?)', [
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
      _authorize();
      return true;
    });
  }
}
