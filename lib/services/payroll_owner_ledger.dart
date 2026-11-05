import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'local_payroll_repository.dart';
import 'local_document_sql_store.dart';
import 'local_document_detail_cache.dart';
import 'payroll_owner_lease.dart';

/// Transfers only the existing payroll ledger. Real financial documents are
/// neither replaced nor uploaded. Local pending shop operations are untouched.
class PayrollOwnerLedger {
  PayrollOwnerLedger(this.db, this.business);
  final BriskersLocalDatabase db;
  final String business;
  static const tables = [
    'regular_payroll_jobs', 'regular_payroll_employees', 'regular_payroll_tasks',
    'regular_payroll_task_sources', 'regular_payroll_estimates',
    'regular_payroll_portions', 'local_mechanic_work_credits_v1', 'regular_payroll_progress_claims', 'regular_payroll_assignment_outgoing',
    'regular_payroll_advances', 'regular_payroll_payments',
    'regular_payroll_paid_work', 'regular_payroll_paid_base',
    'regular_payroll_work_coverage', 'regular_payroll_weekly_defaults',
    'regular_payroll_audit', 'regular_payroll_sync_outbox',
  ];
  static const immutable = {
    'regular_payroll_payments', 'regular_payroll_paid_work',
    'regular_payroll_paid_base', 'regular_payroll_work_coverage',
  };
  Future<void> prepare() async {
    await LocalPayrollRepository(db, business: business, owner: true).prepare();
    await LocalDocumentSqlStore.ensure(db);
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_assignment_outgoing '
      '(business_id TEXT NOT NULL,peer TEXT NOT NULL,credit TEXT NOT NULL,revision INTEGER NOT NULL,body TEXT NOT NULL,'
      'PRIMARY KEY(business_id,peer,credit))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS payroll_owner_pending_v2 '
      '(business_id TEXT NOT NULL,operation TEXT NOT NULL,request TEXT NOT NULL,'
      "state TEXT NOT NULL DEFAULT 'pending',reason TEXT NOT NULL,"
      'PRIMARY KEY(business_id,operation))');
  }
  Variable _variable(Object? value) => value is int ? Variable<int>(value)
      : value is double ? Variable<double>(value) : value is bool ? Variable<bool>(value)
      : Variable<String>(value as String?);
  Future<List<Map<String, dynamic>>> _rows(String table) async =>
      (await db.customSelect('SELECT * FROM $table WHERE business_id=?',
        variables: [Variable(business)]).get()).map((r) => r.data).toList();

  Future<String> export() async {
    await prepare();
    return db.transaction(() async => jsonEncode({'business': business,
      'version': 2, 'references': await _references(), 'tables': {
        for (final table in tables) table: await _rows(table),
      }}));
  }

  Future<Map<String, dynamic>> _references() async {
    final jobs = await db.customSelect(
      'SELECT j.* FROM local_jobs j WHERE j.business_id=? AND EXISTS '
      '(SELECT 1 FROM regular_payroll_tasks t WHERE t.business_id=j.business_id AND t.job_id=j.id)',
      variables: [Variable(business)]).get();
    final documents = await db.customSelect(
      'SELECT d.* FROM local_documents d WHERE d.business_id=? AND EXISTS '
      '(SELECT 1 FROM regular_payroll_task_sources s WHERE s.business_id=d.business_id AND s.invoice_id=d.id)',
      variables: [Variable(business)]).get();
    final details = <Map<String, dynamic>>[];
    for (final document in documents) {
      final key = LocalDocumentDetailCache.key(business, document.read<String>('id'));
      final detail = await LocalDocumentSqlStore.read(db, key);
      if (detail != null) details.add({'cache_key': key, 'payload_json': detail});
    }
    final assignments = await db.customSelect('SELECT a.* FROM local_job_assignments a WHERE a.business_id=? AND EXISTS '
      '(SELECT 1 FROM regular_payroll_tasks t WHERE t.business_id=a.business_id AND t.job_id=a.job_id)',
      variables: [Variable(business)]).get();
    return {'local_jobs': jobs.map((r) => r.data).toList(),
      'local_job_assignments': assignments.map((r) => r.data).toList(),
      'local_documents': documents.map((r) => r.data).toList(), 'details': details};
  }

  /// A non-holder can contribute newer task progress, never financial history.
  /// Canonical import is allowed only for a verified, fenced lease offer.
  Future<void> mergeSnapshot(String body, {required bool canonical}) async {
    final bundle = Map<String, dynamic>.from(jsonDecode(body) as Map);
    if (bundle['business'] != business || bundle['version'] != 2) {
      throw StateError('Payroll snapshot belongs to a different shop.');
    }
    final incoming = Map<String, dynamic>.from(bundle['tables'] as Map);
    if (incoming.keys.any((key) => !tables.contains(key)) ||
        tables.any((table) => incoming[table] is! List)) {
      throw StateError('Incomplete payroll snapshot.');
    }
    await prepare();
    await db.transaction(() async {
      final references = bundle['references'];
      if (references is Map) {
        for (final table in ['local_jobs', 'local_documents', 'local_job_assignments']) {
          final info = await db.customSelect('PRAGMA table_info($table)').get();
          final columns = info.map((r) => r.read<String>('name')).toSet();
          for (final raw in references[table] as List? ?? []) {
            final row = Map<String, dynamic>.from(raw as Map);
            if (row['business_id'] != business || row.keys.any((key) => !columns.contains(key))) {
              throw StateError('Invalid payroll source reference.');
            }
            // Readable reference copies never replace pending local shop edits.
            await db.customStatement('INSERT OR IGNORE INTO $table(${row.keys.join(',')}) '
              'VALUES(${row.keys.map((_) => '?').join(',')})', row.values.toList());
          }
        }
        for (final raw in references['details'] as List? ?? []) {
          final row = Map<String, dynamic>.from(raw as Map);
          final key = row['cache_key'] as String;
          final detail = jsonDecode(row['payload_json'] as String) as Map;
          if (key != LocalDocumentDetailCache.key(business, detail['id'] as String) ||
              (detail['business_id'] != null && detail['business_id'] != business)) {
            throw StateError('Invalid payroll document reference.');
          }
          if (!await LocalDocumentSqlStore.deleted(db, key)) {
            await db.customStatement('INSERT OR IGNORE INTO local_document_details VALUES(?,?)',
              [key, row['payload_json']]);
          }
        }
      }
      // Refuse to overwrite divergent payments or omit locally recorded history.
      for (final table in immutable) {
        final rows = (incoming[table] as List).cast<Map>();
        final localRows = await _rows(table);
        if (!canonical && rows.any((row) => !localRows.any((local) => _same(row, local)))) {
          throw const PayrollPending('Payment pending: Owner payment histories differ. No records were overwritten.');
        }
        for (final local in localRows) {
          if (canonical && !rows.any((r) => _same(r, local))) {
            throw const PayrollPending('Payment pending: payroll histories differ and require reconciliation. Existing records were preserved.');
          }
        }
      }
      if (canonical) {
        final audit = (incoming['regular_payroll_audit'] as List).cast<Map>();
        for (final local in await _rows('regular_payroll_audit')) {
          if (!audit.any((row) => row['operation_id'] == local['operation_id'] &&
              row['event'] == local['event'] && row['payload'] == local['payload'])) {
            throw const PayrollPending('Payment pending: an existing advance or repayment is not reconciled. Records were preserved.');
          }
        }
      }
      if (!canonical) {
        for (final raw in incoming['regular_payroll_sync_outbox'] as List) {
          final row = raw as Map;
          if (row['business_id'] != business) throw StateError('Invalid payroll acknowledgment scope.');
          if (row['state'] == 'reconciled') {
            await db.customStatement("UPDATE regular_payroll_sync_outbox SET state='reconciled' "
              'WHERE business_id=? AND operation_id=? AND payload=?',
              [business, row['operation_id'], row['payload']]);
          }
        }
      }
      for (final table in tables) {
        if (!canonical && (immutable.contains(table) ||
            ['regular_payroll_advances', 'regular_payroll_audit',
             'regular_payroll_weekly_defaults', 'regular_payroll_sync_outbox', 'regular_payroll_assignment_outgoing'].contains(table))) { continue; }
        final info = await db.customSelect('PRAGMA table_info($table)').get();
        final columns = info.map((r) => r.read<String>('name')).toList();
        final primary = info.where((r) => r.read<int>('pk') > 0)
          .map((r) => r.read<String>('name')).toList();
        for (final raw in incoming[table] as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          if (row['business_id'] != business || row.keys.any((key) => !columns.contains(key))) {
            throw StateError('Invalid payroll snapshot row.');
          }
          if (table == 'regular_payroll_audit') {
            row.remove('id');
            final existing = await db.customSelect(
              'SELECT id FROM $table WHERE business_id=? AND operation_id=? AND event=? AND payload=?',
              variables: [business, row['operation_id'], row['event'], row['payload']]
                .map(_variable).toList(),
            ).get();
            if (existing.isNotEmpty) continue;
            await _insert(table, row);
            continue;
          }
          final where = primary.map((key) => '$key=?').join(' AND ');
          final existing = await db.customSelect('SELECT * FROM $table WHERE $where',
            variables: primary.map((key) => _variable(row[key])).toList()).get();
          if (existing.isEmpty) {
            await _insert(table, row);
          } else if (!_same(existing.single.data, row)) {
            if (immutable.contains(table) || table == 'regular_payroll_progress_claims') throw StateError('Conflicting immutable payroll record.');
            final prior = existing.single.data;
            if (table == 'local_mechanic_work_credits_v1' || table == 'regular_payroll_portions' || table == 'regular_payroll_assignment_outgoing') {
              final field = table == 'regular_payroll_portions' ? 'version' : 'revision';
              final previous = prior[field] as int;
              final next = row[field] as int;
              if (next < previous) continue;
              if (next == previous) {
                // The final payment marker is set without rewriting work revision.
                if (canonical && table == 'local_mechanic_work_credits_v1' &&
                    row['paid_operation_id'] != null && prior['paid_operation_id'] == null &&
                    _same({...row, 'paid_operation_id': null}, prior)) {
                  await db.customStatement('UPDATE $table SET paid_operation_id=? WHERE $where',
                    [row['paid_operation_id'], ...primary.map((key) => row[key])]);
                  continue;
                }
                if (!canonical && table == 'local_mechanic_work_credits_v1' &&
                    prior['paid_operation_id'] != null && row['paid_operation_id'] == null &&
                    _same({...prior, 'paid_operation_id': null}, row)) { continue; }
                throw const PayrollPending('Payment pending: mechanic work differs. Reconcile the task before payment.');
              }
            } else if (!canonical) {
              // Unversioned edits must be reconciled explicitly, not silently won.
              continue;
            }
            final changed = row.keys.where((key) => !primary.contains(key)).toList();
            await db.customStatement('UPDATE $table SET ${changed.map((key) => '$key=?').join(',')} WHERE $where',
              [...changed.map((key) => row[key]), ...primary.map((key) => row[key])]);
          }
        }
      }
      final invalid = await db.customSelect(
        'SELECT 1 FROM regular_payroll_payments WHERE business_id=? '
        'AND (gross<0 OR repayment<0 OR net<0 OR net<>gross-repayment) '
        'UNION ALL SELECT 1 FROM regular_payroll_work_coverage w '
        'LEFT JOIN local_mechanic_work_credits_v1 c ON c.business_id=w.business_id AND c.allocation_id=w.credit_id '
        'LEFT JOIN regular_payroll_payments p ON p.business_id=w.business_id AND p.operation_id=w.operation_id '
        'WHERE w.business_id=? AND (c.allocation_id IS NULL OR p.operation_id IS NULL OR c.employee_id<>p.employee_id) '
        'UNION ALL SELECT 1 FROM local_mechanic_work_credits_v1 c WHERE c.business_id=? '
        'AND COALESCE((SELECT SUM(minutes) FROM regular_payroll_work_coverage w '
        'WHERE w.business_id=c.business_id AND w.credit_id=c.allocation_id),0)>c.actual_minutes LIMIT 1',
        variables: [business, business, business].map(Variable<String>.new).toList()).get();
      if (invalid.isNotEmpty) throw StateError('Payroll integrity verification failed; existing records were preserved.');
      await db.customStatement("UPDATE payroll_owner_pending_v2 SET state='resolved',reason='' "
        'WHERE business_id=? AND operation IN (SELECT operation_id FROM regular_payroll_payments WHERE business_id=?)',
        [business, business]);
    });
  }
  static bool _same(Map a, Map b) => a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
  Future<void> _insert(String table, Map<String, dynamic> row) => db.customStatement(
    'INSERT INTO $table(${row.keys.join(',')}) VALUES(${row.keys.map((_) => '?').join(',')})', row.values.toList());

  static Future<String> operationFor(Map<String, dynamic> request) {
    final selected = [
      for (final raw in request['selected'] as List? ?? [])
        {for (final key in ['id', 'version', 'hours_hundredths', 'actual_minutes',
            'rate_cents', 'paid_minutes', 'pay_minutes', 'payment_rate_cents'])
          if ((raw as Map).containsKey(key)) key: raw[key]},
    ]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return PayrollOwnerLease.digest(jsonEncode({...request, 'selected': selected}));
  }

  Future<String> intent(Map<String, dynamic> request) async {
    await prepare();
    final raw = jsonEncode(request);
    final operation = await operationFor(request);
    if ((await db.customSelect('SELECT operation_id FROM regular_payroll_payments WHERE business_id=? AND operation_id=?',
      variables: [business, operation].map(Variable<String>.new).toList()).get()).isNotEmpty) return operation;
    await db.customStatement('INSERT OR IGNORE INTO payroll_owner_pending_v2 VALUES(?,?,?,\'pending\',\'Awaiting current payroll state\')',
      [business, operation, raw]);
    return operation;
  }
  Future<void> resolve(String operation) => db.customStatement(
    "UPDATE payroll_owner_pending_v2 SET state='resolved',reason='' WHERE business_id=? AND operation=?", [business, operation]);
  Future<List<Map<String, dynamic>>> pending() async {
    await prepare();
    return (await db.customSelect("SELECT *,json_extract(request,'\$.employee') AS employee_id FROM payroll_owner_pending_v2 WHERE business_id=? AND state='pending'",
      variables: [Variable(business)]).get()).map((r) => r.data).toList();
  }
}
