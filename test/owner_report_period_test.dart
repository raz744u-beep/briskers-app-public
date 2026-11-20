import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/owner_report_models.dart';
import 'package:briskers_app/core/owner_report_payment_merge.dart';

final period = ReportPeriod(DateTime(2026, 11, 1), DateTime(2026, 11, 20));
ReportRow invoice(
  String id, {
  num gross = 110,
  num tax = 10,
  String date = '2026-11-19',
}) => {
  'id': id,
  'kind': 'invoice',
  'business_id': 'shop',
  'customer_name': 'Customer $id',
  'document_number': id,
  'document_date': date,
  'total_amount': gross,
  'tax_amount': tax,
  'lines': <ReportRow>[],
};
ReportRow cash(
  String id, {
  String? doc = 'a',
  num amount = 110,
  String date = '2026-11-19',
  String? payment,
}) => {
  'id': id,
  'direction': 'income',
  'document_id': doc,
  'amount': amount,
  'transaction_date': date,
  'invoice_payment_id': ?payment,
};
ReportRow receipt(
  String id, {
  String doc = 'a',
  num amount = 110,
  String state = 'posted',
  String? tx,
  String? op,
}) => {
  'receipt_id': id,
  'invoice_id': doc,
  'amount': amount,
  'transaction_date': '2026-11-19',
  'receipt_state': state,
  'transaction_id': ?tx,
  'operation_id': ?op,
};
OwnerReportData data(List<ReportRow> docs, List<ReportRow> tx) =>
    OwnerReportData(
      business: 'shop',
      invoices: docs,
      transactions: tx,
      jobs: [],
      expenses: [],
      labor: [],
    );
List<ReportRow> merge(
  List<ReportRow> financial,
  List<ReportRow> receipts, {
  List<ReportRow>? docs,
  Map<String, String> aliases = const {},
}) => OwnerReportPaymentMerge.combine(
  financial: financial,
  receipts: receipts,
  invoices: docs ?? [invoice('a')],
  aliases: aliases,
);

void main() {
  test(
    'displayed invoice arithmetic is exact and all three totals use the same period rows',
    () {
      final d = data([invoice('a', gross: 35913.44, tax: 3190.50)], []);
      final entries = OwnerReportPeriod(
        d,
        period,
        ReportTransactionBasis.invoices,
      );
      expect(entries.totals.gross, 3591344);
      expect(entries.totals.net, 3272294);
      expect(entries.totals.tax, 319050);
      expect(entries.totals.net! + entries.totals.tax!, entries.totals.gross);
      expect(
        d.summary(period).values[OwnerReportMetric.billedGross],
        entries.totals.gross,
      );
      expect(
        d.summary(period).values[OwnerReportMetric.billedSales],
        entries.totals.net,
      );
    },
  );
  test(
    'a legitimate payment-date versus invoice-date difference remains explicit',
    () {
      final d = data(
        [
          invoice('a', gross: 35913.44, tax: 3190.50),
          invoice('old', gross: 31869.07, tax: 0, date: '2026-10-10'),
        ],
        [
          cash('now', amount: 35913.44),
          cash('older', doc: 'old', amount: 31869.07),
        ],
      );
      expect(d.summary(period).values[OwnerReportMetric.income], 6778251);
      expect(
        OwnerReportPeriod(
          d,
          period,
          ReportTransactionBasis.invoices,
        ).totals.gross,
        3591344,
      );
      final received = OwnerReportPeriod(
        d,
        period,
        ReportTransactionBasis.payments,
      );
      expect(received.entries, hasLength(2));
      expect(received.totals.gross, 6778251);
      expect(
        received.totals.net! + received.totals.tax!,
        received.totals.gross,
      );
    },
  );
  test(
    'the same payment linked by operation ID is represented once and retains fee reporting',
    () {
      final rows = merge(
        [
          {
            ...cash('financial'),
            'operation_id': 'op',
            'reporting_status': 'verified',
            'reporting_amount': 107,
          },
        ],
        [receipt('server', op: 'op', state: 'local_finalized')],
      );
      expect(rows, hasLength(1));
      expect(
        data([
          invoice('a'),
        ], rows).summary(period).values[OwnerReportMetric.income],
        10700,
      );
      final totals = OwnerReportPeriod(
        data([invoice('a')], rows),
        period,
        ReportTransactionBasis.payments,
      ).totals;
      expect(totals.gross, 11000);
      expect(totals.tax, 1000);
      expect(totals.net, 10000);
      expect(totals.fees, 300);
    },
  );
  test(
    'saved invoice payment transaction links reconcile a stale receipt cache without matching amounts',
    () {
      final doc = invoice('a')
        ..['payments'] = [
          {'id': 'payment', 'transaction_id': 'financial'},
        ];
      final rows = merge(
        [cash('financial')],
        [receipt('payment', state: 'local_finalized')],
        docs: [doc],
      );
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'financial');
    },
  );
  test(
    'split invoice allocations replace the whole transaction once and retain its complete income',
    () {
      final docs = [
        invoice('a', gross: 33, tax: 3),
        invoice('b', gross: 77, tax: 7),
      ];
      final rows = merge(
        [
          {
            ...cash('financial', doc: null),
            'reporting_status': 'verified',
            'reporting_amount': 107,
          },
        ],
        [
          receipt('p', amount: 33, tx: 'financial'),
          receipt('q', doc: 'b', amount: 77, tx: 'financial'),
        ],
        docs: docs,
      );
      expect(rows, hasLength(2));
      final totals = OwnerReportPeriod(
        data(docs, rows),
        period,
        ReportTransactionBasis.payments,
      ).totals;
      expect(totals.gross, 11000);
      expect(totals.retained, 10700);
      expect(totals.tax, 1000);
      expect(totals.net, 10000);
    },
  );
  test(
    'legacy entries with no exact payment link cannot silently double income or be guessed away',
    () {
      final f = [cash('financial')],
          r = [receipt('p', state: 'local_finalized')];
      final before = jsonEncode([f, r]);
      final rows = merge(f, r);
      expect(rows, hasLength(2));
      expect(rows.last['_report_payment_review'], isTrue);
      expect(
        data([
          invoice('a'),
        ], rows).summary(period).values[OwnerReportMetric.income],
        isNull,
      );
      expect(
        OwnerReportPeriod(
          data([invoice('a')], rows),
          period,
          ReportTransactionBasis.payments,
        ).totals.gross,
        isNull,
      );
      expect(jsonEncode([f, r]), before);
    },
  );
  test(
    'distinct posted partial receipts remain separate even on the same invoice',
    () {
      final rows = merge(
        [cash('f', amount: 50, payment: 'p')],
        [receipt('q', amount: 60)],
      );
      expect(rows, hasLength(2));
      expect(
        data([
          invoice('a'),
        ], rows).summary(period).values[OwnerReportMetric.income],
        11000,
      );
      final totals = OwnerReportPeriod(
        data([invoice('a')], rows),
        period,
        ReportTransactionBasis.payments,
      ).totals;
      expect(totals.tax, 1000);
      expect(totals.net, 10000);
    },
  );
  test(
    'a proven new local capture is additional; a replay with an unknown acknowledgement needs review',
    () {
      final f = [cash('f', amount: 50, payment: 'p')];
      var rows = merge(f, [
        {
          ...receipt('local', amount: 60, state: 'local'),
          '_report_new_local_receipt': true,
        },
      ]);
      expect(
        data([
          invoice('a'),
        ], rows).summary(period).values[OwnerReportMetric.income],
        11000,
      );
      rows = merge(f, [receipt('local', amount: 60, state: 'local')]);
      expect(
        data([
          invoice('a'),
        ], rows).summary(period).values[OwnerReportMetric.income],
        isNull,
      );
    },
  );
  test('same amount and name never merge different invoice payments', () {
    final docs = [invoice('a'), invoice('b')];
    final rows = merge([cash('f')], [receipt('q', doc: 'b')], docs: docs);
    expect(rows, hasLength(2));
    expect(
      data(docs, rows).summary(period).values[OwnerReportMetric.income],
      22000,
    );
  });
  test(
    'duplicate receipt identities merge once and conflicting amounts require review',
    () {
      var rows = merge([], [
        receipt('p', op: 'op'),
        receipt('q', op: 'op', state: 'local_finalized'),
      ]);
      expect(rows, hasLength(1));
      expect(reportCents(rows.single['amount']), 11000);
      rows = merge([], [
        receipt('p', op: 'op'),
        receipt('q', op: 'op', amount: 100),
      ]);
      expect(rows.single['_report_payment_review'], isTrue);
    },
  );
  test(
    'partial payment tax rounding carries the original remaining cent between months',
    () {
      final d = data(
        [invoice('a', gross: .03, tax: .01)],
        [
          cash('p1', amount: .01, date: '2026-10-31'),
          cash('p2', amount: .01),
          cash('p3', amount: .01),
        ],
      );
      final totals = OwnerReportPeriod(
        d,
        period,
        ReportTransactionBasis.payments,
      ).totals;
      expect(totals.gross, 2);
      expect(totals.tax, 1);
      expect(totals.net, 1);
    },
  );
  test('a refund reverses the matching fraction of original invoice tax', () {
    final d = data(
      [invoice('a')],
      [cash('paid', date: '2026-10-31'), cash('refund', amount: -55)],
    );
    final totals = OwnerReportPeriod(
      d,
      period,
      ReportTransactionBasis.payments,
    ).totals;
    expect(totals.gross, -5500);
    expect(totals.tax, -500);
    expect(totals.net, -5000);
  });
  test(
    'missing historical tax is unknown, never calculated from the current shop rate',
    () {
      final d = data([invoice('a')..remove('tax_amount')], [cash('f')]);
      final totals = OwnerReportPeriod(
        d,
        period,
        ReportTransactionBasis.payments,
      ).totals;
      expect(totals.gross, 11000);
      expect(totals.tax, isNull);
      expect(totals.net, isNull);
    },
  );
  test(
    'non-invoice income keeps its recorded tax treatment and expenses are excluded',
    () {
      final d = data([], [
        {...cash('other', doc: null, amount: 25), 'tax_amount': 0},
        {...cash('expense', doc: null, amount: 30), 'direction': 'expense'},
      ]);
      final totals = OwnerReportPeriod(
        d,
        period,
        ReportTransactionBasis.payments,
      ).totals;
      expect(totals.gross, 2500);
      expect(totals.tax, 0);
      expect(totals.net, 2500);
    },
  );
  test(
    'two financial rows claiming the same payment cannot produce a confident doubled total',
    () {
      final rows = merge([
        cash('f1', payment: 'p'),
        cash('f2', payment: 'p'),
      ], []);
      expect(
        data([
          invoice('a'),
        ], rows).summary(period).values[OwnerReportMetric.income],
        isNull,
      );
    },
  );
  test(
    'partial multi-invoice coverage keeps the known transaction but leaves tax unallocated',
    () {
      final rows = merge(
        [cash('f', doc: null)],
        [
          receipt('p', amount: 20, tx: 'f'),
          receipt('q', doc: 'b', amount: 30, tx: 'f'),
        ],
        docs: [invoice('a'), invoice('b')],
      );
      expect(rows, hasLength(1));
      expect(rows.single['_report_tax_review'], isTrue);
      final totals = OwnerReportPeriod(
        data([invoice('a'), invoice('b')], rows),
        period,
        ReportTransactionBasis.payments,
      ).totals;
      expect(totals.gross, 11000);
      expect(totals.tax, isNull);
    },
  );
  test(
    'explicit invoice aliases reconcile exact receipt IDs, not invoice numbers',
    () {
      final rows = merge(
        [cash('f', payment: 'p')],
        [receipt('p', doc: 'alias')],
        aliases: {'alias': 'a'},
      );
      expect(rows, hasLength(1));
      expect(rows.single['document_id'], 'a');
    },
  );
  test('unknown dated sales cannot produce complete-looking period totals', () {
    final d = data([invoice('a'), invoice('unknown', date: '')], []);
    expect(
      OwnerReportPeriod(
        d,
        period,
        ReportTransactionBasis.invoices,
      ).totals.gross,
      isNull,
    );
    expect(d.summary(period).values[OwnerReportMetric.billedGross], isNull);
    expect(d.summary(period).values[OwnerReportMetric.grossSales], 0);
  });
  test(
    'abandoned invoices stay out of cash totals and remain in unpaid review',
    () {
      final d = data([
        for (var i = 0; i < 3; i++)
          invoice('abandoned$i', gross: 5000, tax: 400),
      ], []);
      final values = d.summary(period).values;
      expect(values[OwnerReportMetric.income], 0);
      expect(values[OwnerReportMetric.sales], 0);
      expect(values[OwnerReportMetric.salesTax], 0);
      expect(values[OwnerReportMetric.grossSales], 0);
      expect(values[OwnerReportMetric.billedGross], 1500000);
      final unpaid = OwnerReportPeriod(
        d,
        period,
        ReportTransactionBasis.unpaid,
      );
      expect(unpaid.entries, hasLength(3));
      expect(unpaid.totals.amountDue, 1500000);
      expect(unpaid.totals.paid, 0);
    },
  );
  test(
    'partial payment counts only collected cash and the next receipt belongs to its own month',
    () {
      final d = data(
        [invoice('a')],
        [
          cash('first', amount: 55),
          cash('second', amount: 55, date: '2026-12-02'),
        ],
      );
      final nov = d.summary(period).values;
      final dec = d
          .summary(ReportPeriod(DateTime(2026, 12), DateTime(2026, 12, 31)))
          .values;
      for (final values in [nov, dec]) {
        expect(values[OwnerReportMetric.grossSales], 5500);
        expect(values[OwnerReportMetric.sales], 5000);
        expect(values[OwnerReportMetric.salesTax], 500);
      }
      final novRows = OwnerReportPeriod(
        d,
        period,
        ReportTransactionBasis.payments,
        now: DateTime(2026, 12, 5),
      );
      expect(novRows.totals.amountDue, 5500);
      expect(novRows.totals.paid, 5500);
      expect(d.invoices.single['document_date'], '2026-11-19');
    },
  );
  test(
    'multiple receipts do not duplicate the invoice balance in the footer',
    () {
      final rows = OwnerReportPeriod(
        data(
          [invoice('a')],
          [cash('one', amount: 20), cash('two', amount: 30)],
        ),
        period,
        ReportTransactionBasis.payments,
      );
      expect(rows.totals.amountDue, 6000);
      expect(rows.totals.paid, 5000);
    },
  );
  test(
    'closed invoice paid cache supplies current balance but cannot invent dated cash',
    () {
      final d = data([
        {...invoice('a'), 'status': 'closed', 'paid_amount': 110},
      ], []);
      expect(
        OwnerReportPeriod(
          d,
          period,
          ReportTransactionBasis.unpaid,
          now: DateTime(2026, 11, 20),
        ).entries,
        isEmpty,
      );
      expect(d.summary(period).values[OwnerReportMetric.income], 0);
      expect(d.summary(period).values[OwnerReportMetric.salesTax], 0);
      final past = OwnerReportPeriod(
        d,
        period,
        ReportTransactionBasis.invoices,
        now: DateTime(2026, 12, 5),
      );
      expect(past.entries.single.amountDue, isNull);
    },
  );
  test('historical saved net or complete saved line tax recovers tax without current settings', () {
    final legacy = invoice('a')..remove('tax_amount');
    expect(reportInvoiceTax({...legacy, 'net_amount': 100}), 1000);
    expect(reportInvoiceTax({...legacy, 'lines': [{'net_amount': 100, 'tax_rate': 0.1}]}), 1000);
    expect(reportInvoiceTax({...legacy, 'lines': [{'net_amount': 100, 'tax_rate': 0.03}]}), isNull);
    final d = data([{...legacy, 'net_amount': 100}], [cash('receipt')]);
    expect(d.summary(period).values[OwnerReportMetric.salesTax], 1000);
    expect(d.summary(period).values[OwnerReportMetric.sales], 10000);
  });

}
