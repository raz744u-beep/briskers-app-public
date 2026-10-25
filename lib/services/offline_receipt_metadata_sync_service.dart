import 'package:shared_preferences/shared_preferences.dart';

import '../core/connection_mode.dart';
import 'briskers_api.dart';
import 'local_financial_cache.dart';

/// Fills *missing* authorized receipt details in bounded idle batches.
/// Never posts payments, changes totals, edits invoices, or overwrites local
/// unsynchronized financial details. The photo mirror picks up the metadata.
class OfflineReceiptMetadataSyncService {
  OfflineReceiptMetadataSyncService({
    BriskersApi api = const BriskersApi(),
    LocalFinancialCache? cache,
  }) : _api = api, _cache = cache ?? LocalFinancialCache();

  final BriskersApi _api;
  final LocalFinancialCache _cache;
  static const _cursorPrefix = 'briskers_receipt_detail_cursor_';

  Future<int> hydrateBatch(String businessId, {int batchSize = 12}) async {
    if (businessId.isEmpty || batchSize <= 0 ||
        BriskersConnectionModeController.instance.forceOffline) {
      return 0;
    }

    // Only already authorized shop rows from the local transaction snapshot.
    // Never use temporary IDs, an unsynchronized edit, or a conflict row as a
    // basis for rehydrating a server detail.
    final rows = await _cache.loadTransactions(businessId);
    final eligible = rows.where((row) {
      final id = row['id']?.toString() ?? '';
      final count = int.tryParse(row['receipt_count']?.toString() ?? '') ?? 0;
      return id.isNotEmpty && !id.startsWith('local-') && count > 0 &&
          row['sync_state'] != 'pending' &&
          row['sync_state'] != 'conflict';
    }).toList()
      ..sort((a, b) =>
          a['id'].toString().compareTo(b['id'].toString()));

    if (eligible.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final cursorKey = '$_cursorPrefix$businessId';
    final offset = prefs.getInt(cursorKey) ?? 0;
    final start = offset < 0 || offset >= eligible.length ? 0 : offset;
    final batch = eligible.skip(start).take(batchSize).toList();

    var completed = 0;
    var downloaded = 0;
    for (final row in batch) {
      if (BriskersConnectionModeController.instance.forceOffline) break;
      completed++;
      final id = row['id'].toString();
      try {
        if (await _cache.loadTransactionDetail(businessId, id) != null) {
          continue;
        }
        final detail = await _api.transactionDetail(businessId, id);
        if (detail['id']?.toString() != id) continue;
        // A pending local mutation that arrived while HTTP was in-flight
        // always wins; we only fill a previously missing detail.
        if (await _cache.loadTransactionDetail(businessId, id) == null) {
          await _cache.saveTransactionDetail(businessId, id, detail);
          downloaded++;
        }
      } catch (_) {
        // Failed remote details retry on a later cursor pass.
      }
    }
    final next = start + completed;
    await prefs.setInt(cursorKey, next >= eligible.length ? 0 : next);
    return downloaded;
  }
}
