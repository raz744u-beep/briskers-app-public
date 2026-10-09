import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_financial_cache.dart';

/// Complete, business-scoped history of expense allocations. This snapshot
/// does not modify local financial outbox items or pending expense edits.
class LinkedExpenseSyncService {
  LinkedExpenseSyncService({
    BriskersApi api = const BriskersApi(),
    LocalFinancialCache? cache,
    BriskersLocalDatabase? database,
  }) : _api = api,
       _cache = cache ?? LocalFinancialCache(database: database),
       _database = database ?? localDatabase;

  final BriskersApi _api;
  final LocalFinancialCache _cache;
  final BriskersLocalDatabase _database;
  static const scope = 'linked_expenses';

  // Share ongoing snapshot pulls across pages/screens. Multiple simultaneous
  // large full-history requests can compete for database resources.
  static final Map<String, Future<int>> _inFlight = {};

  Future<int> pull(String businessId) {
    final previous = _inFlight[businessId];
    if (previous != null) return previous;
    final work = _pullSnapshot(businessId);
    _inFlight[businessId] = work;
    return work.whenComplete(() {
      if (identical(_inFlight[businessId], work)) {
        _inFlight.remove(businessId);
      }
    });
  }

  Future<List<Map<String, dynamic>>> _pageWithTimeoutRetry(
    String businessId, String? cursor,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _api.linkedExpensesAfterPage(
          businessId, afterAllocationId: cursor, limit: 500,
        );
      } catch (error) {
        final timeout = error.toString().contains('57014') ||
            error.toString().toLowerCase().contains('statement timeout');
        if (!timeout || attempt >= 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  Future<int> _pullSnapshot(String businessId) async {
    const pageSize = 500;
    final all = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    String? cursor;
    while (true) {
      final page = await _pageWithTimeoutRetry(businessId, cursor);
      for (final allocation in page) {
        final id = allocation['allocation_id']?.toString() ?? '';
        if (id.isEmpty || !seenIds.add(id)) {
          throw StateError(
            'Linked expense sync returned a missing/duplicate allocation ID.',
          );
        }
      }
      all.addAll(page);
      if (page.length < pageSize) break;
      final next = page.last['allocation_id']?.toString();
      if (next == null || next.isEmpty || next == cursor) {
        throw StateError('Linked expense sync cursor did not advance.');
      }
      cursor = next;
    }
    // Publish only when every page was received. An error preserves the last
    // complete snapshot and all pending expense edits.
    await _cache.saveLinkedExpenses(businessId, all);
    await _database.customStatement(
      '''
      INSERT INTO local_sync_states (
        business_id, scope, last_pull_at, last_error, bootstrapped
      ) VALUES (?, ?, ?, NULL, 1)
      ON CONFLICT(business_id,scope) DO UPDATE SET
        last_pull_at=excluded.last_pull_at,
        last_error=NULL,
        bootstrapped=1
      ''',
      [
        businessId,
        scope,
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );
    return all.length;
  }

  Future<void> refreshBestEffort(String businessId) async {
    try {
      await pull(businessId);
    } catch (error) {
      await _database.customStatement(
        '''
        INSERT INTO local_sync_states (
          business_id, scope, last_error, bootstrapped
        ) VALUES (?, ?, ?, 0)
        ON CONFLICT(business_id,scope) DO UPDATE SET
          last_error=excluded.last_error
        ''',
        [businessId, scope, error.toString()],
      );
    }
  }
}
