import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('historical account correction preserves identity and financial values', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = LocalFinancialCache(database: db);
    const id = 'historical-chris-payment';
    final original = <String, dynamic>{
      'id': id, 'business_id': 'shop', 'direction': 'expense',
      'amount': 700, 'transaction_date': '2026-10-23',
      'account_id': 'old-account', 'account': 'Old account',
      'category_id': 'payroll', 'category': 'Payroll',
      'counterparty': 'Chris', 'remarks': 'Original payment',
      'attachments': <dynamic>[],
    };
    await cache.saveTransactions('shop', [original]);
    await cache.saveTransactionDetail('shop', id, original);
    final writer = OfflineFinancialWriteService(database: db, cache: cache);
    await writer.updateLocalTransaction('shop', id,
      direction: 'expense', accountId: 'business-checking',
      accountName: 'Business Checking', categoryId: 'payroll',
      categoryName: 'Payroll', amount: 700, date: DateTime(2026, 10, 23),
      counterpartyName: 'Chris', remarks: 'Original payment',
    );
    final saved = await cache.loadTransactionDetail('shop', id);
    expect(saved, isNotNull);
    expect(saved!['id'], id);
    expect(saved['account_id'], 'business-checking');
    expect(saved['amount'], 700);
    expect(saved['transaction_date'], '2026-10-23');
    expect(saved['category_id'], 'payroll');
    expect(saved['counterparty'], 'Chris');
    expect(saved['remarks'], 'Original payment');
    final rows = await cache.loadTransactions('shop');
    expect(rows.where((r) => r['id'] == id), hasLength(1));
    final outbox = await db.customSelect(
      "SELECT entity_type, entity_id, payload_json FROM sync_outbox "
      "WHERE business_id='shop' AND entity_type='financial_update'",
    ).get();
    expect(outbox, hasLength(1));
    expect(outbox.single.read<String>('entity_id'), id);
    final payload = jsonDecode(outbox.single.read<String>('payload_json')) as Map;
    expect(payload['account_id'], 'business-checking');
    expect(payload['amount'], 700);
  });
}
