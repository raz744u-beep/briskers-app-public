import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'invoice_labor_work_summary.dart';

/// Derived task identities follow saved invoice identities. This store never
/// changes an invoice, a document number, or a mechanic's earned work.
class LocalInvoiceTaskStore {
  LocalInvoiceTaskStore(this.db);
  final BriskersLocalDatabase db;

  Future<void> prepare() async {
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

  Future<void> save(String business, String document, Map<String, dynamic> detail) async {
    if (detail['id'] != document ||
        (detail['business_id'] != null && detail['business_id'] != business)) return;
    final job = detail['job_id'];
    if (job is! String || job.isEmpty) return;
    final source = await db.customSelect(
      "SELECT j.title FROM local_documents d JOIN local_jobs j "
      "ON j.business_id=d.business_id AND j.id=d.job_id "
      "WHERE d.business_id=? AND d.id=? AND d.job_id=? AND d.kind='invoice'",
      variables: [Variable(business), Variable(document), Variable(job)],
    ).getSingleOrNull();
    if (source == null || (detail['kind'] != null && detail['kind'] != 'invoice')) return;
    final raw = detail['lines'] ?? detail['items'];
    if (raw is! List) return; // An omitted collection is not a deletion.
    final rows = raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
    final ids = rows.map((row) => row['id']).whereType<String>().toList();
    if (ids.length != rows.length || ids.any((id) => id.isEmpty) ||
        ids.toSet().length != ids.length) return;
    await prepare();
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
      for (final line in rows.where(isInvoiceLaborLine)) {
        final id = line['id'] as String;
        final task = jsonEncode([job, document, id]);
        final hours = invoiceLaborHours(line);
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
    });
  }

  static double? invoiceLaborHours(Map<String, dynamic> line) {
    final raw = line['quantity'] ?? line['qty'] ?? line['hours'];
    final hours = num.tryParse(raw?.toString() ?? '')?.toDouble();
    return hours != null && hours.isFinite && hours >= 0 && hours <= 10000 ? hours : null;
  }
}
