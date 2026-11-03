import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/connection_mode.dart';
import '../core/supabase_config.dart';
import '../core/warranty_payment_amounts.dart';
import 'briskers_api.dart';
import 'local_document_detail_cache.dart';

/// Presentation-only projection. Raw transaction amounts, signed amounts,
/// invoice allocations and payment state are never overwritten.
class WarrantyReceiptReporting {
  const WarrantyReceiptReporting({this.api = const BriskersApi(),
    this.cache = const LocalDocumentDetailCache(), this.currentUserId});
  final BriskersApi api;
  final LocalDocumentDetailCache cache;
  /// Identity lookup is injectable for isolated tests; production uses the
  /// authenticated Supabase session, never a business-only cache identity.
  final String? Function()? currentUserId;

  static Map<String, dynamic> project(Map<String, dynamic> transaction,
      Map<String, dynamic> invoice, Map<String, dynamic> warranty) {
    final result = Map<String, dynamic>.from(transaction)
      ..remove('reporting_amount')
      ..remove('reporting_processor_fee');
    if (transaction['direction'] != 'income') return result;
    final payments = List<dynamic>.from(invoice['payments'] ?? const [])
      .whereType<Map>().map((raw) => Map<String, dynamic>.from(raw)).toList();
    final receipt = WarrantyPaymentAmounts.receipt(warranty, payments);
    final id = transaction['id']?.toString() ?? '';
    final exact = payments.where((payment) => payment['id']?.toString() == id &&
      const {'posted', 'finalized'}.contains(payment['state'])).toList();
    if (id.isEmpty || exact.length != 1) {
      return result..['reporting_status'] = 'unverified';
    }
    if (warranty['extended_warranty'] != true) {
      return result..['reporting_status'] = 'verified';
    }
    if (receipt == null) return result..['reporting_status'] = 'unverified';
    if (receipt['id']?.toString() != id) {
      // The invoice's cash/other receipts stay whole. Fee belongs once to
      // the single corroborated warranty receipt, never to every payment.
      return result..['reporting_status'] = 'verified';
    }
    if (WarrantyPaymentAmounts.cents(transaction['amount']) !=
        WarrantyPaymentAmounts.cents(receipt['amount'])) {
      return result..['reporting_status'] = 'unverified';
    }
    final rate = num.tryParse(warranty['surcharge_rate']?.toString() ?? '');
    // A check has no processor fee. Conflicting/stale metadata must not
    // silently reduce its income or become a verified fee allocation.
    if (rate == null || !rate.isFinite || rate < 0 ||
        (rate <= 0.000001 && WarrantyPaymentAmounts.cents(warranty['processor_fee']) != 0)) {
      return result..['reporting_status'] = 'unverified';
    }
    final amounts = WarrantyPaymentAmounts.fromReceipt(
      gross: transaction['amount'], processorFee: warranty['processor_fee']);
    if (amounts == null) return result..['reporting_status'] = 'unverified';
    return result
      ..['reporting_amount'] = amounts.retained
      ..['reporting_processor_fee'] = amounts.fee
      ..['reporting_status'] = 'verified';
  }

  static Map<String, dynamic> unverified(Map<String, dynamic> row) =>
    Map<String, dynamic>.from(row)
      ..remove('reporting_amount')
      ..remove('reporting_processor_fee')
      ..['reporting_status'] = 'unverified';

  static Map<String, dynamic> newerContext(Map<String, dynamic> local,
      Map<String, dynamic> saved) {
    if (local['sync_state'] == 'pending' || local['_local_pending_payment'] == true ||
        local['_payment_reconciliation_required'] == true) {
      return {...local}..remove('offline_warranty_detail');
    }
    final localVersion = int.tryParse(local['row_version']?.toString() ?? '');
    final savedVersion = int.tryParse(saved['row_version']?.toString() ?? '');
    if (localVersion != null && savedVersion != null) {
      if (localVersion > savedVersion) return local;
      if (savedVersion > localVersion) return saved;
    }
    // Same/unknown revision still requires the identical receipt set. A stale
    // dedicated report must not hide a newer reversal, split or replacement.
    String signature(Map<String, dynamic> detail) {
      final rows = List<dynamic>.from(detail['payments'] ?? const [])
        .whereType<Map>().map((row) => '${row['id']}|${row['amount']}|${row['state']}').toList()..sort();
      return rows.join(';');
    }
    return signature(local) == signature(saved) ? saved : local;
  }

  static num amount(Map<String, dynamic> row) =>
    num.tryParse((row['direction'] == 'income' && row['reporting_status'] == 'verified'
      ? row['reporting_amount'] ?? row['amount'] : row['amount']).toString()) ?? 0;

  Future<List<Map<String, dynamic>>> enrich(String businessId,
      List<Map<String, dynamic>> transactions, {bool refresh = true}) async {
    String? userId;
    try {
      userId = currentUserId != null
          ? currentUserId!()
          : supabase.auth.currentUser?.id;
    } catch (_) { /* No authenticated identity. */ }
    if (userId == null || userId.isEmpty) return transactions.map(unverified).toList();
    // Totals request an entire reporting period. Do not scan historical
    // invoice snapshots if this page contains no relevant income receipts.
    // The ledger amounts themselves are never altered by this fast path.
    final wantedReceiptIds = transactions
        .where((row) => row['direction'] == 'income')
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (wantedReceiptIds.isEmpty) {
      return transactions.map(unverified).toList();
    }
    // Offline reporting only trusts user-scoped verified snapshots. Loading
    // every cached invoice (thousands on established devices) before the
    // first Expenses frame adds seconds but cannot authorize any reporting:
    // the old code discarded that whole inventory again below.
    final offline = !refresh ||
        BriskersConnectionModeController.instance.forceOffline;
    List<Map<String, dynamic>> snapshots;
    SharedPreferences prefs;
    try {
      snapshots = offline
          ? <Map<String, dynamic>>[]
          : await cache.loadAll(businessId);
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // Cache failure must not hide real transactions or stale-adjust them.
      return transactions.map(unverified).toList();
    }
    final prefix = 'briskers_warranty_reporting_${userId}_${businessId}_';
    final scoped = <Map<String, dynamic>>[];
    // Reporting cache is user + business scoped. Business-only document
    // snapshots only locate authorized online reads or invalidate stale data;
    // they never grant another user's offline reporting permissions.
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      try {
        final saved = Map<String, dynamic>.from(jsonDecode(prefs.getString(key)!) as Map);
        // When summarizing 30 days, thousands of historical user-scoped
        // reports may still exist. The old loop awaited a local document
        // read for every report even when none of its payment IDs appeared
        // in this period. Filter on saved IDs FIRST; a matching saved report
        // still goes through the original version/pending-state checks.
        // An unrelated saved report cannot authorize a fee deduction.
        if (offline) {
          final payments = saved['payments'];
          if (payments is! List || !payments.whereType<Map>().any(
            (payment) => wantedReceiptIds.contains(payment['id']?.toString()),
          )) {
            continue;
          }
        }
        final id = saved['id']?.toString();
        // When disconnected, read only the invoice having a verified
        // user-scoped reporting record. Still reject newer/dirty local detail,
        // without scanning unrelated invoice cache entries.
        final localDetail = offline && id != null && id.isNotEmpty
            ? await cache.load(businessId, id)
            : null;
        final existing = offline
            ? (localDetail == null
                ? <Map<String, dynamic>>[]
                : <Map<String, dynamic>>[localDetail])
            : snapshots
                .where((item) => item['id']?.toString() == id)
                .toList();
        var selected = existing.length == 1 ? newerContext(existing.single, saved) : saved;
        if (existing.length == 1 && identical(selected, existing.single)) {
          selected = {...selected}..remove('offline_warranty_detail');
        }
        scoped.add(selected);
        if (!offline) {
          snapshots.removeWhere((item) => item['id']?.toString() == id);
          snapshots.add(selected);
        }
      } catch (_) { /* An unreadable reporting snapshot remains unverified. */ }
    }
    if (offline) snapshots = scoped;
    final byPayment = <String, List<Map<String, dynamic>>>{};
    for (final snapshot in snapshots) {
      for (final raw in List<dynamic>.from(snapshot['payments'] ?? const []).whereType<Map>()) {
        final id = raw['id']?.toString() ?? '';
        if (id.isNotEmpty && const {'posted', 'finalized'}.contains(raw['state'])) {
          (byPayment[id] ??= []).add(snapshot);
        }
      }
    }
    final invoiceReads = <String, Future<Map<String, dynamic>>>{};
    Future<Map<String, dynamic>> read(Map<String, dynamic> snapshot) async {
      if (!refresh || BriskersConnectionModeController.instance.forceOffline) return snapshot;
      final id = snapshot['id']?.toString() ?? '';
      if (id.isEmpty) return snapshot;
      // Separate existing, permission-checked read RPCs; no new backend
      // access or schema change, and no writes back to financial records.
      final detail = await api.documentDetail(businessId, id);
      final warranty = await api.documentWarrantyDetail(businessId, id);
      final after = await api.documentDetail(businessId, id);
      final version = detail['row_version']?.toString();
      if (detail['id']?.toString() != id || after['id']?.toString() != id ||
          version == null || version != after['row_version']?.toString() ||
          jsonEncode(detail['payments']) != jsonEncode(after['payments'])) {
        throw StateError('Invoice changed while verifying processor fee.');
      }
      final reporting = {...after, 'offline_warranty_detail': warranty};
      await prefs.setString('$prefix$id', jsonEncode(reporting));
      return reporting;
    }
    final results = <Map<String, dynamic>>[];
    // Bound network concurrency; most invoice snapshots are shared by receipts.
    for (var start = 0; start < transactions.length; start += 4) {
      results.addAll(await Future.wait(transactions.skip(start).take(4).map((row) async {
        if (row['direction'] != 'income') return unverified(row);
        final matches = byPayment[row['id']?.toString() ?? ''] ?? const [];
        if (matches.length != 1) return unverified(row);
        try {
          final snapshot = matches.single;
          final id = snapshot['id']?.toString() ?? '';
          final detail = await (invoiceReads[id] ??= read(snapshot));
          final warranty = detail['offline_warranty_detail'];
          if (warranty is! Map) return unverified(row);
          return project(row, detail, Map<String, dynamic>.from(warranty));
        } catch (_) {
          // The raw receipt remains visible, but never claim a verified net.
          return unverified(row);
        }
      })));
    }
    return results;
  }
}
