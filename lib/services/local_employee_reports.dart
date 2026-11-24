import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../core/owner_report_models.dart';
import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import '../local/local_database_provider.dart';
import 'employee_nickname_store.dart';
import 'local_financial_cache.dart';
import 'local_financial_totals_journal.dart';
import 'local_invoice_task_store.dart';
import 'local_job_retirement.dart';
import 'offline_job_admin_service.dart';
import 'payroll_expense_identity.dart';

typedef EmployeeReportLabor = ({
  DateTime date,
  int minutes,
  int paidMinutes,
  int? unpaidMinutes,
  String description,
  String? jobId,
  String? jobNumber,
  String? invoiceId,
  String? invoiceNumber,
});

typedef EmployeeReportPayment = ({
  DateTime? date,
  int? cents,
  String method,
  String savedName,
  String? operationId,
  ReportRow? expense,
});

class EmployeeReportRow {
  EmployeeReportRow(
    this.id,
    this.name, {
    this.historical = false,
    this.inactive = false,
  });

  final String id;
  final String name;
  final bool historical;
  final bool inactive;
  final labor = <EmployeeReportLabor>[];
  final payments = <EmployeeReportPayment>[];

  int get completed => labor.fold(0, (total, row) => total + row.minutes);
  int get paid => labor.fold(0, (total, row) => total + row.paidMinutes);
  int? get unpaid => labor.any((row) => row.unpaidMinutes == null)
      ? null
      : labor.fold(0, (total, row) => total + row.unpaidMinutes!);
  int get paidCents =>
      payments.fold(0, (total, row) => total + (row.cents ?? 0));
}

typedef EmployeeReportData = ({
  List<EmployeeReportRow> employees,
  List<EmployeeReportPayment> review,
  List<int> years,
});

/// Reads local snapshots without preparing, posting or editing payroll.
class LocalEmployeeReports {
  LocalEmployeeReports({BriskersLocalDatabase? database})
    : _db = database ?? localDatabase;

  final BriskersLocalDatabase _db;

  Future<List<ReportRow>> _read(String sql, String business) async =>
      (await _db.customSelect(sql, variables: [Variable(business)]).get())
          .map((row) => row.data)
          .toList();

  Future<EmployeeReportData> load(
    String business,
    ReportPeriod period, {
    required bool isOwner,
  }) async {
    if (!isOwner || business.trim().isEmpty) {
      throw StateError('Owner access is required.');
    }
    final roster = await OfflineJobAdminService(database: _db)
        .cachedEmployees(business);
    return _db.transaction(() async {
      final tables =
          (await _db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type IN ('table','view')",
                  )
                  .get())
              .map((row) => row.read<String>('name'))
              .toSet();
      final staff = <String, ReportRow>{
        if (tables.contains('regular_payroll_employees'))
          for (final employee in await _read(
            'SELECT id,name FROM regular_payroll_employees WHERE business_id=?',
            business,
          ))
            employee['id'] as String: {...employee},
        for (final employee in roster)
          if (_text(employee['id']) case final id?) id: {...employee},
      };
      final aliases = tables.contains('local_employee_nicknames')
          ? await _read(
              'SELECT employee_id,nickname FROM local_employee_nicknames WHERE business_id=?',
              business,
            )
          : <ReportRow>[];
      for (final alias in aliases) {
        final employee = staff[alias['employee_id']];
        if (employee != null) employee['nickname'] = alias['nickname'];
      }
      final names = <String, Set<String>>{};
      final reports = <String, EmployeeReportRow>{};
      for (final entry in staff.entries) {
        final label = EmployeeNicknameStore.displayLabel(
          entry.value,
          staff.values,
        );
        reports[entry.key] = EmployeeReportRow(
          entry.key,
          label.isEmpty ? 'Saved employee' : label,
          inactive: entry.value['active'] == false,
        );
        for (final value in [entry.value['name'], entry.value['nickname']]) {
          if (_normalized(value) case final name?) {
            (names[name] ??= {}).add(entry.key);
          }
        }
      }

      final years = <int>{};
      final review = <EmployeeReportPayment>[];
      void record(
        EmployeeReportPayment payment, {
        String? employee,
        bool ambiguous = false,
      }) {
        final date = payment.date;
        if (date != null) years.add(date.year);
        if (date != null && !period.containsDate(date)) return;
        final name = _normalized(payment.savedName);
        final matches = names[name] ?? const <String>{};
        if (ambiguous ||
            date == null ||
            payment.cents == null ||
            payment.cents! < 0 ||
            (employee == null && (matches.length > 1 || name == null))) {
          review.add(payment);
          return;
        }
        final id = employee ?? matches.singleOrNull ?? 'historical:$name';
        final report = reports.putIfAbsent(
          id,
          () => EmployeeReportRow(
            id,
            payment.savedName.isEmpty ? 'Saved employee' : payment.savedName,
            historical: !staff.containsKey(id) && payment.expense != null,
          ),
        );
        report.payments.add(payment);
      }

      await _payments(business, tables, staff, record);
      for (final row in await _labor(business, tables)) {
        final date = reportDate(row['completed_date']);
        if (date == null) continue;
        years.add(date.year);
        if (!period.containsDate(date)) continue;
        final employee = row['employee_id'] as String;
        final report = reports.putIfAbsent(
          employee,
          () => EmployeeReportRow(employee, 'Saved employee'),
        );
        final minutes = row['actual_minutes'] as int;
        final paid = math.min(minutes, row['paid_minutes'] as int? ?? 0);
        final archived =
            row['source_kind'] == 'invoice' &&
            !LocalInvoiceTaskStore.currentPayrollDate(row['invoice_date']) &&
            row['reviewed_carry'] != 1;
        report.labor.add((
          date: date,
          minutes: minutes,
          paidMinutes: paid,
          unpaidMinutes:
              paid == minutes || (!archived && row['treatment'] != 'review')
              ? minutes - paid
              : null,
          description: _text(row['description']) ?? 'Labor',
          jobId: _text(row['job_id']),
          jobNumber: _text(row['job_number']),
          invoiceId: _text(row['invoice_id']),
          invoiceNumber: _text(row['invoice_number']),
        ));
      }
      int recentFirst(DateTime? a, DateTime? b) =>
          (b ?? DateTime(1900)).compareTo(a ?? DateTime(1900));
      for (final employee in reports.values) {
        employee.labor.sort((a, b) => recentFirst(a.date, b.date));
        employee.payments.sort((a, b) => recentFirst(a.date, b.date));
      }
      return (
        employees: reports.values.toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ),
        review: review..sort((a, b) => recentFirst(a.date, b.date)),
        years: years.toList()..sort((a, b) => b.compareTo(a)),
      );
    });
  }

  Future<void> _payments(
    String business,
    Set<String> tables,
    Map<String, ReportRow> staff,
    void Function(EmployeeReportPayment, {String? employee, bool ambiguous})
    record,
  ) async {
    final cache = LocalFinancialCache(database: _db);
    final options = await cache.loadOptions(business);
    final payrollCategories = <String>{
      for (final option
          in (options['categories'] as List? ?? []).whereType<Map>())
        if (_normalized(option['name'] ?? option['label']) == 'payroll')
          if (_text(option['id']) case final id?) id,
    };
    final transactions = await LocalFinancialTotalsJournal(database: _db)
        .overlayCachedRows(
          business,
          await cache.loadTransactions(business, includeCachedDetails: true),
        );
    final links = <String, String>{
      if (tables.contains('payroll_expense_links_v1'))
        for (final link in await _read(
          'SELECT transaction_id,payroll_operation_id FROM payroll_expense_links_v1 WHERE business_id=?',
          business,
        ))
          link['transaction_id'] as String:
              link['payroll_operation_id'] as String,
    };
    final reversals = <String>{
      if (tables.contains('regular_payroll_reversals_v1'))
        for (final row in await _read(
          'SELECT operation_id FROM regular_payroll_reversals_v1 WHERE business_id=?',
          business,
        ))
          row['operation_id'] as String,
    };
    final settlements = <String, ReportRow>{};
    if (tables.contains('regular_payroll_payments')) {
      final table = tables.contains('regular_payroll_effective_payments_v1')
          ? 'regular_payroll_effective_payments_v1'
          : 'regular_payroll_payments';
      for (final row in await _read(
        'SELECT operation_id,employee_id,verified_date,net,method FROM $table WHERE business_id=?',
        business,
      )) {
        final operation = row['operation_id'] as String;
        settlements[operation] = row;
        links.putIfAbsent(
          PayrollExpenseIdentity.transactionId(business, operation),
          () => operation,
        );
      }
    }
    EmployeeReportPayment expensePayment(
      ReportRow expense, [
      String? operation,
    ]) => (
      date: reportDate(expense['transaction_date'] ?? expense['date']),
      cents: expense['direction'] == null
          ? reportCents(expense['amount'] ?? expense['signed_amount'])?.abs()
          : reportCents(expense['amount']),
      method:
          _text(expense['payment_method_name'] ?? expense['payment_method']) ??
          '',
      savedName:
          _text(expense['counterparty'] ?? expense['counterparty_name']) ?? '',
      operationId: operation,
      expense: expense,
    );
    final linkedExpenses = <String, List<ReportRow>>{};
    for (final row in transactions) {
      if ((row['direction'] != null && row['direction'] != 'expense') ||
          (row['business_id'] != null && row['business_id'] != business) ||
          const {'void', 'voided', 'deleted'}.contains(row['status']) ||
          row['sync_state'] == 'reversed') {
        continue;
      }
      final linkedOperation = links[row['id']];
      final storedOperation = _text(row['payroll_operation_id']);
      if (linkedOperation != null &&
          storedOperation != null &&
          linkedOperation != storedOperation) {
        record(expensePayment(row), ambiguous: true);
        continue;
      }
      final operation = linkedOperation ?? storedOperation;
      if (operation != null) {
        (linkedExpenses[operation] ??= []).add(row);
      } else if (_normalized(row['category'] ?? row['category_name']) ==
              'payroll' ||
          _normalized(row['kind']) == 'payroll' ||
          payrollCategories.contains(_text(row['category_id']))) {
        final savedId = _text(row['employee_id']);
        record(expensePayment(row), employee: savedId);
      }
    }
    for (final operation in {...settlements.keys, ...linkedExpenses.keys}) {
      if (reversals.contains(operation)) continue;
      final settlement = settlements[operation];
      final copies = linkedExpenses[operation] ?? const <ReportRow>[];
      if (settlement == null) {
        for (final row in copies) {
          record(expensePayment(row, operation), ambiguous: copies.length != 1);
        }
        continue;
      }
      final employee = _text(settlement['employee_id']);
      final paidDate = reportDate(settlement['verified_date']);
      final paidCents = settlement['net'] as int;
      final matching = copies.where((row) {
        final expense = expensePayment(row);
        return expense.date == paidDate && expense.cents == paidCents;
      }).toList();
      // A linked settlement is counted once. A conflicting copy stays
      // available for review without increasing the paid total.
      final exact = matching.firstOrNull;
      record((
        date: paidDate,
        cents: paidCents,
        method: _text(settlement['method']) ?? '',
        savedName:
            _text(staff[employee]?['name']) ??
            (exact == null ? '' : expensePayment(exact).savedName),
        operationId: operation,
        expense: exact,
      ), employee: employee);
      for (final row in copies.where((row) => !matching.contains(row))) {
        record(expensePayment(row, operation), ambiguous: true);
      }
    }
  }

  Future<List<ReportRow>> _labor(String business, Set<String> tables) async {
    if (!tables.containsAll({
      'local_mechanic_work_credits_v1',
      'regular_payroll_portions',
      'regular_payroll_tasks',
      'regular_payroll_task_sources',
    })) {
      return [];
    }

    final coverage = tables.contains('regular_payroll_active_coverage_v1')
        ? 'regular_payroll_active_coverage_v1'
        : tables.contains('regular_payroll_work_coverage')
        ? 'regular_payroll_work_coverage'
        : null;
    final reversed = tables.contains('regular_payroll_reversals_v1');
    final priorPaid = tables.contains('regular_payroll_owner_prior_paid_v1')
        ? 'EXISTS (SELECT 1 FROM regular_payroll_owner_prior_paid_v1 h '
              'WHERE h.business_id=p.business_id AND h.allocation_id=p.id AND h.employee_id=p.employee_id)'
        : '0';
    final reviewed = tables.contains('regular_payroll_audit')
        ? "EXISTS (SELECT 1 FROM regular_payroll_audit a WHERE a.business_id=p.business_id "
              "AND a.operation_id=p.id AND a.event='owner_reviewed_unpaid_carry')"
        : '0';
    final metadata = tables.contains('regular_task_metadata');
    final namedMetadata =
        metadata &&
        (await _db
                .customSelect('PRAGMA table_info(regular_task_metadata)')
                .get())
            .any((column) => column.data['name'] == 'task_name');
    final description = !metadata
        ? 't.description'
        : namedMetadata
        ? 'COALESCE(tm.task_name,tm.description,t.description)'
        : 'COALESCE(tm.description,t.description)';
    final schedule = tables.contains('regular_task_schedule_v1');
    final assignment = tables.contains('regular_payroll_assignment_meta');
    final legacyPaid = reversed
        ? 'AND NOT EXISTS (SELECT 1 FROM regular_payroll_reversals_v1 r '
              'WHERE r.business_id=c.business_id AND r.operation_id=c.paid_operation_id)'
        : '';
    final fallback =
        'CASE WHEN c.paid_operation_id IS NOT NULL $legacyPaid THEN c.actual_minutes ELSE 0 END';
    final coverageReversal = reversed
        ? 'AND NOT EXISTS (SELECT 1 FROM regular_payroll_reversals_v1 r '
              'WHERE r.business_id=w.business_id AND r.operation_id=w.operation_id)'
        : '';
    final paid = coverage == null
        ? fallback
        : 'COALESCE((SELECT SUM(w.minutes) FROM $coverage w WHERE w.business_id=c.business_id '
              'AND w.credit_id=c.allocation_id $coverageReversal), $fallback)';
    return _read('''
      SELECT c.employee_id,c.job_id,c.actual_minutes,p.completed_date,
        j.job_number,d.document_number AS invoice_number,d.document_date AS invoice_date,
        s.invoice_id,s.source_kind,
        $description AS description,
        ${schedule ? 'sch.payroll_treatment' : 'NULL'} AS treatment,
        $reviewed AS reviewed_carry,
        CASE WHEN $priorPaid THEN c.actual_minutes ELSE $paid END AS paid_minutes
      FROM local_mechanic_work_credits_v1 c
      JOIN regular_payroll_portions p ON p.business_id=c.business_id AND p.id=c.allocation_id
        AND p.employee_id=c.employee_id AND p.task_id=c.task_id
      JOIN regular_payroll_tasks t ON t.business_id=c.business_id AND t.id=c.task_id
      LEFT JOIN regular_payroll_task_sources s ON s.business_id=c.business_id AND s.task_id=c.task_id
      LEFT JOIN local_jobs j ON j.business_id=c.business_id AND j.id=c.job_id
      LEFT JOIN local_documents d ON d.business_id=c.business_id AND d.id=s.invoice_id
      ${metadata ? 'LEFT JOIN regular_task_metadata tm ON tm.business_id=c.business_id AND tm.task_id=c.task_id' : ''}
      ${schedule ? 'LEFT JOIN regular_task_schedule_v1 sch ON sch.business_id=c.business_id AND sch.task_id=c.task_id' : ''}
      ${assignment ? 'LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=c.business_id AND m.task_id=c.task_id AND m.employee_id=c.employee_id' : ''}
      WHERE c.business_id=? AND p.state='Done' AND c.actual_minutes>0
        AND COALESCE(s.active,1)=1 ${assignment ? 'AND COALESCE(m.active,1)=1' : ''}
        AND COALESCE(d.status,'') NOT IN ('void','voided','cancelled','canceled','deleted')
        ${tables.contains('local_job_retirement_entities') ? "AND NOT EXISTS (SELECT 1 FROM local_job_retirement_entities r WHERE r.business_id=c.business_id AND r.state IN ${LocalJobRetirement.blockedStates} AND ((r.entity_kind='job' AND r.entity_id=c.job_id) OR (r.entity_kind='invoice' AND r.entity_id=s.invoice_id)))" : ''}
        ${tables.contains('local_offline_job_purge_entities') ? "AND NOT EXISTS (SELECT 1 FROM local_offline_job_purge_entities x WHERE x.business_id=c.business_id AND x.entity_kind='job' AND x.entity_id=c.job_id)" : ''}
        ${tables.contains('local_document_identity_aliases') ? 'AND NOT EXISTS (SELECT 1 FROM local_document_identity_aliases a WHERE a.business_id=c.business_id AND a.alias_id=s.invoice_id)' : ''}
      ''', business);
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static String? _normalized(Object? value) =>
      _text(value)?.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
