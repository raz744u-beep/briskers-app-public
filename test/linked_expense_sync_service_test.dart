import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/linked_expense_sync_service.dart';
import 'package:briskers_app/services/local_financial_cache.dart';

class _PagedExpenseApi extends BriskersApi {
  _PagedExpenseApi({this.failOnOffset = -1});
  final int failOnOffset;

  @override
  Future<List<Map<String, dynamic>>> linkedExpensesPage(
    String businessId, {int limit = 500, int offset = 0}
  ) async {
    if (offset == failOnOffset) throw StateError('Network interruption');
    if (offset != 0) return const [];
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
}
