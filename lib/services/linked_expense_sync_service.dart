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

  Future<int> pull(String businessId) async {
    const pageSize = 500;
    final all = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _api.linkedExpensesPage(
        businessId, limit: pageSize, offset: offset,
      );
      all.addAll(page);
      offset += page.length;
      if (page.length < pageSize) break;
    }
    // Publish only after all pages succeeded. A failed/interrupted pull
    // retains the last complete cache instead of replacing it partially.
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
