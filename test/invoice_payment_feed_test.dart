import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_financial_cache.dart'
    as financial;
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';
import 'package:briskers_app/services/invoice_payment_feed.dart';

Map<String, dynamic> receipt(String id, String state, double amount,
    {String? transactionId, String? operationId, String invoice = 'inv-1',
    String? coverage}) => {
  'receipt_id': id,
  'receipt_state': state,
  'transaction_id': transactionId,
  'operation_id': operationId,
  'invoice_id': invoice,
  'document_number': '6348',
  'customer_name': 'Janet Williams',
  'amount': amount,
  'invoice_total': 175.60,
  'transaction_date': '2026-10-17',
  'received_at': '2026-10-17T12:00:00Z',
  'coverage': coverage ?? 'paid',
};

void main() {
  test('local outbox is immediately visible, without server or finalization',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      const business = 'local-shop';
      await db.customStatement(
        "INSERT INTO local_customers (id,business_id,display_name)"
        " VALUES ('cust-1',?,'Janet Williams')", [business]);
      await db.customStatement(
        "INSERT INTO local_documents (id,business_id,kind,customer_id,"
        "document_number,total) VALUES ('inv-1',?,'invoice',"
        "'cust-1','6348',175.60)", [business]);
      final ledger = OfflineInvoicePaymentLedger(database: db);
      final operationId = await ledger.recordReceivedPayment(
        business, 'inv-1',
        amount: 175.60, remainingBeforePaymentCents: 17560,
        methodId: 'debit-method', methodName: 'Debit Card',
      );
      final feed = InvoicePaymentFeed(
        database: db, cache: financial.LocalFinancialCache(database: db));
      final rows = await feed.load(business);
      expect(rows, hasLength(1));
      expect(rows.single['receipt_id'], operationId);
      expect(rows.single['amount'], 175.60);
      expect(rows.single['receipt_state'], 'local');
      final cards = InvoicePaymentFeed.combine(financial: [], receipts: rows);
      expect(cards, hasLength(1));
      expect(cards.single['_payment_coverage'], 'paid');
      expect(cards.single['_receipt_state'], 'local');
      expect(cards.single['document_number'], '6348');
    } finally {
      await db.close();
    }
  });

  test('server pending + partial/full remain separate, but only one per ID',
      () {
    final input = [
      receipt('pay-1', 'pending', 10, coverage: 'partial'),
      receipt('pay-2', 'pending', 3649.08, coverage: 'paid'),
    ];
    final rows = InvoicePaymentFeed.mergeReceipts(
        input, [receipt('pay-1', 'local', 10)]);
    expect(rows, hasLength(2));
    final cards = InvoicePaymentFeed.combine(financial: [], receipts: rows);
    expect(cards, hasLength(2));
    expect(cards.where((r) => r['_payment_coverage']=='partial'), hasLength(1));
    expect(cards.where((r) => r['_payment_coverage']=='paid'), hasLength(1));
  });

  test('server-saved but unfinalized payment is synchronized for icon only',
      () {
    final cards = InvoicePaymentFeed.combine(
      financial: [],
      receipts: [receipt('server-pending','pending',175.60)],
    );
    expect(cards, hasLength(1));
    expect(cards.single['_receipt_state'], 'pending');
    expect(cards.single['_payment_coverage'], 'paid');
    expect(cards.single['_invoice_receipt'], true);
    // Pending receipts are visible but are not posted transactions.
  });

  test('posted receipt replaces exact posted transaction, not others', () {
    final posted = {
      'id': 'transaction-1', 'direction': 'income',
      'amount': 175.60, 'transaction_date': '2026-10-17',
      'counterparty': 'Janet Williams'
    };
    final separate = {
      'id': 'unrelated-income', 'direction': 'income',
      'amount': 25, 'transaction_date': '2026-10-17',
      'counterparty': 'Other'
    };
    final cards = InvoicePaymentFeed.combine(
      financial: [posted, separate],
      receipts: [receipt('allocation-1','posted',175.60,
          transactionId: 'transaction-1')],
    );
    expect(cards, hasLength(2));
    expect(cards.where((x)=>x['_invoice_receipt']==true), hasLength(1));
    expect(cards.where((x)=>x['id']=='unrelated-income'), hasLength(1));
    expect(cards.fold<double>(0,
        (sum,r)=>sum + (r['amount'] as num).toDouble()), 200.60);
  });

  test('server ID/operation ID remove queued duplicate, amounts alone do not', () {
    final a = receipt('server-uuid','pending',175.60);
    final localAck = receipt('op-uuid','local',175.60)
        ..['server_payment_id']='server-uuid';
    final separateSameAmount = receipt('new-op','local',175.60);
    final rows = InvoicePaymentFeed.mergeReceipts(
      [a], [localAck, separateSameAmount]);
    expect(rows.map((r)=>r['receipt_id']), containsAll(['server-uuid','new-op']));
    expect(rows, hasLength(2));
  });

  test('lost-response replay uses operation UUID to suppress duplication', () {
    final server = receipt('server-id','pending',175.60,
        operationId: 'lost-response-op');
    final queued = receipt('lost-response-op','local',175.60);
    final combined = InvoicePaymentFeed.mergeReceipts([server], [queued]);
    expect(combined, hasLength(1));
    expect(combined.single['receipt_id'], 'server-id');
  });

  test('offline search/range/direction filter invoice receipts', () {
    final data = [receipt('one','pending',175.60)];
    expect(InvoicePaymentFeed.combine(
      financial: [], receipts: data, search: '6348'), hasLength(1));
    expect(InvoicePaymentFeed.combine(
      financial: [], receipts: data, search: 'Worldpac'), isEmpty);
    expect(InvoicePaymentFeed.combine(
      financial: [], receipts: data, direction: 'expense'), isEmpty);
    expect(InvoicePaymentFeed.combine(
      financial: [], receipts: data, startDate: DateTime(2026, 10, 18)), isEmpty);
  });
}
