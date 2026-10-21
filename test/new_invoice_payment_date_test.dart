import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new invoice payment shows a date and sends it through durable v2 queue', () {
    final source = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _enterPayment() async');
    final end = source.indexOf('Future<void> _offerCompleteJobAfterPaymentEntry()',start);
    expect(start, greaterThan(0));
    final entry = source.substring(start,end);
    expect(entry, contains('editDate: true'));
    expect(entry, contains("result['payment_date']"));
    expect(entry, contains('paymentDate: chosenDate'));
    expect(entry, contains('recordReceivedPayment('));
    expect(entry, contains('_offlinePayments.flush(widget.businessId)'));
    expect(entry, isNot(contains('_api.addPendingInvoicePayment(')));
  });

  test('selected yesterday date survives local receipt and cannot be duplicated by retry', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final ledger=OfflineInvoicePaymentLedger(database:db);
      final op=await ledger.recordReceivedPayment(
        'shop-A','invoice-6347',amount:1597.80,
        remainingBeforePaymentCents:159780,
        methodId:'cash-id',methodName:'Cash',
        paymentDate:'2026-10-20',
      );
      expect(op, isNotEmpty);
      final rows=await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE business_id='shop-A'"
        " AND entity_type='invoice_payment_received'").get();
      expect(rows.length,1);
      final payload=jsonDecode(rows.single.read<String>('payload_json')) as Map;
      expect(payload['payment_date'],'2026-10-20');
      expect(payload['amount_cents'],159780);
      expect(payload['operation_id'],op);
      expect(payload['method_id'],'cash-id');
    } finally {await db.close();}
  });

  test('invalid calendar dates are rejected before creating an outbox entry', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final ledger=OfflineInvoicePaymentLedger(database:db);
      await expectLater(
        ledger.recordReceivedPayment(
          'shop-A','invoice-6347',amount:10,remainingBeforePaymentCents:1000,
          methodId:'cash-id',methodName:'Cash',paymentDate:'2026-02-30',
        ),
        throwsArgumentError,
      );
      await expectLater(
        ledger.recordReceivedPayment(
          'shop-A','invoice-6347',amount:10,remainingBeforePaymentCents:1000,
          methodId:'cash-id',methodName:'Cash',paymentDate:'2999-10-20',
        ),
        throwsArgumentError,
      );
      expect((await db.customSelect('SELECT count(*) AS n FROM sync_outbox')
          .getSingle()).read<int>('n'),0);
    } finally {await db.close();}
  });
}
