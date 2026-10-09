import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/linked_expense_sync_service.dart';
import 'package:briskers_app/services/local_financial_cache.dart';

class _PagedExpenseApi extends BriskersApi {
  _PagedExpenseApi({this.failFirstPage = false});
  final bool failFirstPage;

  @override
  Future<List<Map<String, dynamic>>> linkedExpensesAfterPage(
    String businessId, {int limit = 500, String? afterAllocationId}
  ) async {
    if (failFirstPage) throw StateError('Network interruption');
    if (afterAllocationId != null) return const [];
    return [
      {
        'allocation_id': 'allocation-1',
        'id': 'transaction-1',
        'transaction_id': 'transaction-1',
        'job_id': 'job-6306',
        'document_id': 'invoice-6306',
        'direction': 'expense',
        'amount': 225.71,
        'vendor': 'Worldpac',
      },
      {
        'allocation_id': 'allocation-2',
        'id': 'transaction-2',
        'transaction_id': 'transaction-2',
        'job_id': 'job-6306',
        'document_id': 'invoice-6306',
        'direction': 'expense',
        'amount': 36.66,
        'vendor': 'Peake BMW',
      },
    ];
  }
}


/// Simulates a complete 500-row page and a short trailing page.
class _MultiPageExpenseApi extends BriskersApi {
  _MultiPageExpenseApi({this.repeatLastId = false});
  final bool repeatLastId;
  final List<String?> cursors = [];
  @override
  Future<List<Map<String, dynamic>>> linkedExpensesAfterPage(
    String businessId, {int limit = 500, String? afterAllocationId}
  ) async {
    cursors.add(afterAllocationId);
    if (afterAllocationId == null) {
      return List.generate(limit, (i) => <String, dynamic>{
        'allocation_id': 'allocation-${i.toString().padLeft(4, '0')}',
        'transaction_id': 'txn-$i',
        'job_id': 'job-6306',
        'amount': 1,
      });
    }
    if (afterAllocationId == 'allocation-0499') {
      return [
        <String, dynamic>{
          'allocation_id': repeatLastId ? afterAllocationId : 'allocation-0500',
          'transaction_id': 'txn-500',
          'job_id': 'job-6306',
          'amount': 2,
        },
      ];
    }
    throw StateError('Unexpected cursor: $afterAllocationId');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('linked expenses sync to job and invoice lookups, with empty result distinct from missing', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalFinancialCache(database: db);
    expect(await cache.loadLinkedExpenses('shop', jobId: 'job-6306'), isNull);
    final service = LinkedExpenseSyncService(
      database: db,
      cache: cache,
      api: _PagedExpenseApi(),
    );
    expect(await service.pull('shop'), 2);
    final job = await cache.loadLinkedExpenses('shop', jobId: 'job-6306');
    final invoice = await cache.loadLinkedExpenses(
      'shop', documentId: 'invoice-6306',
    );
    expect(job, hasLength(2));
    expect(invoice, hasLength(2));
    expect(job!.fold<double>(
      0, (sum, row) => sum + (row['amount'] as num).toDouble(),
    ), closeTo(262.37, 0.001));
    expect(await cache.loadLinkedExpenses('shop', jobId: 'unknown'), isEmpty);
    await db.close();
  });
  test('interrupted pull leaves the last completed snapshot intact', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalFinancialCache(database: db);
    await cache.saveLinkedExpenses('shop', [
      {
        'allocation_id': 'old-allocation',
        'id': 'old-transaction',
        'transaction_id': 'old-transaction',
        'job_id': 'job-6306',
        'amount': 19.0,
      },
    ]);
    final service = LinkedExpenseSyncService(
      database: db,
      cache: cache,
      api: _PagedExpenseApi(failFirstPage: true),
    );
    await expectLater(service.pull('shop'), throwsStateError);
    final cached = await cache.loadLinkedExpenses('shop', jobId: 'job-6306');
    expect(cached, hasLength(1));
    expect(cached!.single['amount'], 19.0);
    await db.close();
  });

  test('keyset sync fetches every page without repeating allocations',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _MultiPageExpenseApi();
    final cache = LocalFinancialCache(database: db);
    final svc = LinkedExpenseSyncService(database: db, cache: cache, api: api);
    expect(await svc.pull('shop-pages'), 501);
    expect(api.cursors, [null, 'allocation-0499']);
    final items = await cache.loadLinkedExpenses('shop-pages');
    expect(items, hasLength(501));
    expect(items!.last['allocation_id'], 'allocation-0500');
    await db.close();
  });

  test('duplicate allocation across pages leaves prior snapshot untouched',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _MultiPageExpenseApi(repeatLastId: true);
    final cache = LocalFinancialCache(database: db);
    await cache.saveLinkedExpenses('shop-dup', [
      <String, dynamic>{'allocation_id':'previous','amount':7},
    ]);
    final svc = LinkedExpenseSyncService(database: db,cache:cache,api:api);
    await expectLater(svc.pull('shop-dup'), throwsStateError);
    final rows = await cache.loadLinkedExpenses('shop-dup');
    expect(rows, hasLength(1));
    expect(rows!.single['allocation_id'], 'previous');
    await db.close();
  });

}
