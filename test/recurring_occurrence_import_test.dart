import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('verified occurrence persists once and leaves pending expenses intact',
      () async {
    final dir = await Directory.systemTemp.createTemp('recurring-import-');
    final file = File('${dir.path}/shop.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    const occurrence = {
      'id': 'server-expense',
      'business_id': 'shop',
      'recurring_rule_id': 'weekly-rule',
      'recurring_occurrence_date': '2026-11-04',
      'date': '2026-11-04',
      'direction': 'expense',
      'status': 'posted',
      'account_id': 'checking',
      'category_id': 'supplies',
      'counterparty_id': 'supplier',
      'amount': 105.29,
      'remarks': 'weekly supplies',
    };
    var cache = LocalFinancialCache(database: db);
    await cache.saveTransactions('shop', [
      {'id': 'local-unrelated', 'sync_state': 'pending', 'amount': 32},
    ]);
    await cache.importRecurringExpenseOccurrence(
      'shop', 'weekly-rule', '2026-11-04', occurrence,
    );
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(file));
    cache = LocalFinancialCache(database: db);
    await cache.importRecurringExpenseOccurrence(
      'shop', 'weekly-rule', '2026-11-04', occurrence,
    );
    final rows = await cache.loadTransactions('shop');
    expect(rows.map((row) => row['id']),
        unorderedEquals(['server-expense', 'local-unrelated']));
    expect(rows.singleWhere((row) => row['id'] == 'local-unrelated')['amount'], 32);
    final saved = await cache.loadTransactionDetail('shop', 'server-expense');
    expect(saved, containsPair('amount', 105.29));
    expect(saved, containsPair('remarks', 'weekly supplies'));

    // An ordinary limited refresh may omit the downloaded historical row.
    await cache.mergeServerTransactions('shop', []);
    expect(await cache.loadTransactions('shop'), hasLength(2));
    // If a later page includes it, merge by server ID and keep provenance.
    await cache.mergeServerTransactions('shop', [
      {'id': 'server-expense', 'amount': 105.29},
    ]);
    final refreshed = await cache.loadTransactions('shop');
    expect(refreshed, hasLength(2));
    expect(refreshed.singleWhere((row) => row['id'] == 'server-expense'),
        containsPair('recurring_occurrence_date', '2026-11-04'));

    await expectLater(
      cache.importRecurringExpenseOccurrence('shop', 'weekly-rule',
          '2026-11-04', {...occurrence, 'id': 'different-server-expense'}),
      throwsStateError,
    );
    await cache.saveTransactionDetail('shop', 'server-expense', {
      ...occurrence, 'sync_state': 'pending', 'amount': 106,
    });
    await expectLater(
      cache.importRecurringExpenseOccurrence(
        'shop', 'weekly-rule', '2026-11-04', occurrence,
      ),
      throwsStateError,
    );
    expect((await cache.loadTransactionDetail('shop', 'server-expense'))?['amount'], 106);
  });
}
