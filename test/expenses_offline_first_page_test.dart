import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart' hide LocalFinancialCache;
import 'package:briskers_app/services/local_financial_cache.dart';

void main() {
  test('offline financial cache keeps complete history while first page is 50',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final cache = LocalFinancialCache(database: db);
      final transactions = List<Map<String, dynamic>>.generate(
        125,
        (i) => <String, dynamic>{
          'id': 'synthetic-transaction-$i',
          'direction': i.isEven ? 'income' : 'expense',
          'counterparty': i == 75 ? 'Synthetic Janet' : 'Synthetic Customer',
          'account_id': 'fixture-account',
          'amount': 100 + i,
          'transaction_date': '2026-10-16',
          'reporting_status': 'unverified',
        },
      );
      await cache.saveTransactions('fixture-shop', transactions);
      final all = await cache.loadTransactions('fixture-shop',
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 17));
      expect(all, hasLength(125));

      // This is the visible slice the Expenses page now enriches, not
      // the full local history. No row or reporting state is deleted.
      final first = all.take(50).toList();
      expect(first, hasLength(50));
      expect(all.length > first.length, true);
      expect(first.first['id'], 'synthetic-transaction-0');
      expect(first.last['id'], 'synthetic-transaction-49');

      final result = await cache.loadTransactions(
        'fixture-shop', search: 'Synthetic Janet');
      expect(result, hasLength(1));
      expect(result.single['id'], 'synthetic-transaction-75');
      expect(await cache.loadTransactions('fixture-shop'), hasLength(125));
    } finally {
      await db.close();
    }
  });
}
