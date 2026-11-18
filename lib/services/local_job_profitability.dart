import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'local_document_repository.dart';
import 'local_document_detail_cache.dart';
import 'local_financial_cache.dart';
import 'local_payroll_task_identity.dart';

/// A read-only job report. It never finalizes invoices or creates payroll.
class LocalJobProfitability {
  const LocalJobProfitability({
    required this.revenueCents, required this.taxCents,
    required this.directCents, required this.laborCents,
    required this.expenses, required this.issues,
  });
  final int? revenueCents, taxCents, directCents, laborCents;
  final List<Map<String, dynamic>> expenses;
  final List<String> issues;
  int? get costCents => directCents == null || laborCents == null
      ? null : directCents! + laborCents!;
  int? get profitCents => revenueCents == null || costCents == null
      ? null : revenueCents! - costCents!;
  double? get margin => revenueCents == null || revenueCents! <= 0 ||
      profitCents == null ? null : profitCents! * 100 / revenueCents!;

  static int? cents(Object? raw) {
    final n = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
    return n == null || !n.isFinite || !(n * 100).isFinite
        ? null : (n * 100).round();
  }

  factory LocalJobProfitability.fromRecords({
    required String business, required String job,
    required List<Map<String, dynamic>> invoices,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> labor,
    bool invoicesReadable = true,
    bool expensesReadable = true,
    bool laborReadable = true,
    bool laborExpected = true,
    Set<String> documentIds = const {},
  }) {
    final issues = <String>{};
    int? revenue = invoicesReadable ? 0 : null;
    int? tax = invoicesReadable ? 0 : null;
    int? direct = expensesReadable ? 0 : null;
    int? wages = laborReadable ? 0 : null;
    if (!invoicesReadable) issues.add('Saved invoice details could not be read.');
    if (!expensesReadable) issues.add('Saved expense details could not be read.');
    if (!laborReadable) issues.add('Saved labor costs could not be read.');
    bool scope(Map<String, dynamic> r) =>
        r['business_id'] == null || r['business_id'] == business;
    final seenInvoices = <String>{};
    for (final row in invoices) {
      if (!scope(row) || row['job_id'] != job || row['kind'] != 'invoice' ||
          const ['void', 'voided', 'cancelled', 'canceled', 'deleted']
              .contains(row['status']?.toString().toLowerCase())) { continue; }
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty || !seenInvoices.add(id)) { continue; }
      final gross = cents(row['total_amount']);
      final salesTax = cents(row['tax_amount']);
      if (gross == null || salesTax == null) {
        revenue = null; tax = null;
        issues.add('Invoice #${row['document_number'] ?? id}: saved total or tax is missing.');
      } else {
        if (revenue != null) revenue += gross - salesTax;
        if (tax != null) tax += salesTax;
      }
    }
    if (invoices.isEmpty) issues.add('No saved invoices are linked to this job.');
    final seenExpenses = <String>{};
    final included = <Map<String, dynamic>>[];
    for (final row in expenses) {
      if (!scope(row) || row['direction'] == 'income' ||
          row['sync_state'] == 'reversed' ||
          const ['void', 'voided', 'deleted'].contains(row['status'])) { continue; }
      final linked = row['job_id'] == job ||
          (row['job_id'] == null && documentIds.contains(row['document_id']));
      if (!linked) { continue; }
      final id = row['id']?.toString() ?? '';
      final key = row['allocation_id']?.toString() ?? id;
      if (id.isEmpty || !seenExpenses.add(key)) { continue; }
      // A weekly payroll expense is not a second job cost. Its immutable
      // work allocations below establish this job's actual paid portions.
      if (row['payroll_operation_id'] != null) { continue; }
      included.add(Map<String, dynamic>.from(row));
      final minor = row['amount_minor'];
      final amount = minor is int ? minor : cents(row['amount']);
      if (amount == null || amount < 0) {
        direct = null;
        issues.add('An expense has no valid saved amount.');
      } else if (direct != null) {
        direct += amount;
      }
    }
    final seenCredits = <String>{};
    var credits = 0;
    for (final row in labor) {
      if (!scope(row) || row['job_id'] != job) { continue; }
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty || !seenCredits.add(id)) { continue; }
      final paid = row['paid_cents'] as int? ?? 0;
      final paidMinutes = row['paid_minutes'] as int? ?? 0;
      final active = row['source_active'] != 0 &&
          row['duplicate_of_task_id'] == null;
      final minutes = row['actual_minutes'] as int? ?? 0;
      final rate = row['rate_cents'] as int? ?? 0;
      final completed = row['completed'] == 1;
      if (!active && paidMinutes == 0) {
        if (row['duplicate_of_task_id'] == null && completed && minutes > 0) {
          wages = null;
          issues.add('Completed labor has an inactive source and needs cost review.');
        }
        continue;
      }
      if (completed || paidMinutes > 0) credits++;
      if ((row['paid_operation_id'] != null && paidMinutes == 0) ||
          (completed && paidMinutes > minutes)) {
        wages = null;
        issues.add('A paid labor allocation needs its original cost details.');
        continue;
      }
      var cost = paid;
      final remaining = active && completed ? minutes - paidMinutes : 0;
      if (remaining > 0 && rate <= 0) {
        wages = null;
        issues.add('Completed labor is missing a saved hourly cost.');
      } else {
        cost += (remaining * rate + 30) ~/ 60;
        if (wages != null) wages += cost;
      }
    }
    if (credits == 0 && laborExpected) {
      wages = null;
      issues.add('Labor is billed, but its saved mechanic cost is unavailable.');
    }
    return LocalJobProfitability(
      revenueCents: revenue, taxCents: tax, directCents: direct,
      laborCents: wages, expenses: List.unmodifiable(included),
      issues: List.unmodifiable(issues),
    );
  }
}

class LocalJobProfitabilityRepository {
  LocalJobProfitabilityRepository(this.db);
  final BriskersLocalDatabase db;

  Future<LocalJobProfitability> load(
    String business, String job, {required bool isOwner}
  ) async {
    if (!isOwner || business.isEmpty || job.isEmpty) {
      throw StateError('Owner job access is required.');
    }
    return db.transaction(() async {
      final documents = await LocalDocumentRepository(database: db)
          .listByJob(business, job);
      final ids = documents.map((r) => r['id'].toString()).toSet();
      final invoices = <Map<String, dynamic>>[];
      var invoiceReadable = true, laborExpected = false;
      for (final row in documents.where((r) => r['kind'] == 'invoice')) {
        if (const ['void', 'voided', 'deleted', 'cancelled', 'canceled']
            .contains(row['status']?.toString().toLowerCase())) { continue; }
        final detail = await LocalDocumentDetailCache(database: db)
            .loadReadOnly(business, row['id'].toString());
        invoices.add({...row, ...?detail});
        final lines = detail?['lines'];
        if (lines is! List) {
          laborExpected = true;
        } else if (lines.whereType<Map>().any((l) =>
            l['line_kind'] == 'labor' &&
            (LocalJobProfitability.cents(l['net_amount']) ?? 1) != 0)) {
          laborExpected = true;
        }
        if (detail == null) invoiceReadable = false;
      }
      List<Map<String, dynamic>> expenses = const [];
      var expensesReadable = true;
      try {
        expenses = await LocalFinancialCache(database: db).loadLinkedExpenses(
          business, jobId: job, documentIds: ids, failOnUnreadable: true,
        ) ?? const [];
      } catch (_) {
        expensesReadable = false;
      }
      final names = (await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type IN ('table','view')",
      ).get()).map((r) => r.read<String>('name')).toSet();
      final labor = <Map<String, dynamic>>[];
      var laborReadable = true;
      if (names.contains('local_mechanic_work_credits_v1')) {
        final aliasTables = {
          'regular_payroll_task_sources', 'regular_payroll_tasks',
          'regular_payroll_task_order', 'regular_payroll_portions',
          'regular_payroll_estimates',
        };
        final aliases = names.containsAll(aliasTables)
            ? await LocalPayrollTaskIdentity(db).aliases(business)
            : <String, String>{};
        final rows = await db.customSelect(
          'SELECT * FROM local_mechanic_work_credits_v1 WHERE business_id=? AND job_id=?',
          variables: [Variable(business), Variable(job)],
        ).get();
        for (final credit in rows) {
          final row = credit.data;
          var paid = 0, paidMinutes = 0, active = 1;
          final coverage = names.contains('regular_payroll_active_coverage_v1')
              ? 'regular_payroll_active_coverage_v1'
              : names.contains('regular_payroll_work_coverage')
                  ? 'regular_payroll_work_coverage' : null;
          if (coverage != null) {
            final reversalFilter = coverage == 'regular_payroll_work_coverage' &&
                names.contains('regular_payroll_reversals_v1')
                ? ' AND NOT EXISTS (SELECT 1 FROM regular_payroll_reversals_v1 r WHERE r.business_id=w.business_id AND r.operation_id=w.operation_id)' : '';
            final covered = await db.customSelect(
              'SELECT w.minutes,w.amount FROM $coverage w WHERE w.business_id=? AND w.credit_id=?$reversalFilter',
              variables: [Variable(business), Variable(row['allocation_id'] as String)],
            ).get();
            for (final part in covered) {
              paid += part.read<int>('amount');
              paidMinutes += part.read<int>('minutes');
            }
          }
          if (names.contains('regular_payroll_task_sources')) {
            final sources = await db.customSelect(
              'SELECT active FROM regular_payroll_task_sources WHERE business_id=? AND task_id=?',
              variables: [Variable(business), Variable(row['task_id'] as String)],
            ).get();
            if (sources.isNotEmpty && sources.every((s) => s.read<int>('active') == 0)) active = 0;
          }
          labor.add({...row, 'id': row['allocation_id'],
            'source_active': active, 'paid_cents': paid,
            'paid_minutes': paidMinutes,
            'duplicate_of_task_id': aliases[row['task_id']],
          });
        }
      } else {
        laborReadable = !laborExpected;
      }
      return LocalJobProfitability.fromRecords(
        business: business, job: job, invoices: invoices, expenses: expenses,
        labor: labor, invoicesReadable: invoiceReadable,
        expensesReadable: expensesReadable, laborReadable: laborReadable,
        laborExpected: laborExpected, documentIds: ids,
      );
    });
  }
}
