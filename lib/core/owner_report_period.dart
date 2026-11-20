part of 'owner_report_models.dart';

enum ReportTransactionBasis { invoices, payments, unpaid }

int? reportIncomeCents(ReportRow r) => reportCents(
  r['reporting_status'] == 'verified'
      ? r['reporting_amount'] ?? r['amount']
      : r['amount'],
);

/// Recover historical tax only from saved amounts that reconcile to the saved total.
int? reportInvoiceTax(ReportRow invoice) {
  final explicit = reportCents(invoice['tax_amount']);
  if (explicit != null) { return explicit; }
  final gross = reportCents(invoice['total_amount']);
  final net = reportCents(invoice['net_amount']);
  if (gross != null && net != null && gross >= net) { return gross - net; }
  final lines = invoice['lines'];
  if (gross == null || lines is! List || lines.isEmpty) { return null; }
  var savedNet = 0, savedTax = 0;
  for (final line in lines) {
    if (line is! Map) { return null; }
    final amount = reportCents(line['net_amount']);
    final rate = num.tryParse(line['tax_rate']?.toString() ?? '');
    if (amount == null || rate == null || !rate.isFinite || rate < 0) { return null; }
    savedNet += amount;
    savedTax += (amount * rate).round();
  }
  return savedNet + savedTax == gross ? savedTax : null;
}

class ReportPeriodEntry {
  ReportPeriodEntry({
    required this.row,
    this.invoice,
    required this.gross,
    required this.tax,
    required this.retained,
    this.review = false,
    this.amountDue,
    this.paid,
  });
  final ReportRow row;
  final ReportRow? invoice;
  final int? gross, tax, retained;
  final int? amountDue, paid;
  final bool review;
  int? get net => gross == null || tax == null ? null : gross! - tax!;
  String get invoiceNumber =>
      (invoice?['document_number'] ?? row['document_number'] ?? '').toString();
  String get name =>
      (invoice?['customer_name'] ??
              row['counterparty'] ??
              row['customer_name'] ??
              'Other income')
          .toString();
  late final DateTime? date = reportDate(
    row['transaction_date'] ?? row['document_date'],
  );
}

class ReportPeriodTotals {
  ReportPeriodTotals(List<ReportPeriodEntry> rows, {bool unavailable = false}) {
    int? sum(int? Function(ReportPeriodEntry) value) {
      if (unavailable || rows.any((r) => r.review)) return null;
      var total = 0;
      for (final r in rows) {
        final n = value(r);
        if (n == null) return null;
        total += n;
      }
      return total;
    }

    gross = sum((r) => r.gross);
    net = sum((r) => r.net);
    tax = sum((r) => r.tax);
    retained = sum((r) => r.retained);
    paid = sum((r) => r.paid);
    final byInvoice = <String, ReportPeriodEntry>{
      for (final r in rows)
        if (r.invoice != null) r.invoice!['id'].toString(): r,
    };
    amountDue = unavailable || byInvoice.values.any((r) => r.amountDue == null)
        ? null
        : byInvoice.values.fold<int>(0, (n, r) => n + r.amountDue!);
  }
  late final int? gross, net, tax, retained, amountDue, paid;
  int? get fees =>
      gross == null || retained == null ? null : gross! - retained!;
}

/// The same selected rows supply the table and its totals. Tax on partial
/// receipts uses the invoice's saved tax, with cumulative integer rounding so
/// the last receipt retains the exact remaining cent across period boundaries.
class OwnerReportPeriod {
  OwnerReportPeriod(
    this.data,
    this.period,
    this.basis, {
    DateTime? now,
    this.includeBalances = true,
  }) : now = now ?? DateTime.now();
  final DateTime now;
  final bool includeBalances;
  final OwnerReportData data;
  final ReportPeriod period;
  final ReportTransactionBasis basis;
  bool get undated => basis != ReportTransactionBasis.payments
      ? data.invoices.any((r) => data.dateOf(r['document_date']) == null)
      : data.transactions.any(
          (r) =>
              r['direction'] == 'income' &&
              data.dateOf(r['transaction_date']) == null,
        );
  bool get unavailable =>
      undated ||
      (basis == ReportTransactionBasis.payments &&
          data.readIssues.contains(
            'Saved financial records could not be read.',
          ));

  late final List<ReportPeriodEntry> entries = _entries();
  ReportPeriodTotals get totals =>
      ReportPeriodTotals(entries, unavailable: unavailable);
  List<ReportPeriodEntry> _entries() {
    if (basis != ReportTransactionBasis.payments) {
      final docs = basis == ReportTransactionBasis.invoices
          ? data.invoicesIn(period)
          : data.invoices.where((d) {
              final date = data.dateOf(d['document_date']);
              return date == null ||
                  !date.isAfter(ReportPeriod.day(period.end));
            }).toList();
      return [for (final doc in docs) _invoiceEntry(doc)]
          .where(
            (r) =>
                basis != ReportTransactionBasis.unpaid ||
                r.amountDue == null ||
                r.amountDue! > 0,
          )
          .toList()
        ..sort(_descending);
    }
    final all = data._paymentEntries ??= _allPayments();
    return [
      for (final e in all)
        if (data.inPeriod(period, e.row['transaction_date']))
          ReportPeriodEntry(
            row: e.row,
            invoice: e.invoice,
            gross: e.gross,
            tax: e.tax,
            retained: e.retained,
            review: e.review,
            paid: e.review ? null : e.gross,
            amountDue: includeBalances && e.invoice != null
                ? _balance(e.invoice!).due
                : null,
          ),
    ]..sort(_descending);
  }

  List<ReportPeriodEntry> _allPayments() {
    final docs = {for (final d in data.invoices) d['id'].toString(): d};
    final all =
        data.transactions.where((r) => r['direction'] == 'income').toList()
          ..sort((a, b) {
            final cmp = (a['transaction_date']?.toString() ?? '').compareTo(
              b['transaction_date']?.toString() ?? '',
            );
            return cmp != 0
                ? cmp
                : a['id'].toString().compareTo(b['id'].toString());
          });
    final received = <String, int>{};
    final allocatedTax = <String, int>{};
    final unclearTax = <String>{};
    final selected = <ReportPeriodEntry>[];
    for (final r in all) {
      final id = (r['document_id'] ?? r['invoice_id'])?.toString();
      final doc = docs[id];
      final amount = reportCents(r['amount']);
      final review = r['_report_payment_review'] == true;
      int? tax;
      if (!review && r['_report_tax_review'] != true && amount != null) {
        if (r['tax_amount'] != null) {
          tax = reportCents(r['tax_amount']);
        } else if (doc != null && !unclearTax.contains(id)) {
          final gross = reportCents(doc['total_amount']),
              invoiceTax = reportInvoiceTax(doc);
          if (gross != null &&
              invoiceTax != null &&
              gross > 0 &&
              invoiceTax >= 0 &&
              invoiceTax <= gross) {
            final before = received[id] ?? 0, after = before + amount;
            int allocation(int n) =>
                (n.clamp(0, gross) * invoiceTax * 2 + gross) ~/ (gross * 2);
            final delta = allocation(after) - (allocatedTax[id] ?? 0);
            tax = amount >= 0 ? delta.clamp(0, amount) : delta.clamp(amount, 0);
          } else if (gross == 0 && invoiceTax == 0 && amount == 0) {
            tax = 0;
          }
        }
      }
      if (id != null && amount != null) {
        if (!review) received[id] = (received[id] ?? 0) + amount;
        if (tax == null || review) {
          unclearTax.add(id);
        } else {
          allocatedTax[id] = (allocatedTax[id] ?? 0) + tax;
        }
      }
      {
        selected.add(
          ReportPeriodEntry(
            row: r,
            invoice: doc,
            gross: amount,
            tax: tax,
            retained: reportIncomeCents(r),
            review: review,
            paid: review ? null : amount,
          ),
        );
      }
    }
    return selected..sort(_descending);
  }

  final _paidAtEnd = <String, int>{}, _allPaid = <String, int>{};
  final _unclearBalances = <String>{};
  bool _balancesPrepared = false;
  void _prepareBalances() {
    if (_balancesPrepared) return;
    _balancesPrepared = true;
    for (final row in data.transactions.where(
      (r) => r['direction'] == 'income',
    )) {
      final id = (row['document_id'] ?? row['invoice_id'])?.toString();
      if (id == null) continue;
      final date = data.dateOf(row['transaction_date']),
          amount = reportCents(row['amount']);
      if (date == null || amount == null) {
        _unclearBalances.add(id);
        continue;
      }
      if (row['_report_payment_review'] == true) {
        if (!date.isAfter(ReportPeriod.day(period.end))) {
          _unclearBalances.add(id);
        }
        continue;
      }
      _allPaid[id] = (_allPaid[id] ?? 0) + amount;
      if (!date.isAfter(ReportPeriod.day(period.end))) {
        _paidAtEnd[id] = (_paidAtEnd[id] ?? 0) + amount;
      }
    }
  }

  final _balances = <String, ({int? due, int? paid})>{};
  ({int? due, int? paid}) _balance(ReportRow doc) => _balances.putIfAbsent(
    doc['id'].toString(),
    () {
      final gross = reportCents(doc['total_amount']);
      if (gross == null) return (due: null, paid: null);
      _prepareBalances();
      var dated = _paidAtEnd[doc['id']] ?? 0;
      final allDated = _allPaid[doc['id']] ?? 0;
      if (_unclearBalances.contains(doc['id'])) return (due: null, paid: null);
      final cached = doc['_received_cents'] is int
          ? doc['_received_cents'] as int
          : reportCents(doc['paid_amount']);
      final current = !ReportPeriod.day(
        period.end,
      ).isBefore(ReportPeriod.day(now));
      final settled = const {
        'paid',
        'closed',
      }.contains(doc['status']?.toString().toLowerCase());
      if (current &&
          doc['_balance_known'] != false &&
          cached != null &&
          cached > dated) {
        dated = cached;
      } else if (!current && cached != null && cached > allDated) {
        return (due: null, paid: null);
      }
      if ((settled && dated < gross) ||
          (doc['_balance_known'] == false && dated < gross)) {
        return (due: null, paid: null);
      }
      return (due: (gross - dated).clamp(0, 0x7FFFFFFFFFFFFFFF), paid: dated);
    },
  );
  ReportPeriodEntry _invoiceEntry(ReportRow doc) {
    final balance = _balance(doc);
    return ReportPeriodEntry(
      row: doc,
      invoice: doc,
      gross: reportCents(doc['total_amount']),
      tax: reportInvoiceTax(doc),
      retained: reportCents(doc['total_amount']),
      amountDue: balance.due,
      paid: balance.paid,
    );
  }

  static int _descending(ReportPeriodEntry a, ReportPeriodEntry b) =>
      (b.date ?? DateTime(1900)).compareTo(a.date ?? DateTime(1900));
}
