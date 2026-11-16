import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/invoice_payment_feed.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Reginald #6357 cash is visible before finalization and represented once',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(() async {
        LocalDocumentDetailCache.sqliteWritesEnabled = false;
        await db.close();
      });
      await LocalDocumentDetailCache.initialize(db);
      await LocalDocumentDetailCache(database: db).save(
        'fixture',
        'invoice-6357',
        {
          'id': 'invoice-6357',
          'kind': 'invoice',
          'status': 'issued',
          'document_number': '6357',
          'customer_name': 'Reginald Willis',
          'total_amount': 1637.63,
          'payments': [
            {
              'id': 'cash-verified-6357',
              'state': 'pending',
              'pending_sync': true,
              'amount': 1637.63,
              'payment_method_name': 'Cash',
              'payment_date': '2026-11-12',
            },
          ],
        },
      );
      final feed = InvoicePaymentFeed(database: db);
      await feed.saveServerReceipts('fixture', []);
      final savedReceipt = await feed.pendingFromCachedInvoices('fixture');
      final canonical = {
        'id': 'verified-ledger-entry',
        'direction': 'income',
        'invoice_payment_id': 'cash-verified-6357',
        'document_id': 'invoice-6357',
        'amount': 1637.63,
        'transaction_date': '2026-11-12',
      };
      for (final term in [
        'Reginald Willis',
        'invoice #6357',
        r'$1,637.63',
        '11/12/2026',
      ]) {
        final offline = InvoicePaymentFeed.combine(
          financial: [],
          receipts: savedReceipt,
          direction: 'income',
          search: term,
        );
        expect(offline.single['amount'], 1637.63);
        expect(offline.single['payment_method_name'], 'Cash');
        final posted = InvoicePaymentFeed.combine(
          financial: [canonical],
          receipts: savedReceipt,
          direction: 'income',
          search: term,
        );
        expect(posted.single['id'], 'verified-ledger-entry');
      }
      expect(
        InvoicePaymentFeed.combine(
          financial: [],
          receipts: savedReceipt,
          startDate: DateTime(2026, 11, 16),
        ),
        isEmpty,
      );
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
    },
  );

  test(
    'all saved history includes detail-only rows and imports preserve matching local records',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final cache = LocalFinancialCache(database: db);
      final recent = {
        'id': 'recent',
        'direction': 'income',
        'amount': 200,
        'transaction_date': '2026-11-16',
      };
      final old = {
        'id': 'older-detail',
        'direction': 'expense',
        'counterparty': 'WorldPac',
        'document_number': '6357',
        'amount': 99.5,
        'date': '2025-05-01',
      };
      await cache.saveTransactions('fixture', [recent]);
      await cache.saveTransactionDetail('fixture', 'older-detail', old);
      expect(await cache.postedHistoryCoverage('fixture'), isNull);
      final all = await cache.loadTransactions(
        'fixture',
        includeCachedDetails: true,
      );
      expect(all.map((r) => r['id']), ['recent', 'older-detail']);
      for (final term in [
        'worldpac',
        r'$99.50',
        'May 1, 2025',
        'invoice #6357',
      ]) {
        final matches = await cache.loadTransactions(
          'fixture',
          includeCachedDetails: true,
          search: term,
        );
        expect(matches.single['id'], 'older-detail');
      }
      expect(
        await cache.loadTransactions(
          'fixture',
          includeCachedDetails: true,
          startDate: DateTime(2026, 11, 1),
        ),
        hasLength(1),
      );
      await cache.mergeServerTransactions('fixture', [
        {...recent, 'amount': 500},
      ], onlyMissing: true);
      expect((await cache.loadTransactions('fixture')).single['amount'], 200);
      await cache.savePostedHistoryCoverage(
        'fixture',
        null,
        DateTime(2026, 11, 16),
      );
      expect((await cache.postedHistoryCoverage('fixture'))?.start, isNull);
      expect(
        (await cache.postedHistoryCoverage('fixture'))?.end,
        DateTime(2026, 11, 16),
      );
    },
  );
}
