import 'dart:math' as math;

import '../services/invoice_labor_work_summary.dart';

part 'owner_report_period.dart';

typedef ReportRow = Map<String, dynamic>;

enum OwnerReportMetric {
  income('Income Received', 'Money received in the selected period.'),
  expenses('Total Expenses', 'Recorded expenses in the selected period.'),
  net('Net Profit', 'Cash basis: received income less recorded expenses.'),
  sales(
    'Sales Excl. Tax',
    'Sales excluding tax on verified fully paid invoices dated in the selected period.',
  ),
  projected(
    'Projected Net Income',
    'Current open jobs: sales excluding tax, less recorded job expenses and all assigned mechanic labor. Before unallocated shop overhead and costs not yet recorded.',
  ),
  openJobs('Open Jobs', 'Current active jobs, independent of the date filter.'),
  averageSale(
    'Average Paid Sale',
    'Average sales excluding tax for verified fully paid invoices dated in the selected period.',
  ),
  salesTax(
    'Tax on Paid Invoices',
    'Saved invoice tax on verified fully paid invoices dated in the selected period.',
  ),
  grossSales(
    'Sales Incl. Tax',
    'Total including tax on verified fully paid invoices dated in the selected period.',
  ),
  billedSales(
    'Invoiced Sales Excl. Tax',
    'Billed invoice sales excluding tax, by original invoice date, including unpaid invoices.',
  ),
  billedTax(
    'Tax Billed',
    'Sales tax billed on invoices by original invoice date, including unpaid invoices.',
  ),
  billedGross(
    'Invoiced Total',
    'Total billed invoices including tax, by original invoice date.',
  );

  const OwnerReportMetric(this.label, this.description);
  final String label, description;
  bool get isCount => this == openJobs;
  static const defaults = [income, expenses, net, sales];
}

enum ReportGrouping { monthly, quarterly, yearly }

class ReportPeriod {
  const ReportPeriod(this.start, this.end, {this.preset = 'custom'});
  final DateTime start, end;
  final String preset;
  static DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  factory ReportPeriod.preset(String code, DateTime now) {
    final today = day(now);
    return switch (code) {
      'lastMonth' => ReportPeriod(
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month, 0),
        preset: code,
      ),
      '30days' => ReportPeriod(
        DateTime(today.year, today.month, today.day - 29),
        today,
        preset: code,
      ),
      '60days' => ReportPeriod(
        DateTime(today.year, today.month, today.day - 59),
        today,
        preset: code,
      ),
      '90days' => ReportPeriod(
        DateTime(today.year, today.month, today.day - 89),
        today,
        preset: code,
      ),
      'thisYear' => ReportPeriod(DateTime(now.year), today, preset: code),
      _ => ReportPeriod(
        DateTime(now.year, now.month),
        today,
        preset: 'thisMonth',
      ),
    };
  }
  bool contains(Object? raw) => containsDate(reportDate(raw));
  bool containsDate(DateTime? date) {
    if (date == null) return false;
    int key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
    final value = key(date);
    return value >= key(start) && value <= key(end);
  }

  ReportPeriod shift(int direction) {
    if (preset == 'thisMonth' ||
        preset == 'lastMonth' ||
        (start.day == 1 &&
            end.day == DateTime(end.year, end.month + 1, 0).day)) {
      final first = DateTime(start.year, start.month + direction);
      return ReportPeriod(first, DateTime(first.year, first.month + 1, 0));
    }
    final days =
        DateTime.utc(
          end.year,
          end.month,
          end.day,
        ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
        1;
    return ReportPeriod(
      DateTime(start.year, start.month, start.day + days * direction),
      DateTime(end.year, end.month, end.day + days * direction),
    );
  }
}

// Business dates keep their written calendar day, including ISO timestamps
// with an explicit offset. Parsing the timestamp first would move late-night
// receipts into tomorrow when the device or CI runs in UTC.
final _reportDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|[T ])');
DateTime? reportDate(Object? raw) {
  final match = _reportDatePattern.firstMatch(raw?.toString() ?? '');
  if (match == null) return null;
  final year = int.parse(match[1]!),
      month = int.parse(match[2]!),
      day = int.parse(match[3]!);
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime(year, month + 1, 0).day) {
    return null;
  }
  return DateTime(year, month, day);
}

int? reportCents(Object? raw) {
  final n = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
  return n == null || !n.isFinite || !(n * 100).isFinite
      ? null
      : (n * 100).round();
}

int reportInt(Object? raw) => int.tryParse(raw?.toString() ?? '') ?? 0;
double reportNumber(Object? raw) =>
    num.tryParse(raw?.toString() ?? '')?.toDouble() ?? 0;
bool reportVoided(ReportRow row) =>
    row['sync_state'] == 'reversed' ||
    const {
      'void',
      'voided',
      'deleted',
      'cancelled',
      'canceled',
    }.contains(row['status']?.toString().toLowerCase());

class ReportJobFigure {
  const ReportJobFigure({
    required this.job,
    required this.sales,
    required this.expenses,
    required this.labor,
    required this.issues,
  });
  final ReportRow job;
  final int? sales, expenses, labor;
  final List<String> issues;
  int? get profit => sales == null || expenses == null || labor == null
      ? null
      : sales! - expenses! - labor!;
}

class CustomerReportRow {
  CustomerReportRow(this.id, this.name);
  final String id, name;
  int sales = 0, balance = 0, invoices = 0;
  int? profit = 0;
  bool newCustomer = false, salesKnown = true, balanceKnown = true;
  final Set<String> jobs = {};
  final List<ReportRow> documents = [];
}

class ItemReportRow {
  ItemReportRow(this.id, this.name, this.labor, {this.discount = false});
  final String id, name;
  final bool labor, discount;
  double quantity = 0;
  int revenue = 0;
  int? cost = 0;
  int get unitCount => quantity.round();
  int? get profit => cost == null ? null : revenue - cost!;
  double? get margin =>
      profit == null || revenue <= 0 ? null : profit! * 100 / revenue;
  final Set<String> invoiceIds = {};
}

class OwnerReportSummary {
  const OwnerReportSummary(this.values, this.issues, this.invoices);
  final Map<OwnerReportMetric, int?> values;
  final List<String> issues;
  final List<ReportRow> invoices;
}

/// A consistent snapshot read from the on-device database. Calculation is
/// separate from I/O and never edits invoice, payment or payroll records.
class OwnerReportData {
  OwnerReportData({
    required this.business,
    required List<ReportRow> invoices,
    required List<ReportRow> transactions,
    required List<ReportRow> jobs,
    required List<ReportRow> expenses,
    required List<ReportRow> labor,
    this.readIssues = const [],
  }) : invoices = _unique(
         invoices.where(
           (r) =>
               _scope(r, business) &&
               r['kind'] == 'invoice' &&
               !reportVoided(r),
         ),
       ),
       transactions = _unique(
         transactions.where((r) => _scope(r, business) && !reportVoided(r)),
       ),
       jobs = _unique(
         jobs.where((r) => _scope(r, business) && !reportVoided(r)),
       ),
       expenses = expenses
           .where((r) => _scope(r, business) && !reportVoided(r))
           .toList(),
       labor = labor.where((r) => _scope(r, business)).toList();
  final String business;
  final List<ReportRow> invoices, transactions, jobs, expenses, labor;
  final List<String> readIssues;
  static bool _scope(ReportRow r, String b) =>
      r['business_id'] == null || r['business_id'] == b;
  static List<ReportRow> _unique(Iterable<ReportRow> rows) => {
    for (final r in rows)
      if ((r['id']?.toString() ?? '').isNotEmpty) r['id'].toString(): r,
  }.values.toList();
  late final List<ReportRow> openJobs = jobs.where((r) {
    if (const {
      'closed',
      'completed',
      'complete',
      'done',
      'cancelled',
      'canceled',
    }.contains(r['status']?.toString().toLowerCase())) {
      return false;
    }
    final docs = invoices.where((d) => d['job_id'] == r['id']).toList();
    return docs.isEmpty ||
        !docs.every(
          (d) =>
              (d['closed_at'] != null &&
                  !const {'', '0'}.contains(d['closed_at'].toString())) ||
              d['status'] == 'closed',
        );
  }).toList();
  final _dates = <String, DateTime?>{};
  DateTime? dateOf(Object? raw) =>
      _dates.putIfAbsent(raw?.toString() ?? '', () => reportDate(raw));
  bool inPeriod(ReportPeriod p, Object? raw) => p.containsDate(dateOf(raw));
  List<ReportRow> invoicesIn(ReportPeriod p) =>
      invoices.where((r) => inPeriod(p, r['document_date'])).toList();
  static int? salesOf(ReportRow r) {
    final gross = reportCents(r['total_amount']);
    final tax = reportInvoiceTax(r);
    return gross == null || tax == null ? null : gross - tax;
  }

  static int? _sum(Iterable<int?> values) {
    var total = 0;
    for (final value in values) {
      if (value == null) return null;
      total += value;
    }
    return total;
  }

  List<ReportPeriodEntry>? _paymentEntries;
  final _paidTotals = <String, ReportPeriodTotals>{};
  final _summaries = <String, OwnerReportSummary>{};
  OwnerReportSummary summary(ReportPeriod p) => _summaries.putIfAbsent(
    '${p.start.toIso8601String()}:${p.end.toIso8601String()}',
    () => _summary(p),
  );
  OwnerReportSummary _summary(ReportPeriod p) {
    final selected = invoicesIn(p);
    final financial = transactions
        .where((r) => inPeriod(p, r['transaction_date']))
        .toList();
    int? amount(ReportRow r) => reportCents(
      r['direction'] == 'income' &&
              r['reporting_status'] == 'verified' &&
              r['reporting_amount'] != null
          ? r['reporting_amount']
          : r['amount'],
    );
    final undatedIncome = transactions.any(
      (r) =>
          r['direction'] == 'income' && dateOf(r['transaction_date']) == null,
    );
    final undatedExpense = transactions.any(
      (r) =>
          r['direction'] == 'expense' && dateOf(r['transaction_date']) == null,
    );
    final ambiguousIncome = financial.any(
      (r) => r['_report_payment_review'] == true,
    );
    final income =
        undatedIncome ||
            ambiguousIncome ||
            readIssues.contains('Saved financial records could not be read.')
        ? null
        : _sum(financial.where((r) => r['direction'] == 'income').map(amount));
    final spend =
        undatedExpense ||
            readIssues.contains('Saved financial records could not be read.')
        ? null
        : _sum(financial.where((r) => r['direction'] == 'expense').map(amount));
    final undatedInvoices = invoices.any(
      (r) => dateOf(r['document_date']) == null,
    );
    final billedSales = undatedInvoices ? null : _sum(selected.map(salesOf));
    final paidRegister = OwnerReportPeriod(this, p, ReportTransactionBasis.invoices);
    final collected = _paidTotals.putIfAbsent(
      '${p.start.toIso8601String()}:${p.end.toIso8601String()}',
      () => paidRegister.paidInvoiceTotals,
    );
    final paidInvoiceCount = paidRegister.paidInvoices.length;
    final forecast = openJobs
        .map((job) => jobFigure(job, projected: true))
        .toList();
    final issues = <String>{...readIssues};
    if (ambiguousIncome) {
      issues.add(
        'Some payment entries need review before income can be totaled. Open period transactions for details.',
      );
    }
    if (undatedIncome || undatedExpense) {
      issues.add(
        'Some saved transactions have no date; period totals need review.',
      );
    }
    if (undatedInvoices) {
      issues.add(
        'Some saved invoices have no invoice date; invoiced sales totals need review.',
      );
    }
    final missing = selected.where((r) => salesOf(r) == null).length;
    if (missing > 0) {
      issues.add(
        '$missing invoice(s) are missing saved totals or tax details.',
      );
    }
    return OwnerReportSummary(
      {
        OwnerReportMetric.income: income,
        OwnerReportMetric.expenses: spend,
        OwnerReportMetric.net: income == null || spend == null
            ? null
            : income - spend,
        OwnerReportMetric.sales: collected.net,
        OwnerReportMetric.grossSales: collected.gross,
        OwnerReportMetric.billedSales: billedSales,
        OwnerReportMetric.billedTax: undatedInvoices
            ? null
            : _sum(selected.map(reportInvoiceTax)),
        OwnerReportMetric.billedGross: undatedInvoices
            ? null
            : _sum(selected.map((r) => reportCents(r['total_amount']))),
        OwnerReportMetric.projected: _sum(forecast.map((r) => r.profit)),
        OwnerReportMetric.openJobs: forecast.length,
        OwnerReportMetric.averageSale: collected.net == null
            ? null
            : paidInvoiceCount == 0
            ? 0
            : (collected.net! / paidInvoiceCount).round(),
        OwnerReportMetric.salesTax: collected.tax,
      },
      issues.toList(),
      selected,
    );
  }

  final Map<String, ReportJobFigure> _figures = {};
  ReportJobFigure jobFigure(ReportRow job, {required bool projected}) =>
      _figures.putIfAbsent(
        '${job['id']}:$projected',
        () => _jobFigure(job, projected),
      );
  ReportJobFigure _jobFigure(ReportRow job, bool projected) {
    final id = job['id']?.toString();
    final docs = invoices.where((r) => r['job_id'] == id).toList();
    final ids = docs.map((r) => r['id']).toSet();
    final issues = <String>[];
    final sales = docs.isEmpty ? null : _sum(docs.map(salesOf));
    if (sales == null) issues.add('Sales or tax details are not recorded.');
    var direct = 0;
    var expenseReadable = true;
    final seen = <String>{};
    for (final row in expenses) {
      if (!(row['job_id'] == id ||
          (row['job_id'] == null && ids.contains(row['document_id'])))) {
        continue;
      }
      final key = (row['allocation_id'] ?? row['id'])?.toString() ?? '';
      if (key.isEmpty ||
          !seen.add(key) ||
          row['payroll_operation_id'] != null ||
          row['direction'] == 'income') {
        continue;
      }
      final value = row['amount_minor'] is int
          ? row['amount_minor'] as int
          : reportCents(row['amount']);
      if (value == null || value < 0) {
        expenseReadable = false;
      } else {
        direct += value;
      }
    }
    if (readIssues.contains('Job expenses could not be read.')) {
      expenseReadable = false;
    }
    if (!expenseReadable) issues.add('Some job expenses are unreadable.');
    final credits = labor.where((r) => r['job_id'] == id).toList();
    var laborTotal = 0, laborKnown = true;
    final seenCredits = <String>{};
    for (final r in credits) {
      if (!seenCredits.add((r['allocation_id'] ?? r['id']).toString())) {
        continue;
      }
      final paid = reportInt(r['paid_cents']),
          paidMinutes = reportInt(r['paid_minutes']);
      final active =
          r['source_active'] != 0 && r['duplicate_of_task_id'] == null;
      if (r['duplicate_of_task_id'] != null && paidMinutes > 0) {
        laborKnown = false;
        continue;
      }
      if (!active && paidMinutes == 0) {
        if (r['duplicate_of_task_id'] == null &&
            r['completed'] == 1 &&
            reportInt(r['actual_minutes']) > 0) {
          laborKnown = false;
        }
        continue;
      }
      final actual = reportInt(r['actual_minutes']);
      final expected = projected
          ? math.max(actual, reportInt(r['estimated_minutes']))
          : actual;
      final minutes = active && (projected || r['completed'] == 1)
          ? expected
          : paidMinutes;
      final remaining = minutes - paidMinutes;
      final rate = reportInt(r['rate_cents']);
      if (remaining < 0 ||
          (r['paid_operation_id'] != null && paidMinutes == 0) ||
          (remaining > 0 && rate <= 0)) {
        laborKnown = false;
      } else {
        laborTotal += paid + (remaining * rate / 60).round();
      }
    }
    for (final doc in docs) {
      if (doc['lines'] is! List) {
        laborKnown = false;
        continue;
      }
      for (final line in (doc['lines'] as List).whereType<Map>().where(
        isInvoiceLaborLine,
      )) {
        if (line['id'] == null ||
            !credits.any(
              (r) =>
                  r['source_active'] != 0 &&
                  r['duplicate_of_task_id'] == null &&
                  r['invoice_id'] == doc['id'] &&
                  (r['source_line_id'] ?? r['labor_line_id']) == line['id'],
            )) {
          laborKnown = false;
        }
      }
    }
    if (!laborKnown) {
      issues.add('Mechanic hours, rates or original paid costs need review.');
    }
    return ReportJobFigure(
      job: job,
      sales: sales,
      expenses: expenseReadable ? direct : null,
      labor: laborKnown ? laborTotal : null,
      issues: issues,
    );
  }

  List<CustomerReportRow> customers(ReportPeriod p) {
    final groups = <String, CustomerReportRow>{};
    for (final doc in invoicesIn(p)) {
      final id = doc['customer_id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final group = groups.putIfAbsent(
        id,
        () => CustomerReportRow(
          id,
          doc['customer_name']?.toString() ?? 'Customer',
        ),
      );
      group.documents.add(doc);
      group.invoices++;
      final net = salesOf(doc);
      if (net != null) {
        group.sales += net;
      } else {
        group.salesKnown = false;
      }
      if (doc['_balance_known'] == false) group.balanceKnown = false;
      final gross = reportCents(doc['total_amount']);
      final received = reportInt(doc['_received_cents']);
      if (gross != null) {
        group.balance += math.max(0, gross - received);
      } else {
        group.balanceKnown = false;
      }
      if (doc['job_id'] != null) group.jobs.add(doc['job_id'].toString());
    }
    for (final group in groups.values) {
      final earlier = invoices.any(
        (r) =>
            r['customer_id'] == group.id &&
            (reportDate(r['document_date'])?.isBefore(p.start) ?? false),
      );
      group.newCustomer = !earlier;
      for (final id in group.jobs) {
        final job = jobs.where((r) => r['id'] == id).firstOrNull;
        final all = invoices
            .where((r) => r['job_id'] == id)
            .map((r) => r['id'])
            .toSet();
        final selected = group.documents
            .where((r) => r['job_id'] == id)
            .map((r) => r['id'])
            .toSet();
        if (job == null || all.difference(selected).isNotEmpty) {
          group.profit = null;
          break;
        }
        final figure = jobFigure(job, projected: false);
        if (figure.profit == null) {
          group.profit = null;
          break;
        }
        group.profit = group.profit! + figure.profit!;
      }
      if (group.documents.any(
        (r) => salesOf(r) == null || r['job_id'] == null,
      )) {
        group.profit = null;
      }
    }
    return groups.values.toList()..sort((a, b) => b.sales.compareTo(a.sales));
  }

  List<ItemReportRow> items(ReportPeriod p) {
    final groups = <String, ItemReportRow>{};
    for (final doc in invoicesIn(p)) {
      final lines = (doc['lines'] as List? ?? const []).whereType<Map>();
      for (final raw in lines) {
        final line = Map<String, dynamic>.from(raw);
        final name = line['name']?.toString() ?? 'Item';
        final laborLine = isInvoiceLaborLine(line);
        final id =
            line['item_id']?.toString() ??
            'manual:${laborLine ? 'labor' : 'item'}:${name.trim().toLowerCase()}';
        final group = groups.putIfAbsent(
          id,
          () => ItemReportRow(
            id,
            name,
            laborLine,
            discount: line['line_kind'] == 'discount',
          ),
        );
        final qty = reportNumber(line['quantity']);
        final revenue =
            reportCents(line['net_amount']) ??
            reportCents(qty * reportNumber(line['unit_price']));
        group.quantity += qty;
        group.revenue += revenue ?? 0;
        group.invoiceIds.add(doc['id'].toString());
        int? cost;
        if (line['line_kind'] == 'discount') {
          cost = 0;
        } else if (!laborLine) {
          final unit = reportCents(line['unit_cost'] ?? line['cost_price']);
          cost = unit == null ? null : (unit * qty).round();
          final allocations = expenses
              .where(
                (e) =>
                    line['id'] != null &&
                    e['document_id'] == doc['id'] &&
                    (e['source_line_id'] == line['id'] ||
                        e['sales_document_line_id'] == line['id']),
              )
              .toList();
          if (line['id'] != null && allocations.isNotEmpty) {
            cost = _sum(
              allocations.map(
                (e) => e['amount_minor'] is int
                    ? e['amount_minor'] as int
                    : reportCents(e['amount']),
              ),
            );
          }
        } else {
          final byId = <String, ReportRow>{};
          for (final r in labor.where(
            (r) =>
                line['id'] != null &&
                r['source_line_id'] == line['id'] &&
                r['invoice_id'] == doc['id'],
          )) {
            byId[(r['allocation_id'] ?? r['id']).toString()] = r;
          }
          final parts = byId.values
              .where(
                (r) =>
                    (r['source_active'] != 0 &&
                        r['duplicate_of_task_id'] == null) ||
                    reportInt(r['paid_minutes']) > 0 ||
                    (r['duplicate_of_task_id'] == null &&
                        r['completed'] == 1 &&
                        reportInt(r['actual_minutes']) > 0),
              )
              .toList();
          if (parts.isNotEmpty) {
            cost = _sum(
              parts.map((r) {
                if (r['duplicate_of_task_id'] != null ||
                    (r['source_active'] == 0 &&
                        reportInt(r['paid_minutes']) == 0)) {
                  return null;
                }
                final actual = reportInt(r['actual_minutes']);
                final paidMinutes = reportInt(r['paid_minutes']);
                final remaining = r['completed'] == 1
                    ? actual - paidMinutes
                    : 0;
                final rate = reportInt(r['rate_cents']);
                if (remaining < 0 ||
                    (remaining > 0 && rate <= 0) ||
                    (r['paid_operation_id'] != null && paidMinutes == 0)) {
                  return null;
                }
                return reportInt(r['paid_cents']) +
                    (remaining * rate / 60).round();
              }),
            );
          }
        }
        if (cost == null || group.cost == null) {
          group.cost = null;
        } else {
          group.cost = group.cost! + cost;
        }
      }
    }
    return groups.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
  }
}
