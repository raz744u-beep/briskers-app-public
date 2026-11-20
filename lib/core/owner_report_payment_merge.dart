import 'owner_report_models.dart';

/// Read-only identity reconciliation for reporting. Never equate payments by
/// amount, name, date or invoice number; never modify the financial ledger.
class OwnerReportPaymentMerge {
  static List<ReportRow> combine({
    required List<ReportRow> financial,
    required List<ReportRow> receipts,
    required List<ReportRow> invoices,
    Map<String, String> aliases = const {},
  }) {
    String? document(ReportRow r) {
      final id = (r['invoice_id'] ?? r['document_id'])?.toString();
      return aliases[id] ?? id;
    }

    Set<String> paymentKeys(ReportRow r, {bool receipt = false}) => {
      for (final key
          in receipt
              ? ['receipt_id', 'operation_id', 'server_payment_id']
              : [
                  'invoice_payment_id',
                  'payment_id',
                  'operation_id',
                  'client_operation_id',
                  'source_receipt_id',
                ])
        if ((r[key]?.toString() ?? '').isNotEmpty) r[key].toString(),
    };
    final rows = financial
        .map(
          (r) => <String, dynamic>{
            ...r,
            if (document(r) != null) 'document_id': document(r),
          },
        )
        .toList();
    final seenFinancialPayments = <String, ReportRow>{};
    for (final row in rows.where((r) => r['direction'] == 'income')) {
      for (final key in paymentKeys(row)) {
        final identity = '${document(row)}:$key';
        final previous = seenFinancialPayments[identity];
        if (previous != null && previous['id'] != row['id']) {
          previous['_report_payment_review'] = true;
          row['_report_payment_review'] = true;
        }
        seenFinancialPayments[identity] = row;
      }
    }
    final invoiceById = {for (final i in invoices) i['id'].toString(): i};
    final links = <String, ReportRow>{};
    for (final invoice in invoices) {
      for (final raw
          in (invoice['payments'] as List? ?? const []).whereType<Map>()) {
        final p = Map<String, dynamic>.from(raw);
        for (final key in ['id', 'operation_id', 'server_payment_id']) {
          if (p[key] != null) links['${invoice['id']}:${p[key]}'] = p;
        }
      }
    }
    final unique = <ReportRow>[];
    final receiptByKey = <String, ReportRow>{};
    for (final original in receipts) {
      final r = <String, dynamic>{
        ...original,
        'invoice_id': document(original),
      };
      final keys = paymentKeys(r, receipt: true);
      if (keys.isEmpty) continue;
      final previous = keys
          .map((key) => receiptByKey['${document(r)}:$key'])
          .nonNulls
          .firstOrNull;
      if (previous != null) {
        if (reportCents(previous['amount']) != reportCents(r['amount'])) {
          previous['_report_payment_review'] = true;
        }
        for (final key in keys) {
          receiptByKey['${document(r)}:$key'] = previous;
        }
        continue;
      }
      for (final key in keys) {
        final p = links['${document(r)}:$key'];
        final tx = p?['transaction_id'] ?? p?['financial_transaction_id'];
        if (tx != null && r['transaction_id'] == null) r['transaction_id'] = tx;
      }
      unique.add(r);
      for (final key in keys) {
        receiptByKey['${document(r)}:$key'] = r;
      }
    }
    final financialById = <String, List<ReportRow>>{};
    final financialByPayment = <String, List<ReportRow>>{};
    final financialByInvoice = <String, List<ReportRow>>{};
    for (final row in rows.where((r) => r['direction'] == 'income')) {
      (financialById[row['id'].toString()] ??= []).add(row);
      for (final key in paymentKeys(row)) {
        (financialByPayment[key] ??= []).add(row);
      }
      final doc = document(row);
      if (doc != null) {
        (financialByInvoice[doc] ??= []).add(row);
      }
    }
    final matched = <String, List<ReportRow>>{};
    final supplemental = <ReportRow>[];
    for (final receipt in unique) {
      final keys = paymentKeys(receipt, receipt: true);
      final candidates = <ReportRow>{
        ...?financialById[receipt['transaction_id']?.toString()],
        for (final key in keys) ...?financialByPayment[key],
      };
      final matches = candidates
          .where((f) => document(f) == null || document(f) == document(receipt))
          .toList();
      if (matches.length == 1) {
        (matched[matches.single['id'].toString()] ??= []).add(receipt);
      } else {
        final sameInvoice =
            financialByInvoice[document(receipt)] ?? const <ReportRow>[];
        final serverId =
            receipt['server_payment_id'] ??
            (receipt['receipt_state'] == 'posted'
                ? receipt['receipt_id']
                : null);
        final distinctServerPayments =
            serverId != null &&
            sameInvoice.every(
              (f) =>
                  f['invoice_payment_id'] != null &&
                  f['invoice_payment_id'] != serverId,
            );
        supplemental.add({
          ...receipt,
          if (matches.length > 1 ||
              (sameInvoice.isNotEmpty &&
                  !distinctServerPayments &&
                  receipt['_report_new_local_receipt'] != true))
            '_report_payment_review': true,
        });
      }
    }
    ReportRow decorate(ReportRow f, ReportRow receipt) {
      final id = document(receipt);
      final doc = invoiceById[id];
      return {
        ...f,
        'document_id': id,
        'document_number':
            doc?['document_number'] ??
            receipt['document_number'] ??
            f['document_number'],
        'counterparty':
            doc?['customer_name'] ??
            receipt['customer_name'] ??
            f['counterparty'],
        if (receipt['_report_payment_review'] == true)
          '_report_payment_review': true,
      };
    }

    final result = <ReportRow>[];
    for (final row in rows) {
      final parts = matched[row['id'].toString()] ?? const <ReportRow>[];
      if (parts.isEmpty) {
        result.add(row);
        continue;
      }
      final gross = reportCents(row['amount']);
      final sum = parts.fold<int>(
        0,
        (n, r) => n + (reportCents(r['amount']) ?? 0),
      );
      if (parts.length == 1) {
        result.add({
          ...decorate(row, parts.single),
          if (sum != gross) '_report_tax_review': true,
        });
      } else if (gross != null && gross > 0 && sum == gross) {
        final retained = reportCents(
          row['reporting_status'] == 'verified'
              ? row['reporting_amount'] ?? row['amount']
              : row['amount'],
        );
        var allocatedGross = 0, allocatedRetained = 0;
        for (final part in parts) {
          final amount = reportCents(part['amount'])!;
          allocatedGross += amount;
          final cumulativeRetained = retained == null
              ? null
              : (allocatedGross * retained / gross).round();
          result.add(
            decorate({
              ...row,
              'id':
                  '${row['id']}:${part['receipt_id'] ?? part['operation_id'] ?? part['server_payment_id']}',
              'amount': amount / 100,
              if (cumulativeRetained != null)
                'reporting_amount':
                    (cumulativeRetained - allocatedRetained) / 100,
            }, part),
          );
          allocatedRetained = cumulativeRetained ?? 0;
        }
      } else {
        result.add({...row, '_report_tax_review': true});
      }
    }
    for (final r in supplemental) {
      result.add(
        decorate({
          'id':
              'report-receipt:${r['receipt_id'] ?? r['operation_id'] ?? r['server_payment_id']}',
          'direction': 'income',
          'amount': r['amount'],
          'transaction_date': r['transaction_date'],
          'received_at': r['received_at'],
          'reporting_status': 'unverified',
          if (r['_report_payment_review'] == true)
            '_report_payment_review': true,
        }, r),
      );
    }
    return result;
  }
}
