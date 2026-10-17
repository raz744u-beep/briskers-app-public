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
}
