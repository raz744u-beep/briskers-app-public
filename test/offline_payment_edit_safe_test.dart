import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';

void main() {
  test('editing unsent receipt retains operation UUID and corrects all fields', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final ledger = OfflineInvoicePaymentLedger(database: db);
      const shop = 'edit-sandbox';
      const invoice = 'local-invoice-edit-test';
      final op = await ledger.recordReceivedPayment(
        shop, invoice,
        amount: 175.60,
        remainingBeforePaymentCents: 17560,
        methodId: 'debit-method', methodName: 'Debit Card',
      );
      final captured = (await ledger.pendingForInvoice(shop, invoice)).single;
      final actualLocal = DateTime.now();
      final today = '${actualLocal.year.toString().padLeft(4, '0')}-'
          '${actualLocal.month.toString().padLeft(2, '0')}-'
          '${actualLocal.day.toString().padLeft(2, '0')}';
      expect(captured['payment_date'], today);
      expect(captured['received_at'], isNotEmpty);
      final before = (await ledger.pendingForInvoice(shop, invoice)).single;
      await ledger.editNeverSubmittedPayment(shop, invoice, op,
        amount: 150.25, maximumAllowedCents: 17560,
        methodId: 'cash-method', methodName: 'Cash',
        paymentDate: '2026-10-16');
      final after = await ledger.pendingForInvoice(shop, invoice);
      expect(after, hasLength(1));
      expect(after.single['operation_id'], op);
      expect(after.single['received_at'], before['received_at']);
      expect(after.single['amount_cents'], 15025);
      expect(after.single['method_id'], 'cash-method');
      expect(after.single['method_name'], 'Cash');
      expect(after.single['payment_date'], '2026-10-16');
      final projected = OfflineInvoicePaymentLedger.projectPendingPayments(
        {'total_amount': 175.60, 'paid_amount': 0, 'pending_payment': 0},
        after);
      expect(projected['pending_payment'], 150.25);
      final payment = (projected['payments'] as List).single as Map;
      expect(payment['entered_at'], '2026-10-16');
      expect(payment['id'], op);
    } finally {
      await db.close();
    }
  });

  test('attempted replay cannot be edited or submitted a second time', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final ledger = OfflineInvoicePaymentLedger(database: db);
      const shop = 'payment-attempt-sandbox';
      const invoice = 'local-invoice-attempt-test';
      final op = await ledger.recordReceivedPayment(
        shop, invoice, amount: 100, remainingBeforePaymentCents: 10000,
        methodId: 'cash', methodName: 'Cash');
      final before = (await ledger.pendingForInvoice(shop, invoice)).single;
      await db.customStatement(
        "UPDATE sync_outbox SET attempt_count=1 WHERE business_id=? "
        "AND entity_type='invoice_payment_received'",
        [shop]);
      await expectLater(
        ledger.editNeverSubmittedPayment(shop, invoice, op,
          amount: 80, maximumAllowedCents: 10000,
          methodId: 'cash', methodName: 'Cash',
          paymentDate: '2026-10-16'),
        throwsStateError);
      final after = (await ledger.pendingForInvoice(shop, invoice)).single;
      expect(jsonEncode(after), jsonEncode(before));
    } finally {
      await db.close();
    }
  });
  test('server pending edit is one queued correction and preserves payment ID', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final ledger=OfflineInvoicePaymentLedger(database:db);
      const shop='server-edit-sandbox';
      const invoice='invoice-server-edit';
      const payment='pending-payment-id';
      await ledger.queueServerPendingEdit(
        shop,invoice,payment,expectedRowVersion:3,
        amount:150.25,maximumAllowedCents:17560,
        methodId:'cash',methodName:'Cash',paymentDate:'2026-10-16');
      await ledger.queueServerPendingEdit(
        shop,invoice,payment,expectedRowVersion:3,
        amount:160.50,maximumAllowedCents:17560,
        methodId:'card',methodName:'Debit Card',paymentDate:'2026-10-15');
      final pending=await ledger.pendingEditsForInvoice(shop,invoice);
      expect(pending,hasLength(1));
      expect(pending.single['payment_id'],payment);
      expect(pending.single['expected_row_version'],3);
      expect(pending.single['amount_cents'],16050);
      final projected=OfflineInvoicePaymentLedger.projectPendingEdits({
        'pending_payment':175.60,
        'payments':[{
          'id':payment,
          'state':'pending',
          'amount':175.60,
          'row_version':3,
          'payment_method_name':'Debit Card',
          'payment_method_id':'previous-method',
          'entered_at':'2026-10-17T11:05:00Z',
        }]
      },pending);
      expect(projected['pending_payment'],closeTo(160.50,0.0001));
      final shown=(projected['payments'] as List).single as Map;
      expect(shown['id'],payment);
      expect(shown['payment_date'],'2026-10-15');
      expect(shown['_local_pending_edit'],true);
      expect(shown['entered_at'],'2026-10-17T11:05:00Z');
    } finally { await db.close(); }
  });

  test('server version conflict does not overwrite cached receipt', () {
    final projected=OfflineInvoicePaymentLedger.projectPendingEdits({
      'pending_payment':100,
      'payments':[{'id':'p','state':'pending','amount':100,'row_version':5}],
    },[{
      'payment_id':'p','expected_row_version':4,
      'amount_cents':8000,'method_id':'cash','method_name':'Cash',
      'payment_date':'2026-10-16'
    }]);
    expect(projected['pending_payment'],100);
    expect(projected['_payment_reconciliation_required'],true);
    expect((projected['payments'] as List).single['amount'],100);
  });

  test('attempted queued server edit cannot be changed offline again', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final ledger=OfflineInvoicePaymentLedger(database:db);
      const shop='attempted-server-edit';
      const invoice='invoice-attempted';
      await ledger.queueServerPendingEdit(shop,invoice,'receipt',
        expectedRowVersion:1,amount:50,maximumAllowedCents:10000,
        methodId:'cash',methodName:'Cash',paymentDate:'2026-10-16');
      await db.customStatement(
        """UPDATE sync_outbox SET attempt_count=1
        WHERE business_id=? AND entity_type='invoice_pending_payment_edit'""",
        [shop]);
      await expectLater(
        ledger.queueServerPendingEdit(shop,invoice,'receipt',
          expectedRowVersion:1,amount:60,maximumAllowedCents:10000,
          methodId:'card',methodName:'Card',paymentDate:'2026-10-17'),
        throwsStateError);
      expect((await ledger.pendingEditsForInvoice(shop,invoice)).single['amount_cents'],5000);
    } finally { await db.close(); }
  });

}
