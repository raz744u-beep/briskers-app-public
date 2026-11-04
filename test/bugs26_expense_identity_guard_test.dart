import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'wrong expense or business cannot replace a scoped saved detail',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final cache = LocalFinancialCache(database: db);
      const original = {
        'id': 'expense-a',
        'business_id': 'shop-a',
        'amount': 73.51,
        'document_id': 'invoice-a',
      };
      await cache.saveTransactionDetail('shop-a', 'expense-a', original);
      for (final wrong in [
        {...original, 'id': 'expense-b'},
        {...original, 'business_id': 'shop-b'},
      ]) {
        await expectLater(
          cache.saveTransactionDetail('shop-a', 'expense-a', wrong),
          throwsArgumentError,
        );
      }
      expect(
        await cache.loadTransactionDetail('shop-a', 'expense-a'),
        original,
      );
      expect(await cache.loadTransactionDetail('shop-b', 'expense-a'), isNull);
      // Simulate an older contradictory cache payload without changing a real record.
      final corrupt = jsonEncode({...original, 'id': 'expense-other'});
      await db.customStatement(
        "UPDATE local_financial_cache SET payload_json=? WHERE business_id=? AND cache_key=?",
        [corrupt, 'shop-a', 'transaction_detail_expense-a'],
      );
      expect(await cache.loadTransactionDetail('shop-a', 'expense-a'), isNull);
      final stored = await db
          .customSelect('SELECT payload_json FROM local_financial_cache')
          .getSingle();
      expect(
        stored.read<String>('payload_json'),
        corrupt,
        reason: 'Read rejection does not repair, delete or rewrite records',
      );
    },
  );
}
