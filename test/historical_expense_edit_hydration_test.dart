import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart' hide LocalFinancialCache;
import 'package:briskers_app/services/local_financial_cache.dart';

void main() {
  test('historical expense with complete saved row opens with original values', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = LocalFinancialCache(database: db);
    await cache.saveTransactions('shop', [{
      'id': 'old-payroll', 'business_id': 'shop', 'direction': 'expense',
      'amount': 700, 'transaction_date': '2026-10-23',
      'account_id': 'original-account', 'category_id': 'payroll',
      'counterparty': 'Chris', 'remarks': 'Historical payment',
    }]);
    final saved = await cache.loadTransactionForEdit('shop', 'old-payroll');
    expect(saved, isNotNull);
    expect(saved!['amount'], 700);
    expect(saved['transaction_date'], '2026-10-23');
    expect(saved['account_id'], 'original-account');
    expect(saved['category_id'], 'payroll');
    expect(saved['counterparty'], 'Chris');
    expect(saved['remarks'], 'Historical payment');
  });

  test('incomplete historical expense cannot open a blank edit target', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = LocalFinancialCache(database: db);
    await cache.saveTransactions('shop', [{
      'id': 'missing-fields', 'business_id': 'shop',
      'amount': 600, 'transaction_date': '2026-10-02',
    }]);
    expect(await cache.loadTransactionForEdit('shop', 'missing-fields'), isNull);
    expect(await cache.loadTransactionForEdit('other-shop', 'missing-fields'), isNull);
  });
}
