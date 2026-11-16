import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';

void main() {
  late BriskersLocalDatabase db;
  late LocalFinancialCache cache;

  setUp(() {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    cache = LocalFinancialCache(database: db);
  });
  tearDown(() async => db.close());

  test('complete historical expense remains available for editing', () async {
    await cache.saveTransactionDetail('shop', 'old-payment', {
      'id': 'old-payment',
      'amount': 700,
      'date': '2026-10-23',
      'account_id': 'capital-one',
      'category_id': 'payroll',
      'counterparty': 'Chris',
      'attachments': [{'id': 'receipt-1'}],
    });
    final record = await cache.loadTransactionForEdit('shop', 'old-payment');
    expect(record?['amount'], 700);
    expect(record?['date'], '2026-10-23');
    expect(record?['attachments'], hasLength(1));
  });

  test('summary-only cache cannot open a blank edit form', () async {
    await cache.saveTransactionDetail('shop', 'old-payment', {
      'id': 'old-payment',
      'amount': 700,
      'date': '2026-10-23',
    });
    expect(await cache.loadTransactionForEdit('shop', 'old-payment'), isNull);
  });

  test('mismatched transaction identity cannot be edited', () async {
    await cache.saveTransactionDetail('shop', 'old-payment', {
      'id': 'another-payment',
      'amount': 700,
      'date': '2026-10-23',
      'account_id': 'capital-one',
      'category_id': 'payroll',
    });
    expect(await cache.loadTransactionForEdit('shop', 'old-payment'), isNull);
  });
}
