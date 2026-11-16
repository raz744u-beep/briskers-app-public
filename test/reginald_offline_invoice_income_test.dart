import 'dart:io';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/invoice_payment_feed.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_invoice_closure.dart';
import 'package:briskers_app/services/local_financial_totals_journal.dart';
import 'package:briskers_app/services/offline_invoice_finalization.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';
import 'package:briskers_app/widgets/job_financial_status_card.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final queued in [false, true]) {
    test(
      'Reginald #6357 J-38 posts existing cash once (outbox: $queued)',
      () async {
        const business = 'shop';
        const invoice = 'invoice-uuid';
        const job = 'job-uuid';
        const date = '2026-11-03';
        const receipt = {
          'id': 'existing-receipt',
          'state': 'pending',
          'amount': 1637.63,
          'payment_method_id': 'cash-method',
          'payment_method_name': 'Cash',
          'payment_date': date,
          'pending_sync': true,
        };
        final detail = <String, dynamic>{
          'id': invoice,
          'kind': 'invoice',
          'document_number': '6357',
          'job_id': job,
          'job_number': 'J-38',
          'customer_name': 'Reginald Willis',
          'status': 'issued',
          'total_amount': 1637.63,
          'paid_amount': 0,
          'pending_payment': queued ? 0 : 1637.63,
          'payments': queued ? [] : [receipt],
        };
        SharedPreferences.setMockInitialValues({});
        await BriskersConnectionModeController.instance.setMode(
          BriskersConnectionMode.offline,
        );
        final dir = await Directory.systemTemp.createTemp('reginald-income-');
        final file = File('${dir.path}/briskers.sqlite');
        var db = BriskersLocalDatabase(NativeDatabase(file));
        addTearDown(() async {
          await db.close();
          await dir.delete(recursive: true);
          LocalDocumentDetailCache.sqliteWritesEnabled = false;
        });
        await LocalDocumentDetailCache.initialize(db);
        await LocalDocumentDetailCache(
          database: db,
        ).save(business, invoice, detail);
        String? operation;
        if (queued) {
          operation = await OfflineInvoicePaymentLedger(database: db)
              .recordReceivedPayment(
                business,
                invoice,
                amount: 1637.63,
                remainingBeforePaymentCents: 163763,
                methodId: 'cash-method',
                methodName: 'Cash',
                paymentDate: date,
              );
        }

        final before =
            (await db.customSelect('SELECT * FROM sync_outbox').get())
                .map((row) => row.data)
                .toList();
        final feed = InvoicePaymentFeed(database: db);
        await feed.saveServerReceipts(business, []);
        if (!queued) expect(await feed.load(business), isEmpty);
        final service = OfflineInvoiceFinalization(database: db);
        await service.save(business, [invoice], isOwner: true, close: false);
        await db.customStatement(
          "INSERT INTO sync_outbox (business_id,entity_type,entity_id,operation,"
          "payload_json,state,attempt_count,created_at) "
          "VALUES (?,'document_edit',?,'memo','{}','pending',0,1793700000)",
          [business, invoice],
        );
        await Future.wait([
          service.finalizeLocally(
            business,
            invoice,
            isOwner: true,
            resumeSavedRequest: true,
          ),
          service.finalizeLocally(business, invoice, isOwner: true),
        ]);
        expect(
          (await db
                  .customSelect(
                    "SELECT * FROM sync_outbox WHERE entity_type='invoice_payment_received'",
                  )
                  .get())
              .map((row) => row.data)
              .toList(),
          before,
        );
        await db.close();
        db = BriskersLocalDatabase(NativeDatabase(file));
        await LocalDocumentDetailCache.initialize(db);
        await OfflineInvoiceFinalization(
          database: db,
        ).finalizeLocally(business, invoice, isOwner: true);

        final raw = (await LocalDocumentDetailCache(
          database: db,
        ).loadReadOnly(business, invoice))!;
        expect(raw['payments'], detail['payments']);
        final projected = await LocalInvoiceClosureStore(db).projectFinalized(
          business,
          OfflineInvoicePaymentLedger.projectPendingPayments(
            raw,
            await OfflineInvoicePaymentLedger(
              database: db,
            ).pendingForInvoice(business, invoice),
          ),
        );
        expect(projected['paid_amount'], 1637.63);
        expect(projected['pending_payment'], 0);
        expect((projected['payments'] as List).single['state'], 'posted');
        expect(cachedVerifiedJobPaymentState([projected]), 'paid');

        final restartedFeed = InvoicePaymentFeed(database: db);
        final rows = await restartedFeed.load(business);
        final card = InvoicePaymentFeed.combine(
          financial: [],
          receipts: rows,
        ).single;
        expect(card, containsPair('counterparty', 'Reginald Willis'));
        expect(card, containsPair('amount', 1637.63));
        expect(card, containsPair('document_number', '6357'));
        expect(card, containsPair('document_id', invoice));
        expect(card, containsPair('job_number', 'J-38'));
        expect(card, containsPair('transaction_date', date));
        expect(card, containsPair('payment_method_name', 'Cash'));
        expect(card, containsPair('id', operation ?? 'existing-receipt'));
        expect(InvoicePaymentFeed.paymentLabel(card), 'Paid');
        expect(
          InvoicePaymentFeed.syncLabel(card),
          'Local · saved on this device',
        );

        final journal = LocalFinancialTotalsJournal(database: db);
        expect(await journal.pendingCount(business), 1);

        final serverPending = {
          ...rows.single,
          'receipt_id': 'existing-receipt',
          'operation_id': operation,
          'receipt_state': 'pending',
        };
        if (queued) {
          await BriskersConnectionModeController.instance.setMode(
            BriskersConnectionMode.auto,
          );
          await OfflineInvoicePaymentLedger(database: db).flush(
            business,
            submitPayment: (_, _, amount, method, key) async {
              expect(amount, 1637.63);
              expect(method, 'cash-method');
              expect(key, operation);
              return 'existing-receipt';
            },
            fetchInvoice: (_, _) async => {
              ...detail,
              'pending_payment': 1637.63,
              'payments': [
                {...receipt, 'pending_sync': false},
              ],
            },
          );
          expect(
            await OfflineInvoicePaymentLedger(
              database: db,
            ).pendingForInvoice(business, invoice),
            isEmpty,
          );
          await BriskersConnectionModeController.instance.setMode(
            BriskersConnectionMode.offline,
          );
          final acknowledged = await LocalDocumentDetailCache(
            database: db,
          ).loadReadOnly(business, invoice);
          expect(
            (await LocalInvoiceClosureStore(
              db,
            ).projectFinalized(business, acknowledged!))['paid_amount'],
            1637.63,
          );
          await OfflineInvoiceFinalization(
            database: db,
          ).finalizeLocally(business, invoice, isOwner: true);
        }
        serverPending['operation_id'] = null;
        await restartedFeed.saveServerReceipts(business, [serverPending]);
        expect(
          (await restartedFeed.load(business)).single['receipt_state'],
          'local_finalized',
        );
        final allocation = {
          ...serverPending,
          'receipt_id': 'legacy-allocation',
          'operation_id': null,
          'transaction_id': 'posted-transaction',
          'receipt_state': 'posted',
        };
        await restartedFeed.saveServerReceipts(business, [allocation]);
        final posted = [
          <String, dynamic>{
            'id': 'posted-transaction',
            'direction': 'income',
            'amount': 1637.63,
            'transaction_date': date,
          },
        ];
        final remoteReceipts = await restartedFeed.load(business);
        final afterSync = InvoicePaymentFeed.combine(
          financial: posted,
          receipts: remoteReceipts,
        );
        expect(afterSync.single['id'], 'posted-transaction');
        await journal.reconcile(business, posted, receipts: remoteReceipts);
        expect(await journal.pendingCount(business), 0);
      },
    );
  }
}
