import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_financial_cache.dart';

/// Read-only projection of real invoice receipts into Expenses & Income.
/// No methods in this class insert, finalize, post, or charge a payment.
class InvoicePaymentFeed {
  InvoicePaymentFeed({
    BriskersLocalDatabase? database,
    LocalFinancialCache? cache,
  })  : _db = database ?? localDatabase,
        _cache = cache ?? LocalFinancialCache(database: database);

  final BriskersLocalDatabase _db;
  final LocalFinancialCache _cache;

  Future<void> saveServerReceipts(
    String businessId,
    List<Map<String, dynamic>> receipts,
  ) => _cache.saveInvoiceReceipts(businessId, receipts);

  Future<List<Map<String, dynamic>>> load(String businessId) async {
    final server = await _cache.loadInvoiceReceipts(businessId);
    final raw = await _db.customSelect(
      '''
      SELECT o.entity_id, o.payload_json, d.document_number,
             d.total AS invoice_total, d.job_id,
             c.display_name AS customer_name
      FROM sync_outbox o
      LEFT JOIN local_documents d
        ON d.business_id=o.business_id AND d.id=o.entity_id
       AND d.kind='invoice'
      LEFT JOIN local_customers c
        ON c.business_id=o.business_id AND c.id=d.customer_id
      WHERE o.business_id=?
        AND o.entity_type='invoice_payment_received'
        AND o.state IN ('pending','inflight')
      ORDER BY o.id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    final local = <Map<String, dynamic>>[];
    for (final row in raw) {
      try {
        final data = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );
        final cents = (data['amount_cents'] as num).round();
        if (cents <= 0) continue;
        final id = data['operation_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        local.add({
          'receipt_id': id,
          'operation_id': id,
          'server_payment_id': data['server_payment_id'],
          'invoice_id': row.read<String>('entity_id'),
          'document_number': row.readNullable<String>('document_number'),
          'customer_name': row.readNullable<String>('customer_name') ??
              'Customer',
          'job_id': row.readNullable<String>('job_id'),
          'invoice_total': row.readNullable<double>('invoice_total'),
          'payment_method': data['method_name'] ?? 'Payment',
          'amount': cents / 100,
          'transaction_date': (data['received_at']?.toString() ?? '')
              .split('T').first,
          'received_at': data['received_at'],
          'receipt_state': 'local',
        });
      } catch (_) {
        // Preserve the queue, but never invent a receipt from invalid payload.
      }
    }
    return mergeReceipts(server, local);
  }

  /// Stable identity is required to retire a local card without duplication.
  /// Equal amounts or customer names NEVER establish receipt identity.
  static List<Map<String, dynamic>> mergeReceipts(
    List<Map<String, dynamic>> authoritative,
    List<Map<String, dynamic>> local,
  ) {
    final byId = <String>{};
    final byOperation = <String>{};
    final kept = <Map<String, dynamic>>[];
    for (final raw in authoritative) {
      final row = Map<String, dynamic>.from(raw);
      final id = row['receipt_id']?.toString() ?? '';
      if (id.isEmpty || !byId.add(id)) continue;
      final op = row['operation_id']?.toString() ?? '';
      if (op.isNotEmpty) byOperation.add(op);
      kept.add(row);
    }
    for (final raw in local) {
      final id = raw['receipt_id']?.toString() ?? '';
      final op = raw['operation_id']?.toString() ?? '';
      final acknowledged = raw['server_payment_id']?.toString() ?? '';
      if (id.isEmpty || byId.contains(id) ||
          byOperation.contains(id) ||
          (op.isNotEmpty && byOperation.contains(op)) ||
          (acknowledged.isNotEmpty && byId.contains(acknowledged))) {
        continue;
      }
      kept.add(Map<String, dynamic>.from(raw));
      byId.add(id);
    }
    // A new offline receipt may complete a partly-paid invoice. Recalculate
    // coverage only for those invoices, retaining server authoritative labels
    // for all other invoices and avoiding aggregate/financial writes.
    final localInvoices = local.map((r) => r['invoice_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty).toSet();
    for (final invoice in localInvoices) {
      final related = kept.where(
        (r) => r['invoice_id']?.toString() == invoice,
      ).toList()
        ..sort((a, b) {
          final byTime = (a['received_at']?.toString() ?? '')
              .compareTo(b['received_at']?.toString() ?? '');
          return byTime != 0 ? byTime :
              (a['receipt_id']?.toString() ?? '')
              .compareTo(b['receipt_id']?.toString() ?? '');
        });
      var cumulative = 0.0;
      for (final item in related) {
        cumulative += _amount(item['amount']);
        final total = _amount(item['invoice_total']);
        if (total > 0) {
          item['coverage'] =
              cumulative + 0.005 >= total ? 'paid' : 'partial';
        }
      }
    }
    return kept;
  }

  static double _amount(Object? x) =>
      x is num ? x.toDouble() : double.tryParse(x?.toString() ?? '') ?? 0;

  /// Keep existing posted transaction rows except those EXACTLY represented
  /// by an authoritative receipt allocation. A single posted transaction can
  /// allocate to several invoices; each allocation remains a separate row.
  static List<Map<String, dynamic>> combine({
    required List<Map<String, dynamic>> financial,
    required List<Map<String, dynamic>> receipts,
    DateTime? startDate,
    DateTime? endDate,
    String? search,
    String? direction,
    bool filteredAccount = false,
  }) {
    final eligible = receipts.where((r) {
      if (direction == 'expense' || filteredAccount) return false;
      final date = DateTime.tryParse(
        r['transaction_date']?.toString() ?? '',
      );
      if (date != null) {
        final day = DateTime(date.year, date.month, date.day);
        if (startDate != null && day.isBefore(startDate)) return false;
        if (endDate != null && day.isAfter(endDate)) return false;
      }
      final needle = search?.trim().toLowerCase() ?? '';
      if (needle.isEmpty) return true;
      return [
        r['customer_name'], r['document_number'], r['payment_method'],
        r['amount'], r['job_number'], r['transaction_date'],
      ].any((field) =>
          field?.toString().toLowerCase().contains(needle) ?? false);
    }).toList();

    final postedIds = eligible
        .where((r) => r['receipt_state']?.toString() == 'posted')
        .map((r) => r['transaction_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty).toSet();
    final merged = <Map<String, dynamic>>[
      ...financial.where(
          (row) => !postedIds.contains(row['id']?.toString() ?? '')),
      for (final r in eligible)
        <String, dynamic>{
          'id': r['receipt_id'],
          'direction': 'income',
          'kind': 'customer_payment',
          'amount': r['amount'],
          'counterparty': r['customer_name'] ?? 'Customer',
          'transaction_date': r['transaction_date'],
          'document_id': r['invoice_id'],
          'document_number': r['document_number'],
          'job_number': r['job_number'],
          'payment_method_name': r['payment_method'],
          'remarks': '',
          'reporting_status': 'verified',
          '_invoice_receipt': true,
          '_receipt_state': r['receipt_state'],
          '_payment_coverage': r['coverage'] ??
              (_amount(r['amount']) + 0.005 >=
                  _amount(r['invoice_total']) ? 'paid' : 'partial'),
        },
    ];
    merged.sort((a,b) {
      final cmp = (b['transaction_date']?.toString() ?? '')
          .compareTo(a['transaction_date']?.toString() ?? '');
      if(cmp!=0)return cmp;
      return (b['received_at']?.toString() ?? '')
          .compareTo(a['received_at']?.toString() ?? '');
    });
    return merged;
  }
}
