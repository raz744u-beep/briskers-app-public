import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/invoice_expense_reader.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BriskersLocalDatabase db;
  late LocalFinancialCache cache;
  setUp(() {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    cache = LocalFinancialCache(database: db);
  });
  tearDown(() => db.close());

  Map<String, dynamic> expense(String id, {String? job, String? document}) => {
    'id': id, 'business_id': 'shop', 'direction': 'expense',
    'job_id': job, 'document_id': document, 'amount': 25,
    'transaction_date': '2026-11-18', 'status': 'posted',
  };

  test('Auto returns saved invoice and job shares without invoking remote', () async {
    await cache.saveLinkedExpenses('shop', [
      {...expense('split', job: 'job'), 'allocation_id': 'a', 'amount': 10},
      {...expense('split', job: 'other'), 'allocation_id': 'b', 'amount': 15},
      expense('invoice-only', document: 'invoice'),
      expense('unrelated', job: 'other'),
    ]);
    final rows = await InvoiceExpenseReader(cache: cache).load(
      businessId: 'shop', documentId: 'invoice', jobId: 'job', offline: false,
      fetchRemote: () => throw StateError('Network must not gate saved expenses'),
    );
    expect(rows!.map((row) => row['id']), unorderedEquals(['split', 'invoice-only']));
    expect(rows.singleWhere((row) => row['id'] == 'split')['amount'], 10);
  });

  test('known empty stays local, uncached offline never requests network', () async {
    final reader = InvoiceExpenseReader(cache: cache);
    var requests = 0;
    Future<List<Map<String, dynamic>>> remote() async {
      requests++;
      return [expense('remote', document: 'invoice')];
    }
    expect(await reader.load(businessId: 'shop', documentId: 'invoice',
      offline: true, fetchRemote: remote), isNull);
    expect(requests, 0);
    expect(await reader.load(businessId: 'shop', documentId: 'invoice',
      offline: false, fetchRemote: remote), hasLength(1));
    expect(requests, 1);
    await cache.saveLinkedExpenses('shop', []);
    expect(await reader.load(businessId: 'shop', documentId: 'invoice',
      offline: false, fetchRemote: remote), isEmpty);
    expect(requests, 1);
  });

  test('scoped reads match full history through pending moves, detail-only data and split shares', () async {
    await cache.saveLinkedExpenses('shop', [
      expense('moved-out', job: 'job'),
      expense('unlinked', document: 'invoice'),
      expense('allocated-elsewhere', job: 'other'),
      {...expense('split', job: 'job'), 'allocation_id': 'share-1', 'amount': 10},
      {...expense('split', job: 'job'), 'allocation_id': 'share-2', 'amount': 15},
    ]);
    await cache.saveTransactions('shop', [
      {...expense('moved-out', job: 'other'), 'sync_state': 'pending'},
      {...expense('unlinked'), 'sync_state': 'pending'},
      {...expense('moved-in', job: 'job'), 'sync_state': 'pending'},
      expense('split', job: 'job'),
      expense('allocated-elsewhere', job: 'job'),
    ]);
    await cache.saveTransactionDetail('shop', 'detail-only', expense('detail-only', document: 'invoice'));
    final full = (await cache.loadLinkedExpenses('shop'))!;
    final scoped = await cache.loadLinkedExpenses('shop', documentId: 'invoice', relatedJobId: 'job');
    expect(scoped, unorderedEquals(full.where((row) => row['job_id'] == 'job' || row['document_id'] == 'invoice')));
    expect(scoped!.map((row) => row['id']), unorderedEquals(['split', 'split', 'moved-in', 'detail-only']));
    expect(scoped.where((row) => row['id'] == 'split').fold<num>(0, (n,r) => n + (r['amount'] as num)), 25);
  });

  test('large saved archive returns only this invoice and preserves other-shop isolation', () async {
    await cache.saveLinkedExpenses('shop', [
      for (var i = 0; i < 3000; i++) expense('expense-$i', job: 'job-$i'),
      {...expense('foreign', document: 'invoice'), 'business_id': 'other-shop'},
    ]);
    await cache.saveTransactions('shop', [
      for (var i = 0; i < 3000; i++) expense('expense-$i', job: 'job-$i'),
    ]);
    await db.transaction(() async {
      for (var i = 0; i < 3000; i++) {
        await db.customStatement(
          'INSERT INTO local_financial_cache(business_id,cache_key,payload_json) VALUES (?,?,?)',
          ['shop', 'transaction_detail_expense-$i', jsonEncode(expense('expense-$i', job: 'job-$i'))],
        );
      }
      // Corrupt unrelated blobs must not break the scoped SQL query.
      await db.customStatement(
        'INSERT INTO local_financial_cache(business_id,cache_key,payload_json) VALUES (?,?,?)',
        ['shop', 'transaction_detail_bad', '{bad'],
      );
    });
    final watch = Stopwatch()..start();
    final rows = await InvoiceExpenseReader(cache: cache).load(
      businessId: 'shop', documentId: 'invoice', jobId: 'job-42', offline: true,
      fetchRemote: () => throw StateError('Offline network request'),
    );
    watch.stop();
    expect(rows!.map((r) => r['id']), ['expense-42']);
    // Informational timing, not a device-independent latency promise.
    // ignore: avoid_print
    print('Scoped invoice read, 3000 archived expenses: ${watch.elapsedMilliseconds}ms');
    final unchanged = await db.customSelect(
      "SELECT count(*) AS n FROM local_financial_cache WHERE cache_key GLOB 'transaction_detail_*'",
    ).getSingle();
    expect(unchanged.read<int>('n'), 3001);
  });
  test('scoped snapshots keep large unrelated payloads inside SQLite, including empty invoices', () async {
    final largeNote=List.filled(24000,'x').join();
    await cache.saveLinkedExpenses('shop',[
      for(var i=0;i<1500;i++) {...expense('archive-$i',job:'other'),'description':largeNote},
      {...expense('selected',document:'invoice'),'allocation_id':'share','amount':12.5},
    ]);
    await cache.saveTransactions('shop',[
      for(var i=0;i<1500;i++) {...expense('archive-$i',job:'other'),'description':largeNote},
      expense('selected',document:'invoice'),
    ]);
    final watch=Stopwatch()..start();
    final rows=await cache.loadLinkedExpenses('shop',documentId:'invoice',relatedJobId:'job');
    expect(rows!.single['amount'],12.5);
    expect(await cache.loadLinkedExpenses('shop',documentId:'empty',relatedJobId:'empty-job'),isEmpty);
    // Informational native read timing; do not claim a device latency guarantee.
    // ignore: avoid_print
    print('Scoped/empty invoice reads with 72MB archive: ${watch.elapsedMilliseconds}ms');
    final original=await db.customSelect("SELECT length(payload_json) AS n FROM local_financial_cache WHERE business_id='shop' AND cache_key='transactions_snapshot'").getSingle();
    expect(original.read<int>('n'),greaterThan(36000000));
  });

}
