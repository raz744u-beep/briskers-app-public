import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';

Map<String, dynamic> row(
  String id, {
  String date = '2026-10-23',
  String category = 'Payroll',
  String counterparty = 'Kamerron',
  num amount = 500,
  String? syncState,
}) => <String, dynamic>{
  'id': id,
  'direction': 'expense',
  'kind': 'payroll',
  'transaction_date': date,
  'category': category,
  'counterparty': counterparty,
  'amount': amount,
  'sync_state': ?syncState,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('limited server refresh preserves older saved payroll and other expenses',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = LocalFinancialCache(database: db);

    final historical = List.generate(
      75,
      (index) => row('history-$index',
          date: index.isEven ? '2026-08-21' : '2026-09-25',
          counterparty: index.isEven ? 'Chris Rideaux' : 'Kamerron'),
    );
    await cache.saveTransactions('shop', [
      ...historical,
      row('local-oct-30', date: '2026-10-30', amount: 700,
          syncState: 'pending'),
    ]);

    await cache.mergeServerTransactions('shop', [
      row('server-nov-06', date: '2026-11-06', amount: 600),
      row('history-0', date: '2026-08-21', amount: 880),
    ]);

    final saved = await cache.loadTransactions('shop');
    expect(saved.length, 77);
    expect(saved.where((entry) => entry['id'] == 'history-74').length, 1);
    expect(saved.singleWhere((entry) => entry['id'] == 'history-0')['amount'],
        880);
    expect(saved.singleWhere((entry) =>
        entry['id'] == 'local-oct-30')['sync_state'], 'pending');

    // Refreshing the same server page twice never duplicates saved rows.
    await cache.mergeServerTransactions('shop', [
      row('server-nov-06', date: '2026-11-06', amount: 600),
    ]);
    expect((await cache.loadTransactions('shop')).length, 77);
  });

  test('pending local edits win against matching remote ID', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = LocalFinancialCache(database: db);
    await cache.saveTransactions('shop', [
      row('same-id', amount: 950, syncState: 'pending'),
    ]);
    await cache.mergeServerTransactions('shop', [
      row('same-id', amount: 900),
    ]);
    final saved = await cache.loadTransactions('shop');
    expect(saved.length, 1);
    expect(saved.single['amount'], 950);
    expect(saved.single['sync_state'], 'pending');
  });

  test('90-day local filtering searches all saved rows, not only first 50',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = LocalFinancialCache(database: db);
    await cache.saveTransactions('shop', [
      for (var index = 0; index < 130; index++)
        row('history-$index',
            date: index.isEven ? '2026-08-21' : '2026-10-23',
            counterparty: index >= 100 ? 'Chris Rideaux' : 'Kamerron'),
    ]);
    final all = await cache.loadTransactions('shop',
        startDate: DateTime(2026, 8, 11),
        endDate: DateTime(2026, 11, 8),
        direction: 'expense');
    expect(all.length, 130);
    expect(all.skip(100).take(50).length, 30);

    final chris = await cache.loadTransactions('shop',
        search: 'Chris Rideaux');
    expect(chris.length, 30);
  });

  test('business financial cache data remains isolated', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = LocalFinancialCache(database: db);
    await cache.saveTransactions('shop-a', [row('a')]);
    await cache.mergeServerTransactions('shop-b', [row('b')]);
    expect((await cache.loadTransactions('shop-a')).single['id'], 'a');
    expect((await cache.loadTransactions('shop-b')).single['id'], 'b');
  });
}
