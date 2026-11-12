import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'invoice_labor_work_summary.dart';
import 'local_task_assignment_store.dart';

/// Derived task identities follow saved invoice identities. This store never
/// changes an invoice, a document number, or a mechanic's earned work.
class LocalInvoiceTaskStore {
  LocalInvoiceTaskStore(this.db);
  final BriskersLocalDatabase db;
  // Owner cutoff: through Sunday November 8, shop-local calendar date.
  // Historical completion is not evidence that a mechanic was paid.
  static const payrollCutover = '2026-11-09';
  static bool currentPayrollDate(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null && parsed.toIso8601String().startsWith(value) &&
        value.compareTo(payrollCutover) >= 0;
  }

  Future<void> prepare() async {
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_task_order '
      '(business_id TEXT NOT NULL,task_id TEXT NOT NULL,line_position INTEGER NOT NULL,PRIMARY KEY(business_id,task_id))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_estimates '
      '(business_id TEXT NOT NULL,task_id TEXT NOT NULL,employee_id TEXT NOT NULL,'
      'minutes INTEGER NOT NULL CHECK(minutes>=0),PRIMARY KEY(business_id,task_id,employee_id))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_jobs '
      '(business_id TEXT NOT NULL,id TEXT NOT NULL,label TEXT NOT NULL,PRIMARY KEY(business_id,id))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_tasks '
      '(business_id TEXT NOT NULL,id TEXT NOT NULL,job_id TEXT NOT NULL,labor_id TEXT NOT NULL,'
      'description TEXT NOT NULL,planned INTEGER NOT NULL CHECK(planned>=0),'
      'PRIMARY KEY(business_id,id),UNIQUE(business_id,job_id,labor_id))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_task_sources '
      '(business_id TEXT NOT NULL,task_id TEXT NOT NULL,invoice_id TEXT,'
      'line_id TEXT,source_kind TEXT NOT NULL,active INTEGER NOT NULL DEFAULT 1,'
      'PRIMARY KEY(business_id,task_id))');
  }

  Future<void> save(String business, String document, Map<String, dynamic> detail, {bool ownerAssignedOpenDocument = false, String? selectedServiceLine}) async {
    if (detail['id'] != document ||
        (detail['business_id'] != null && detail['business_id'] != business)) {
      return;
    }
    final job = detail['job_id'];
    if (job is! String || job.isEmpty) return;
    final source = await db.customSelect(
      "SELECT j.title,d.document_date,d.status AS document_status FROM local_documents d JOIN local_jobs j "
      "ON j.business_id=d.business_id AND j.id=d.job_id "
      "WHERE d.business_id=? AND d.id=? AND d.job_id=? AND d.kind='invoice'",
      variables: [Variable(business), Variable(document), Variable(job)],
    ).getSingleOrNull();
    if (source == null || (detail['kind'] != null && detail['kind'] != 'invoice')) return;
    final raw = detail['lines'] ?? detail['items'];
    if (raw is! List) return; // An omitted collection is not a deletion.
    final rows = raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
    final ids = rows.map((row) => row['id']).whereType<String>().toList();
    if (rows.length != raw.length || ids.length != rows.length || ids.any((id) => id.isEmpty) ||
        ids.toSet().length != ids.length) {
      return;
    }
    await prepare();
    if (['void','voided','cancelled','canceled','deleted'].contains((source.data['document_status'] ?? detail['status'])?.toString().toLowerCase())) {
      await db.customStatement("UPDATE regular_payroll_task_sources SET active=0 WHERE business_id=? AND invoice_id=? AND source_kind='invoice'",[business,document]);
      return;
    }
    // Task visibility and assignment are independent of payroll eligibility.
    // Pre-cutover sources remain archived in the payroll ledger.
    await db.transaction(() async {
      await db.customStatement(
        'INSERT INTO regular_payroll_jobs VALUES(?,?,?) '
        'ON CONFLICT(business_id,id) DO UPDATE SET label=excluded.label',
        [business, job, source.data['title']],
      );
      await db.customStatement(
        'UPDATE regular_payroll_task_sources SET active=0 '
        "WHERE business_id=? AND invoice_id=? AND source_kind='invoice'",
        [business, document],
      );
      final linked = await db.customSelect(
        'SELECT line_id FROM regular_payroll_task_sources WHERE business_id=? AND invoice_id=?',
        variables: [Variable(business), Variable(document)],
      ).get();
      final selected = linked.map((r) => r.data['line_id']).toSet();
      if (selectedServiceLine != null) selected.add(selectedServiceLine);
      final taskLines = rows.where((r) => isInvoiceLaborLine(r) || selected.contains(r['id']));
      for (final line in taskLines) {
        final id = line['id'] as String;
        final retained = await db.customSelect(
          'SELECT task_id FROM regular_payroll_task_sources '
          'WHERE business_id=? AND invoice_id=? AND line_id=?',
          variables: [business, document, id].map(Variable<String>.new).toList(),
        ).get();
        if (retained.length > 1) { throw StateError('Conflicting invoice task identities.'); }
        final canonical = await db.customSelect(
          'SELECT id FROM regular_payroll_tasks WHERE business_id=? AND job_id=? AND labor_id=?',
          variables:[business,job,jsonEncode([document,id])].map(Variable<String>.new).toList()).get();
        if(canonical.length>1) { throw StateError('Invoice labor identity needs review.'); }
        final task = retained.isNotEmpty ? retained.single.read<String>('task_id')
          : canonical.isNotEmpty ? canonical.single.read<String>('id') : jsonEncode([job, document, id]);
        final hours = isInvoiceLaborLine(line) ? invoiceLaborHours(line) : null;
        final description = (line['description'] ?? line['name'] ?? 'Invoice labor').toString();
        await db.customStatement(
          'INSERT INTO regular_payroll_tasks VALUES(?,?,?,?,?,?) '
          'ON CONFLICT(business_id,id) DO UPDATE SET description=excluded.description,planned=excluded.planned',
          [business, task, job, jsonEncode([document, id]), description,
            hours == null ? 0 : (hours * 100).round()],
        );
        await db.customStatement(
          "INSERT INTO regular_payroll_task_sources VALUES(?,?,?,?,'invoice',1) "
          'ON CONFLICT(business_id,task_id) DO UPDATE SET active=1',
          [business, task, document, id],
        );
      }
      for (var position=0;position<rows.length;position++) {
        final line=rows[position];
        if(!isInvoiceLaborLine(line) && !selected.contains(line['id'])) continue;
        await db.customStatement('INSERT INTO regular_payroll_task_order(business_id,task_id,line_position) '
          'SELECT business_id,task_id,? FROM regular_payroll_task_sources WHERE business_id=? AND invoice_id=? AND line_id=? '
          'ON CONFLICT(business_id,task_id) DO UPDATE SET line_position=excluded.line_position',
          [position,business,document,line['id']]);
      }
      await LocalTaskAssignmentStore(db).inherit(business, job,
        ownerAssignedDocument: ownerAssignedOpenDocument ? document : null);
    });
  }


  Future<void> reconcileCached(String business,String document,Map<String,dynamic> detail) async {
    final raw=detail['lines']??detail['items'];
    if(raw is! List) { return; }
    final rows=raw.whereType<Map>().map(Map<String,dynamic>.from).toList();
    if(rows.length!=raw.length || rows.any((r)=>r['id'] is! String || (r['id'] as String).isEmpty) ||
      rows.map((r)=>r['id']).toSet().length!=rows.length) { return; }
    await prepare();
    final documentRow=await db.customSelect('SELECT status FROM local_documents WHERE business_id=? AND id=?',variables:[Variable(business),Variable(document)]).getSingleOrNull();
    if(['void','voided','cancelled','canceled','deleted'].contains((documentRow?.data['status']??detail['status'])?.toString().toLowerCase())) { await save(business,document,detail);return; }
    final actual=await db.customSelect('SELECT s.line_id,o.line_position FROM regular_payroll_task_sources s '
      'LEFT JOIN regular_payroll_task_order o ON o.business_id=s.business_id AND o.task_id=s.task_id '
      "WHERE s.business_id=? AND s.invoice_id=? AND s.source_kind='invoice' AND s.active=1",
      variables:[Variable(business),Variable(document)]).get();
    final linked=actual.map((r)=>r.data['line_id']).toSet();
    final expected={for(var i=0;i<rows.length;i++) if(isInvoiceLaborLine(rows[i]) || linked.contains(rows[i]['id'])) rows[i]['id']:i};
    if(actual.length!=expected.length || actual.any((r)=>expected[r.data['line_id']]!=r.data['line_position'])) {
      await save(business,document,detail);
    } else if (detail['job_id'] is String) {
      await LocalTaskAssignmentStore(db).inherit(business, detail['job_id'] as String);
    }
  }

  /// Called only by the existing successful draft replay transaction. Exact
  /// ordered source-line equality is required; matching amounts alone is not proof.
  /// Credit IDs and frozen payment snapshots are never changed.
  Future<void> remapDraft(String business, String localId,
      Map<String, dynamic> local, Map<String, dynamic> remote) async {
    await prepare();
    final sources = await db.customSelect(
      'SELECT task_id,line_id FROM regular_payroll_task_sources '
      'WHERE business_id=? AND invoice_id=?',
      variables: [Variable(business), Variable(localId)],
    ).get();
    if (sources.isEmpty) { return; }
    final replay = await db.customSelect(
      "SELECT payload_json FROM sync_outbox WHERE business_id=? AND entity_id=? "
      "AND entity_type='document_draft_create' AND state IN ('pending','inflight')",
      variables: [Variable(business), Variable(localId)],
    ).get();
    if (!localId.startsWith('local-invoice-') || replay.length != 1) {
      throw StateError('Payroll identity replacement requires the pending invoice draft replay.');
    }
    final invoice = remote['id'];
    final job = remote['job_id'];
    if (local['id'] != localId || local['kind'] != 'invoice' ||
        remote['kind'] != 'invoice' || invoice is! String || invoice.isEmpty || invoice.startsWith('local-') ||
        job is! String || job.isEmpty ||
        (remote['business_id'] != null && remote['business_id'] != business)) {
      throw StateError('Payroll draft replay has no verified invoice identity.');
    }
    final before = (local['lines'] as List).cast<Map>();
    final after = (remote['lines'] as List).cast<Map>();
    String text(Map row, String key) => (row[key] ?? '').toString();
    bool same(Map a, Map b) {
      for (final key in ['name', 'description', 'line_kind']) {
        if (text(a, key) != text(b, key)) { return false; }
      }
      for (final key in ['quantity', 'unit_price', 'tax_rate']) {
        final left = num.tryParse(text(a, key));
        final right = num.tryParse(text(b, key));
        if (left != right) { return false; }
      }
      return true;
    }
    if (before.length != after.length ||
        after.map((row) => row['id']).toSet().length != after.length ||
        after.any((row) => row['id'] is! String || (row['id'] as String).isEmpty) ||
        !List.generate(before.length, (i) => same(before[i], after[i])).every((v) => v)) {
      throw StateError('Payroll source lines need reconciliation before invoice identity replacement.');
    }
    await db.transaction(() async {
      for (final source in sources) {
        final index = before.indexWhere((row) => row['id'] == source.data['line_id']);
        if (index < 0) { throw StateError('Original payroll labor identity is missing.'); }
        final line = after[index]['id'] as String;
        final conflict = await db.customSelect(
          'SELECT task_id FROM regular_payroll_task_sources '
          'WHERE business_id=? AND invoice_id=? AND line_id=? AND task_id<>?',
          variables: [business, invoice, line, source.read<String>('task_id')]
            .map(Variable<String>.new).toList(),
        ).get();
        if (conflict.isNotEmpty) { throw StateError('Payroll task identities require review.'); }
        await db.customStatement(
          'UPDATE regular_payroll_task_sources SET invoice_id=?,line_id=? '
          'WHERE business_id=? AND task_id=?',
          [invoice, line, business, source.data['task_id']],
        );
        await db.customStatement(
          'UPDATE regular_payroll_tasks SET job_id=? WHERE business_id=? AND id=?',
          [job, business, source.data['task_id']],
        );
      }
    });
  }

  static double? invoiceLaborHours(Map<String, dynamic> line) {
    final raw = line['quantity'] ?? line['qty'] ?? line['hours'];
    final hours = num.tryParse(raw?.toString() ?? '')?.toDouble();
    return hours != null && hours.isFinite && hours >= 0 && hours <= 10000 ? hours : null;
  }
}
