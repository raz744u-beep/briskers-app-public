import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart' hide LocalFinancialCache;
import '../local/local_database_provider.dart';
import 'local_financial_cache.dart';
import 'local_document_detail_cache.dart';
import 'local_invoice_closure.dart';
import 'offline_invoice_payment_ledger.dart';
import 'local_document_sql_store.dart';
import 'local_transaction_search.dart';

/// Read-only projection of real invoice receipts into Expenses & Income.
/// No methods in this class insert, finalize, post, or charge a payment.
class InvoicePaymentFeed {
  InvoicePaymentFeed({
    BriskersLocalDatabase? database,
    LocalFinancialCache? cache,
  })  : _db = database ?? localDatabase,
        _cache = cache ?? LocalFinancialCache(database: database);

  /// Present accounting and connectivity as separate concepts. Never call
  /// a pending or locally held receipt fully paid from a stale coverage hint.
  static String paymentLabel(Map<String, dynamic> transaction) {
    final state = transaction['_receipt_state']?.toString().toLowerCase();
    final coverage = transaction['_payment_coverage']?.toString().toLowerCase();
    if (state != 'posted' && state != 'local_finalized') return 'Recorded';
    if (coverage == 'paid') return 'Paid';
    if (coverage == 'partial') return 'Partial';
    return 'Recorded';
  }

  static String syncLabel(Map<String, dynamic> transaction) {
    switch (transaction['_receipt_state']?.toString().toLowerCase()) {
      case 'posted':
        return 'Synced';
      case 'local_finalized':
      case 'local':
        return 'Local · saved on this device';
      case 'pending':
        return 'Pending cloud sync';
      default:
        return 'Sync status needs verification';
    }
  }

  final BriskersLocalDatabase _db;
  final LocalFinancialCache _cache;

  Future<void> saveServerReceipts(
    String businessId,
    List<Map<String, dynamic>> receipts,
  ) => _cache.saveInvoiceReceipts(businessId, receipts);

  Future<List<Map<String, dynamic>>> load(String businessId) async {
    final deletionIds = await OfflineInvoicePaymentLedger(database: _db)
        .pendingDeletionIds(businessId);
    final server = (await _cache.loadInvoiceReceipts(businessId)).where((receipt) {
      if (receipt['receipt_state'] != 'pending') return true;
      return !OfflineInvoicePaymentLedger.hasDeletedPaymentIdentity(
        receipt, deletionIds[receipt['invoice_id']] ?? const {},
      );
    }).toList();
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
        AND (o.state IN ('pending','inflight') OR
          (o.state='conflict' AND
           o.last_error='Owner recovery payment preserved; sync disabled'))
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
          'transaction_date': (data['payment_date']?.toString() ??
                  data['received_at']?.toString() ?? '').split('T').first,
          'received_at': data['received_at'],
          'receipt_state': 'local',
        });
      } catch (_) {
        // Preserve the queue, but never invent a receipt from invalid payload.
      }
    }
    final finalized = await LocalInvoiceClosureStore(_db).finalizedIncome(businessId);
    final merged = mergeReceipts(withLocalFinalization(server, finalized),
        local.where((row) => !finalized.any((item) => _sameReceipt(item, row))).toList());
    final pendingCorrections = await _db.customSelect(
      """SELECT payload_json FROM sync_outbox
      WHERE business_id=? AND entity_type='invoice_pending_payment_edit'
      AND state IN ('pending','inflight')""",
      variables:[Variable<String>(businessId)],
    ).get();
    final corrections=<Map<String,dynamic>>[];
    for(final row in pendingCorrections) {
      try {
        corrections.add(Map<String,dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map));
      } catch (_) {
        // Invalid corrections cannot create receipt rows or income.
      }
    }
    final receipts = overlayPendingPaymentEdits(merged,corrections);
    final hasNumberHistory = await _db.customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='local_invoice_number_corrections'",
    ).getSingleOrNull();
    if (hasNumberHistory == null) return receipts;
    final correctedNumbers = await _db.customSelect(
      'SELECT invoice_id,new_invoice_number FROM local_invoice_number_corrections WHERE business_id=?',
      variables:[Variable(businessId)],
    ).get();
    final numbers = {for (final row in correctedNumbers)
      row.read<String>('invoice_id'):row.read<String>('new_invoice_number')};
    return [for (final receipt in receipts)
      if (numbers.containsKey(receipt['invoice_id']))
        {...receipt,'document_number':numbers[receipt['invoice_id']]}
      else receipt];
  }

  static bool _sameReceipt(Map<String, dynamic> left, Map<String, dynamic> right) {
    if (left['invoice_id'] != right['invoice_id']) return false;
    Set<String> keys(Map<String, dynamic> row) => {
      for (final key in ['receipt_id', 'operation_id', 'server_payment_id', 'transaction_id'])
        if (row[key]?.toString().isNotEmpty == true) row[key].toString(),
    };
    return keys(left).intersection(keys(right)).isNotEmpty;
  }

  /// A posted allocation with an exact identity takes precedence. Legacy
  /// posting can discard receipt IDs. Once posted allocations cover the
  /// entire invoice, avoid adding a second representation of that income.
  static List<Map<String, dynamic>> withLocalFinalization(
    List<Map<String, dynamic>> authoritative,
    List<Map<String, dynamic>> finalized,
  ) {
    final postedCents = <Object?, int>{};
    for (final row in authoritative) {
      if (row['receipt_state'] != 'posted') continue;
      postedCents.update(row['invoice_id'],
          (value) => value + (_amount(row['amount']) * 100).round(),
          ifAbsent: () => (_amount(row['amount']) * 100).round());
    }
    final result = authoritative.toList();
    for (final row in finalized) {
      final total = (_amount(row['invoice_total']) * 100).round();
      result.removeWhere((item) => item['receipt_state'] != 'posted' &&
          _sameReceipt(item, row));
      if ((total > 0 && (postedCents[row['invoice_id']] ?? 0) >= total) ||
          authoritative.any((item) =>
              item['receipt_state'] == 'posted' && _sameReceipt(item, row))) {
        continue;
      }
      result.add(row);
    }
    return result;
  }

  /// Read-only view of amount/method/date corrections to server-pending
  /// receipts. Never fabricate a receipt when its exact ID is absent.
  static List<Map<String,dynamic>> overlayPendingPaymentEdits(
    List<Map<String,dynamic>> receipts,
    Iterable<Map<String,dynamic>> edits,
  ) {
    final result=receipts
        .map((row)=>Map<String,dynamic>.from(row)).toList();
    final affected=<String>{};
    for(final edit in edits) {
      final id=edit['payment_id']?.toString()??'';
      final invoice=edit['invoice_id']?.toString()??'';
      final matches=<int>[];
      for(var i=0;i<result.length;i++) {
        if(result[i]['receipt_id']?.toString()==id &&
            result[i]['invoice_id']?.toString()==invoice &&
            result[i]['receipt_state']?.toString()=='pending') {
          matches.add(i);
        }
      }
      if(matches.length!=1)continue; // Never guess by amount or customer.
      final cents=num.tryParse(edit['amount_cents']?.toString()??'')?.round();
      if(cents==null||cents<=0)continue;
      final target=result[matches.single];
      result[matches.single]={
        ...target,
        'amount':cents/100,
        'payment_method':edit['method_name'],
        'transaction_date':edit['payment_date'],
        '_local_pending_edit':true,
      };
      affected.add(invoice);
    }
    for(final invoice in affected) {
      final related=result.where((r)=>r['invoice_id']?.toString()==invoice)
          .toList()..sort((a,b)=>
              (a['received_at']?.toString()??'')
                .compareTo(b['received_at']?.toString()??''));
      var totalReceived=0.0;
      for(final payment in related) {
        totalReceived+=_amount(payment['amount']);
        final invoiceTotal=_amount(payment['invoice_total']);
        if(invoiceTotal>0) {
          payment['coverage']=totalReceived+0.005>=invoiceTotal
              ? 'paid' : 'partial';
        }
      }
    }
    return result;
  }

  /// An existing b2286 installation already holds local invoice details.
  /// Until the new RPC has downloaded its complete receipt inventory, recover
  /// server-pending receipts from those protected snapshots WITHOUT networking
  /// or writing money. This runs AFTER the Expenses first paint.
  Future<List<Map<String, dynamic>>> pendingFromCachedInvoices(
      String businessId) async {
    final serverComplete = await _cache.hasServerInvoiceReceipts(businessId);
    final server = await _cache.loadInvoiceReceipts(businessId);
    final active = await _db.customSelect(
      "SELECT id FROM local_documents WHERE business_id=? AND kind='invoice' "
      "AND COALESCE(status,'') NOT IN ('void','voided','deleted')",
      variables: [Variable<String>(businessId)],
    ).get();
    final invoiceIds = active.map((row) => row.read<String>('id')).toSet();
    final prefix = 'briskers_document_detail_${businessId}_';
    await LocalDocumentSqlStore.ensure(_db);
    final durable = await _db.customSelect(
      'SELECT cache_key FROM local_document_details WHERE substr(cache_key,1,?)=? '
      "AND json_valid(payload_json) AND json_extract(payload_json,'\$.kind')='invoice' "
      "AND json_array_length(payload_json,'\$.payments')>0",
      variables: [Variable(prefix.length), Variable(prefix)],
    ).get();
    invoiceIds.addAll(durable.map((row) => row.read<String>('cache_key').substring(prefix.length)));
    final prefs = await SharedPreferences.getInstance();
    final legacy = {
      for (final key in prefs.getKeys())
        if (key.startsWith(prefix)) key.substring(prefix.length),
    };
    final sqliteIds = {
      for (final row in durable) row.read<String>('cache_key').substring(prefix.length),
    };
    final detailCache = LocalDocumentDetailCache(database: _db);
    final pendingRows = <Map<String, dynamic>>[];
    var examined = 0;
    for (final invoiceId in invoiceIds) {
      if (!sqliteIds.contains(invoiceId) && !legacy.contains(invoiceId)) continue;
      final detail = await detailCache.loadReadOnly(businessId, invoiceId, projectLifecycle: false);
      if (detail == null || detail['id'] != invoiceId || detail['kind'] != 'invoice' ||
          const ['void','voided','deleted'].contains(detail['status'])) {
        continue;
      }
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
        final state = payment['state']?.toString();
        final paymentId = payment['id']?.toString() ?? '';
        final transactionId = payment['transaction_id']?.toString() ??
            payment['financial_transaction_id']?.toString();
        final locallyRecorded = payment['pending_sync'] == true;
        final posted = state == 'posted' && transactionId?.isNotEmpty == true;
        if (paymentId.isEmpty || payment['_local_pending_payment'] == true ||
            (!posted && (state != 'pending' || (serverComplete && !locallyRecorded)))) {
          continue;
        }
        final at = payment['entered_at']?.toString() ?? '';
        pendingRows.add({
          'receipt_id': paymentId,
          'operation_id': payment['operation_id'],
          'server_payment_id': payment['server_payment_id'],
          'transaction_id': transactionId,
          'invoice_id': invoiceId,
          'document_number': detail['document_number'],
          'customer_name': detail['customer_name'] ?? 'Customer',
          'job_number': detail['job_number'],
          'payment_method': payment['payment_method_name'] ?? 'Payment',
          'amount': amount,
          'invoice_total': total,
          'transaction_date': (payment['payment_date']?.toString().isNotEmpty == true)
              ? payment['payment_date'] : (at.isNotEmpty ? at.split('T').first : null),
          'received_at': at,
          'receipt_state': posted ? 'posted' : locallyRecorded ? 'local' : 'pending',
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
    final finalized = await LocalInvoiceClosureStore(_db).finalizedIncome(businessId);
    return mergeReceipts(const [], pendingRows.where((row) =>
        !finalized.any((item) => _sameReceipt(item, row)) &&
        !server.any((item) => _sameReceipt(item, row))).toList());
  }

  /// Stable identity is required to retire a local card without duplication.
  /// On an online first page, stale server-pending cached receipts are NOT
  /// proof that a payment remains pending. The same payment may already have
  /// been finalized and appear in the financial ledger. Show the current
  /// authorized page plus previous posted allocations and the durable local
  /// outbox. Full pagination restores any still-pending older server items.
  /// Never equate payments merely because amount/customer/date match.
  static List<Map<String, dynamic>> reconcileOnlineFirstPage(
    List<Map<String, dynamic>> authoritativePage,
    List<Map<String, dynamic>> previouslyVisible,
  ) {
    final posted = previouslyVisible
        .where((row) => row['receipt_state']?.toString() == 'posted')
        .toList();
    final local = previouslyVisible
        .where((row) => row['receipt_state']?.toString() == 'local')
        .toList();
    final finalized = previouslyVisible
        .where((row) => row['receipt_state'] == 'local_finalized').toList();
    return mergeReceipts(withLocalFinalization(
        mergeReceipts([...authoritativePage, ...posted], const []), finalized), local);
  }

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
      if (date == null && (startDate != null || endDate != null)) return false;
      if (date != null) {
        final day = DateTime(date.year, date.month, date.day);
        if (startDate != null && day.isBefore(startDate)) return false;
        if (endDate != null && day.isAfter(endDate)) return false;
      }
      return LocalTransactionSearch.matches(r, search);
    }).toList();

    final financialByPayment = <String, String>{};
    for (final item in financial) {
      final payment = item['invoice_payment_id']?.toString() ?? '';
      final id = item['id']?.toString() ?? '';
      if (payment.isEmpty || id.isEmpty || item['direction'] != 'income') continue;
      // A receipt claimed by multiple financial rows is ambiguous.
      financialByPayment.update(payment, (_) => '', ifAbsent: () => id);
    }
    final allocations = <String, List<Map<String, dynamic>>>{};
    for (final r in eligible) {
      var transactionId = r['receipt_state'] == 'posted'
          ? r['transaction_id']?.toString() ?? '' : '';
      if (transactionId.isEmpty) {
        final matched = {
          for (final key in ['receipt_id','operation_id','server_payment_id'])
            if (financialByPayment[r[key]?.toString()] case final String id when id.isNotEmpty) id,
        };
        transactionId = matched.length == 1 ? matched.single : '';
      }
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
