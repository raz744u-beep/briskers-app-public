import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/owner_report_models.dart';
import '../core/owner_report_payment_merge.dart';
import '../local/briskers_local_database.dart' hide LocalFinancialCache;
import '../local/local_database_provider.dart';
import 'invoice_payment_feed.dart';
import 'local_document_sql_store.dart';
import 'local_financial_cache.dart';
import 'local_financial_totals_journal.dart';
import 'local_invoice_closure.dart';
import 'local_job_retirement.dart';
import 'offline_invoice_payment_ledger.dart';
import 'recovery_commit_store.dart';

/// Reports read the local database in a single consistent transaction. No RPC,
/// bootstrap, sync, payroll preparation, or accounting write is performed.
class LocalOwnerReports {
  LocalOwnerReports({BriskersLocalDatabase? database}) : db = database ?? localDatabase;
  final BriskersLocalDatabase db;

  Future<int> revision() async => (await db.customSelect('SELECT total_changes() AS revision').getSingle()).read<int>('revision');

  Future<OwnerReportData> load(String business, {required bool isOwner}) async {
    if (!isOwner || business.isEmpty) throw StateError('Owner access is required.');
    await LocalDocumentSqlStore.ensure(db);
    await RecoveryCommitStore.ensure(db);
    final blockedJobs = await LocalJobRetirement.blockedJobIds(db, business);
    final blockedDocuments = await LocalJobRetirement.blockedDocumentIds(db, business);
    final preferences = await SharedPreferences.getInstance();
    final legacyDetails = <String, String>{
      for (final key in preferences.getKeys().where((k) => k.startsWith('briskers_document_detail_${business}_')))
        if (preferences.get(key) is String) key: preferences.getString(key)!,
    };
    return db.transaction(() async {
      final names = (await db.customSelect("SELECT name FROM sqlite_master WHERE type IN ('table','view')").get())
          .map((r) => r.read<String>('name')).toSet();
      final aliases = names.contains('local_document_identity_aliases')
          ? await db.customSelect('SELECT a.alias_id,a.canonical_id,ad.job_id AS alias_job,d.job_id AS canonical_job FROM local_document_identity_aliases a JOIN local_documents d '
              'ON d.business_id=a.business_id AND d.id=a.canonical_id '
              'JOIN local_documents ad ON ad.business_id=a.business_id AND ad.id=a.alias_id '
              "WHERE a.business_id=? AND d.kind='invoice' AND ad.kind='invoice'", variables: [Variable(business)]).get()
          : <QueryRow>[];
      final recoveryAliases = await db.customSelect(
        'SELECT local_invoice_id,server_invoice_id FROM recovery_commits WHERE business_id=?',
        variables: [Variable(business)]).get();
      final invoiceAliases = <String, String>{
        for (final alias in aliases) alias.read<String>('alias_id'): alias.read<String>('canonical_id'),
        for (final alias in recoveryAliases) alias.read<String>('local_invoice_id'): alias.read<String>('server_invoice_id'),
      };
      final aliasIds = aliases.map((r) => r.read<String>('alias_id')).toSet();
      final source = await db.customSelect('''
        SELECT d.*,c.display_name AS customer_name,l.cache_key AS detail_key,
          CASE WHEN r.document_id IS NOT NULL THEN r.payload_json ELSE l.payload_json END AS detail_json,
          r.document_id AS recovery_id
        FROM local_documents d
        LEFT JOIN local_customers c ON c.business_id=d.business_id AND c.id=d.customer_id
        LEFT JOIN local_document_details l ON l.cache_key='briskers_document_detail_' || d.business_id || '_' || d.id
        LEFT JOIN recovery_document_cache r ON r.business_id=d.business_id AND r.document_id=d.id
        WHERE d.business_id=? AND d.kind='invoice' AND NOT EXISTS (
          SELECT 1 FROM recovery_commits rc WHERE rc.business_id=d.business_id AND rc.local_invoice_id=d.id
        ) AND NOT EXISTS (
          SELECT 1 FROM local_document_detail_deleted x
          WHERE x.cache_key='briskers_document_detail_' || d.business_id || '_' || d.id)
      ''', variables: [Variable(business)]).get();
      final issues = <String>{};
      final documents = <ReportRow>[];
      final queued = <String, List<ReportRow>>{};
      for (final row in await db.customSelect("SELECT entity_id,payload_json FROM sync_outbox WHERE business_id=? "
          "AND entity_type='invoice_payment_received' AND (state IN ('pending','inflight') OR "
          "(state='conflict' AND last_error='Owner recovery payment preserved; sync disabled')) ORDER BY id",
          variables: [Variable(business)]).get()) {
        try {
          (queued[row.read<String>('entity_id')] ??= []).add(Map<String, dynamic>.from(jsonDecode(row.read<String>('payload_json')) as Map));
        } catch (_) { issues.add('A saved payment needs review.'); }
      }
      for (final row in source) {
        final index = row.data;
        final id = row.read<String>('id');
        if (blockedDocuments.contains(id) || blockedJobs.contains(index['job_id']) || aliasIds.contains(id)) continue;
        if (row.data['recovery_id'] != null && row.data['detail_json'] == null) continue;
        ReportRow detail = {};
        try {
          final saved = row.readNullable<String>('detail_json') ??
            (row.data['recovery_id'] == null && row.data['detail_key'] == null ? legacyDetails['briskers_document_detail_${business}_$id'] : null);
          final decoded = jsonDecode(saved ?? 'null');
          if (decoded is Map && decoded['id'] == id && decoded['kind'] == 'invoice' &&
              (decoded['business_id'] == null || decoded['business_id'] == business)) {
            detail = Map<String, dynamic>.from(decoded);
          }
        } catch (_) { issues.add('Some saved invoice details could not be read.'); }
        final doc = <String, dynamic>{...index, ...detail, 'id': id, 'kind': 'invoice', 'business_id': business,
          'total_amount': detail['total_amount'] ?? index['total'],
          'customer_name': index['customer_name'] ?? detail['customer_name'] ?? 'Customer'}..remove('detail_json')..remove('detail_key');
        final projected = OfflineInvoicePaymentLedger.projectPendingPayments(doc, queued[id] ?? const []);
        final paid = reportCents(projected['paid_amount']) ?? 0;
        final pending = reportCents(projected['pending_payment']) ?? 0;
        doc['_received_cents'] = paid + pending;
        doc['_balance_known'] = projected['_payment_reconciliation_required'] != true && detail['paid_amount'] != null;
        documents.add(doc);
      }
      final invoices = await LocalInvoiceClosureStore(db).projectRows(business, documents);
      // A saved close proof records verified coverage, without inventing receipt dates.
      if (names.contains('local_invoice_closures')) {
        final closureRows = await db.customSelect(
          'SELECT invoice_id,payload FROM local_invoice_closures WHERE business_id=? AND reopened_at IS NULL',
          variables: [Variable(business)]).get();
        final byId = {for (final invoice in invoices) invoice['id']: invoice};
        for (final row in closureRows) {
          try {
            final proof = jsonDecode(row.read<String>('payload')) as Map;
            final invoice = byId[row.read<String>('invoice_id')];
            if (invoice == null) { continue; }
            final gross = reportCents(invoice['total_amount']);
            final paid = proof['paid_cents'];
            if (gross != null && proof['total_cents'] == gross && paid is int && paid >= gross) {
              invoice['_verified_closed_paid_cents'] = paid;
            }
          } catch (_) { issues.add('A saved invoice closure needs review.'); }
        }
      }
      final redundantJobs = aliases.where((r) => r.data['alias_job'] != r.data['canonical_job'])
          .map((r) => r.data['alias_job']).whereType<String>().where((id) =>
            !invoices.any((d) => d['job_id'] == id)).toSet();
      final jobs = (await db.customSelect('SELECT * FROM local_jobs WHERE business_id=?', variables: [Variable(business)]).get())
          .map((r) => r.data).where((r) => !blockedJobs.contains(r['id']) && !redundantJobs.contains(r['id'])).toList();
      final cache = LocalFinancialCache(database: db);
      final invalidFinancial = await db.customSelect(
        "SELECT 1 FROM local_financial_cache WHERE business_id=? AND "
        "(cache_key IN ('transactions_snapshot','invoice_receipts_v1') OR cache_key GLOB 'transaction_detail_*') "
        "AND (NOT json_valid(payload_json) OR CASE WHEN json_valid(payload_json) THEN json_type(payload_json) <> CASE WHEN cache_key GLOB 'transaction_detail_*' THEN 'object' ELSE 'array' END ELSE 0 END) LIMIT 1",
        variables: [Variable(business)]).get();
      if (invalidFinancial.isNotEmpty) issues.add('Saved financial records could not be read.');
      bool inScope(ReportRow r) => r['business_id'] == null || r['business_id'] == business;
      final ledger = await LocalFinancialTotalsJournal(database: db).overlayCachedRows(business,
          await cache.loadTransactions(business, includeCachedDetails: true));
      // This journal contribution is represented by finalizedIncome in the
      // receipt feed. Adding it a second time would double-count local cash.
      final receipts = (await InvoicePaymentFeed(database: db, cache: cache).load(business)).where(inScope).toList();
      final localNewOperations = {for(final batch in queued.values) for(final p in batch)
        if(p['replay_attempted']!=true && p['operation_id']!=null) p['operation_id'].toString()};
      final financial = OwnerReportPaymentMerge.combine(
        financial: ledger.where((r) => inScope(r) && r['locally_finalized_invoice_receipt'] != true).toList(),
        receipts: [for(final r in receipts) {...r, if(localNewOperations.contains(r['operation_id'])) '_report_new_local_receipt':true}],
        invoices: invoices, aliases: invoiceAliases);
      final receiptsByInvoice = <String, int>{};
      for (final r in receipts) {
        final rawId = r['invoice_id']?.toString();
        final id = invoiceAliases[rawId] ?? rawId;
        if (id != null) receiptsByInvoice[id] = (receiptsByInvoice[id] ?? 0) + (reportCents(r['amount']) ?? 0);
      }
      for (final doc in invoices) {
        doc['_received_cents'] = math.max(reportInt(doc['_received_cents']), receiptsByInvoice[doc['id']] ?? 0);
      }
      List<ReportRow> expenses;
      try { expenses = await cache.loadLinkedExpenses(business, failOnUnreadable: true) ?? []; }
      catch (_) { expenses = []; issues.add('Job expenses could not be read.'); }
      final labor = <ReportRow>[];
      if (names.containsAll({'local_mechanic_work_credits_v1', 'regular_payroll_task_sources'})) {
        final coverage = names.contains('regular_payroll_active_coverage_v1') ? 'regular_payroll_active_coverage_v1'
            : names.contains('regular_payroll_work_coverage') ? 'regular_payroll_work_coverage' : null;
        final reversalFilter = coverage == 'regular_payroll_work_coverage' && names.contains('regular_payroll_reversals_v1')
          ? ' AND NOT EXISTS (SELECT 1 FROM regular_payroll_reversals_v1 r WHERE r.business_id=w.business_id AND r.operation_id=w.operation_id)' : '';
        final estimated = names.contains('regular_payroll_estimates');
        final meta = names.contains('regular_payroll_assignment_meta');
        final rows = await db.customSelect('SELECT c.*,s.line_id AS source_line_id,s.invoice_id,s.active AS source_active,'
          '${estimated ? 'COALESCE(e.minutes,0)' : '0'} AS estimated_minutes,'
          '${meta ? 'COALESCE(m.active,1)' : '1'} AS assignment_active,'
          '${coverage == null ? '0' : '(SELECT COALESCE(SUM(w.amount),0) FROM $coverage w WHERE w.business_id=c.business_id AND w.credit_id=c.allocation_id$reversalFilter)'} AS paid_cents,'
          '${coverage == null ? '0' : '(SELECT COALESCE(SUM(w.minutes),0) FROM $coverage w WHERE w.business_id=c.business_id AND w.credit_id=c.allocation_id$reversalFilter)'} AS paid_minutes '
          'FROM local_mechanic_work_credits_v1 c '
          'LEFT JOIN regular_payroll_task_sources s ON s.business_id=c.business_id AND s.task_id=c.task_id '
          '${estimated ? 'LEFT JOIN regular_payroll_estimates e ON e.business_id=c.business_id AND e.task_id=c.task_id AND e.employee_id=c.employee_id ' : ''}'
          '${meta ? 'LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=c.business_id AND m.task_id=c.task_id AND m.employee_id=c.employee_id ' : ''}'
          'WHERE c.business_id=?', variables: [Variable(business)]).get();
        for (final r in rows) {
          if (blockedJobs.contains(r.data['job_id'])) continue;
          labor.add({...r.data,
            if (r.data['assignment_active'] == 0) 'source_active': 0,
            if (aliasIds.contains(r.data['invoice_id'])) 'duplicate_of_task_id': r.data['task_id'],
          });
        }
      }
      return OwnerReportData(business: business, invoices: invoices, transactions: financial,
        jobs: jobs, expenses: expenses, labor: labor, readIssues: issues.toList());
    });
  }
}
