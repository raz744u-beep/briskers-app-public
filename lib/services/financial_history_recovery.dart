import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import 'local_financial_cache.dart';

/// Explicit read-only recovery of posted financial history. It does not
/// toggle Force Offline, flush the outbox, or create/update server records.
class FinancialHistoryRecovery {
  FinancialHistoryRecovery({LocalFinancialCache? cache, SupabaseClient? client})
      : _cache = cache ?? LocalFinancialCache(),
        _client = client;

  final LocalFinancialCache _cache;
  final SupabaseClient? _client;
  static const pageSize = 100;
  static const maxPages = 300;

  /// [onPage] is progress only; the local cache remains usable between pages.
  /// Returns fetched server IDs, not the total local row count.
  Future<int> download({
    required String businessId,
    required DateTime start,
    required DateTime end,
    required void Function(int) onPage,
  }) async {
    if (businessId.trim().isEmpty || end.isBefore(start)) {
      throw ArgumentError('Choose a valid business and date range.');
    }
    final client = _client ?? supabase;
    final identity = client.auth.currentUser?.id;
    if (identity == null || client.auth.currentSession == null) {
      throw StateError('Sign in to Briskers before downloading history.');
    }
    final startDay = start.toIso8601String().split('T').first;
    final endDay = end.toIso8601String().split('T').first;
    final ids = <String>{};
    for (var page = 0; page < maxPages; page++) {
      if (client.auth.currentUser?.id != identity ||
          client.auth.currentSession == null) {
        throw StateError('Account changed during download. Saved records remain intact.');
      }
      // This RPC requires expenses.read. It lists posted transactions only.
      // No SyncReplayFence or outbound mutation is used here.
      final raw = await client.rpc(
        'briskers_list_transactions_recurring_v1',
        params: {
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
      ).timeout(const Duration(seconds: 20));
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
      await _cache.mergeServerTransactions(businessId, rows);
      onPage(ids.length);
      if (rows.length < pageSize) return ids.length;
    }
    throw StateError('History download reached the safety limit. Saved pages remain available.');
  }
}
