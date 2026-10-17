import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart' hide LocalFinancialCache;
import '../local/local_database_provider.dart';
import 'local_financial_cache.dart';
import 'local_document_detail_cache.dart';

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

  /// An existing b2286 installation already holds local invoice details.
  /// Until the new RPC has downloaded its complete receipt inventory, recover
  /// server-pending receipts from those protected snapshots WITHOUT networking
  /// or writing money. This runs AFTER the Expenses first paint.
  Future<List<Map<String, dynamic>>> pendingFromCachedInvoices(
      String businessId) async {
    if (await _cache.hasServerInvoiceReceipts(businessId)) {
      // A complete server RPC cache, even if empty, outranks stale documents.
      return const [];
    }
    final active = await _db.customSelect(
      "SELECT id FROM local_documents "
      "WHERE business_id = ? AND kind = 'invoice' "
      "AND COALESCE(status, '') <> 'void'",
      variables: [Variable<String>(businessId)],
    ).get();
    final invoiceIds = active.map((r) => r.read<String>('id')).toSet();
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'briskers_document_detail_${businessId}_';
    final detailCache = LocalDocumentDetailCache(database: _db);
    final pendingRows = <Map<String, dynamic>>[];
    final aggregate = RegExp(
        r'"pending_payment"\s*:\s*"?([0-9]+(?:\.[0-9]+)?)');
    var examined = 0;
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final invoiceId = key.substring(prefix.length);
      if (!invoiceIds.contains(invoiceId)) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final match = aggregate.firstMatch(raw);
      if (match == null ||
          (double.tryParse(match.group(1) ?? '') ?? 0) <= 0.005) {
        continue;
      }
      // Honor local retirement/quarantine protections before exposing details.
      final detail = await detailCache.load(businessId, invoiceId);
      if (detail == null ||
          detail['kind'] != 'invoice' ||
          detail['status'] == 'void') continue;
      final rows = detail['payments'];
      if (rows is! List) continue;
      final payments = rows.whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p)).toList();
      var cumulative = 0.0;
      final total = _amount(detail['total_amount']);
      for (final payment in payments) {
        final amount = _amount(payment['amount']);
        if (amount <= 0) continue;
        cumulative += amount;
        if (payment['state']?.toString() != 'pending' ||
            payment['pending_sync'] == true ||
            payment['_local_pending_payment'] == true) continue;
        final paymentId = payment['id']?.toString() ?? '';
        if (paymentId.isEmpty) continue;
        final at = payment['entered_at']?.toString() ?? '';
        pendingRows.add({
          'receipt_id': paymentId,
          'invoice_id': invoiceId,
          'document_number': detail['document_number'],
          'customer_name': detail['customer_name'] ?? 'Customer',
          'job_number': detail['job_number'],
          'payment_method': payment['payment_method_name'] ?? 'Payment',
          'amount': amount,
          'invoice_total': total,
          'transaction_date': at.isNotEmpty
              ? at.split('T').first : detail['document_date'],
          'received_at': at,
          'receipt_state': 'pending',
          'coverage': total > 0 && cumulative + 0.005 >= total
              ? 'paid' : 'partial',
        });
      }
      examined += 1;
      if (examined % 25 == 0) {
        // Allow frames to render between independent cache entries.
        await Future<void>.delayed(Duration.zero);
      }
    }
    return mergeReceipts(pendingRows, const []);
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

    final allocations = <String, List<Map<String, dynamic>>>{};
    for (final r in eligible) {
      if (r['receipt_state']?.toString() != 'posted') continue;
      final transactionId = r['transaction_id']?.toString() ?? '';
      if (transactionId.isEmpty) continue;
      allocations.putIfAbsent(transactionId, () => []).add(r);
    }
    final represented = <String>{};
    final preservedFinancial = <Map<String, dynamic>>[];
    for (final original in financial) {
      final id = original['id']?.toString() ?? '';
      final matches = allocations[id] ?? const <Map<String, dynamic>>[];
      if (matches.length == 1) {
        final receipt = matches.single;
        represented.add(receipt['receipt_id']?.toString() ?? '');
        // Preserve the already-enriched posted transaction, including exact
        // warranty processor fee reporting. Only decorate its context.
        preservedFinancial.add({
          ...original,
          'counterparty': receipt['customer_name'] ?? original['counterparty'],
          'document_id': receipt['invoice_id'],
          'document_number': receipt['document_number'],
          'payment_method_name': receipt['payment_method'],
          '_invoice_receipt': true,
          '_receipt_state': 'posted',
          '_payment_coverage': receipt['coverage'],
        });
      } else if (matches.isEmpty) {
        preservedFinancial.add(original);
      }
      // A multi-invoice allocation is displayed by its exact per-invoice
      // receipt rows below. Never also add the full original transaction.
    }
    final merged = <Map<String, dynamic>>[
      ...preservedFinancial,
      for (final r in eligible)
        if (!represented.contains(r['receipt_id']?.toString() ?? ''))
        <String, dynamic>{
          'id': r['receipt_id'],
          'direction': 'income',
          'kind': 'customer_payment',
          'amount': r['amount'],
          'counterparty': r['customer_name'] ?? 'Customer',
          'transaction_date': r['transaction_date'],
          'received_at': r['received_at'],
          'document_id': r['invoice_id'],
          'document_number': r['document_number'],
          'job_number': r['job_number'],
          'payment_method_name': r['payment_method'],
          'remarks': '',
          'reporting_status': 'unverified',
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
