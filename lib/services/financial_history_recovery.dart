import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import 'local_document_repository.dart';
import 'local_financial_cache.dart';

/// Explicit read-only recovery of posted financial history. It does not
/// toggle Force Offline, flush the outbox, or create/update server records.
class FinancialHistoryRecovery {
  FinancialHistoryRecovery({
    LocalFinancialCache? cache,
    LocalDocumentRepository? documents,
    SupabaseClient? client,
  })
      : _cache = cache ?? LocalFinancialCache(),
        _documents = documents,
        _client = client;

  final LocalFinancialCache _cache;
  final LocalDocumentRepository? _documents;
  final SupabaseClient? _client;
  static const pageSize = 200;
  static const maxPages = 150;

  static String failureMessage(Object error) {
    if (error is AuthRetryableFetchException) {
      return 'Could not refresh your Owner session for the download. '
          'Check the internet connection and tap Download again.';
    }
    if (error is AuthException) {
      return 'Your Owner sign-in could not be renewed. Sign in again before downloading history.';
    }
    return error.toString();
  }


  /// The invoice index RPC returns a single JSON value containing all rows.
  /// Import it without deleting device-only invoices or replaying the outbox.
  Future<int> downloadInvoices(String businessId) async {
    final client = _client ?? supabase;
    final identity = client.auth.currentUser?.id;
    if (businessId.trim().isEmpty || identity == null ||
        client.auth.currentSession == null) {
      throw StateError('Sign in to Briskers before downloading invoices.');
    }
    const rpc = 'briskers_list_documents_v4';
    final raw = await explicitSupabaseRead(rpc, () => client.rpc(
      rpc, params: {'p_business_id': businessId, 'p_kind': 'invoice'},
    ).timeout(const Duration(seconds: 45)));
    if (client.auth.currentUser?.id != identity ||
        client.auth.currentSession == null) {
      throw StateError('Account changed during download. Saved records remain intact.');
    }
    final rows = (raw as List<dynamic>)
        .map((entry) => Map<String, dynamic>.from(entry as Map)).toList();
    final ids = <String>{};
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      final amount = num.tryParse(row['total_amount']?.toString() ?? '');
      if (row['kind'] != 'invoice' || id.isEmpty || !ids.add(id) ||
          amount == null || !amount.isFinite) {
        throw StateError('A downloaded invoice has invalid identity or totals.');
      }
    }
    await (_documents ?? LocalDocumentRepository())
        .importInvoiceHistory(businessId, rows);
    return rows.length;
  }

  /// [onPage] is progress only; the local cache remains usable between pages.
  /// Returns fetched server IDs, not the total local row count.
  Future<int> download({
    required String businessId,
    required DateTime? start,
    required DateTime end,
    required void Function(int) onPage,
  }) async {
    if (businessId.trim().isEmpty || (start != null && end.isBefore(start))) {
      throw ArgumentError('Choose a valid business and date range.');
    }
    final client = _client ?? supabase;
    final identity = client.auth.currentUser?.id;
    if (identity == null || client.auth.currentSession == null) {
      throw StateError('Sign in to Briskers before downloading history.');
    }
    final startDay = start?.toIso8601String().split('T').first;
    final endDay = end.toIso8601String().split('T').first;
    final ids = <String>{};
    final batch = <Map<String, dynamic>>[];
    for (var page = 0; page < maxPages; page++) {
      if (client.auth.currentUser?.id != identity ||
          client.auth.currentSession == null) {
        throw StateError('Account changed during download. Saved records remain intact.');
      }
      // This RPC requires expenses.read. It lists posted transactions only.
      // No SyncReplayFence or outbound mutation is used here.
      const rpc = 'briskers_list_transactions_recurring_v1';
      final raw = await explicitSupabaseRead(rpc, () => client.rpc(
        rpc, params: {
          'p_business_id': businessId,
          'p_limit': pageSize,
          'p_offset': page * pageSize,
          'p_start_date': startDay,
          'p_end_date': endDay,
          'p_search': null,
          'p_direction': null,
          'p_account_id': null,
          'p_category_id': null,
          'p_counterparty_id': null,
        },
      ).timeout(const Duration(seconds: 20)));
      if (client.auth.currentUser?.id != identity ||
          client.auth.currentSession == null) {
        throw StateError('Account changed during download. Saved records remain intact.');
      }
      final rows = (raw as List<dynamic>)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
      if (rows.any((row) =>
          (row['id']?.toString() ?? '').isEmpty ||
          (row['business_id']?.toString() ?? '') != businessId)) {
        throw StateError('Downloaded transaction identity mismatch. Nothing was removed.');
      }
      // Do not allow repeated IDs across pages to suggest the history is
      // complete while the remote ordering is changing.
      for (final row in rows) {
        if (!ids.add(row['id'].toString())) {
          throw StateError('Historical pages changed during download. Retry to verify.');
        }
      }
      // Save in bounded batches instead of rewriting a large SQLite JSON
      // snapshot after every individual 200-row page. Failed downloads
      // preserve previously saved pages and the user's pending outbox.
      batch.addAll(rows);
      if (batch.length >= 1000 || rows.length < pageSize) {
        await _cache.mergeServerTransactions(businessId, batch);
        batch.clear();
      }
      onPage(ids.length);
      if (rows.length < pageSize) {
        await _cache.savePostedHistoryCoverage(businessId, start, end);
        return ids.length;
      }
    }
    throw StateError('History download reached the safety limit. Saved pages remain available.');
  }
}
