import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Expense sync proof survives reopening cache only within its shop',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final cache = LocalFinancialCache(database: db);
      const businessId = 'briskers-shop-a';
      final worldpac = <String, dynamic>{
        'id': 'tx-worldpac-88',
        'direction': 'expense',
        'amount': 88.10,
        'transaction_date': '2026-10-20',
      };
      final signature = LocalFinancialCache.serverTransactionSignature(worldpac);
      await cache.saveServerConfirmedTransactions(businessId, [worldpac]);
      final reopened = LocalFinancialCache(database: db);
      expect((await reopened.loadServerConfirmedTransactions(businessId))
          ['tx-worldpac-88'], signature);
      expect(await reopened.loadServerConfirmedTransactions('shop-b'), isEmpty);
      expect(signature,
        isNot(LocalFinancialCache.serverTransactionSignature(
          {...worldpac, 'amount': 89.10})));
      expect(signature,
        isNot(LocalFinancialCache.serverTransactionSignature(
          {...worldpac, 'transaction_date': '2026-10-21'})));
    } finally {
      await db.close();
    }
  });

  test('Pending/failed rows never mint a synced proof', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final cache = LocalFinancialCache(database: db);
      final base = <String, dynamic>{
        'direction': 'expense',
        'amount': 145.91,
        'transaction_date': '2026-10-20',
      };
      await cache.saveServerConfirmedTransactions('shop', [
        {...base, 'id': 'pending', 'sync_state': 'pending_sync'},
        {...base, 'id': 'failed', 'sync_state': 'failed'},
        {...base, 'id': 'conflict', 'sync_state': 'conflict'},
        {...base, 'id': 'good', 'sync_state': 'synced'},
      ]);
      expect((await cache.loadServerConfirmedTransactions('shop')).keys,
          contains('good'));
      expect((await cache.loadServerConfirmedTransactions('shop')).keys,
          isNot(contains('pending')));
      expect((await cache.loadServerConfirmedTransactions('shop')).keys,
          isNot(contains('failed')));
      expect((await cache.loadServerConfirmedTransactions('shop')).keys,
          isNot(contains('conflict')));
    } finally {
      await db.close();
    }
  });

  test('Expired proof does not claim a previously synced transaction',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final cache = LocalFinancialCache(database: db);
      final oldTimestamp = DateTime.now().toUtc()
          .subtract(const Duration(days: 9)).millisecondsSinceEpoch;
      const id = 'worldpac-expired';
      final serialized = jsonEncode({
        'entries': {
          id: {'signature': 'old', 'verified_at': oldTimestamp},
        },
      });
      await db.customStatement(
        'INSERT INTO local_financial_cache '
        '(business_id, cache_key, payload_json, updated_at) '
        'VALUES (?, ?, ?, ?)',
        ['shop', 'server_transaction_proof_v1', serialized, 0],
      );
      expect(await cache.loadServerConfirmedTransactions('shop'), isEmpty);
    } finally {
      await db.close();
    }
  });
}
