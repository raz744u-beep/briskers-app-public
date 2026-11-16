import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';

void main() {
  late BriskersLocalDatabase db;
  setUp(() => db=BriskersLocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('Owner recovery held receipt still appears but stays blocked from upload', () async {
    final payment = {
      'operation_id':'synthetic-once','invoice_id':'invoice-a',
      'amount_cents':300000,'payment_date':'2026-10-19',
      'method_id':'card','method_name':'Credit Card'
    };
    await db.customStatement(
      '''INSERT INTO sync_outbox(business_id,entity_type,entity_id,
        operation,payload_json,state,attempt_count,created_at,last_error)
        VALUES(?, 'invoice_payment_received', ?, 'record_received_payment',
        ?, 'conflict', 0, 1793301845, ?)''',
      ['business-a','invoice-a',jsonEncode(payment),
       'Owner recovery payment preserved; sync disabled'],
    );
    final ledger=OfflineInvoicePaymentLedger(database:db);
    final rows=await ledger.pendingForInvoice('business-a','invoice-a');
    expect(rows.length,1);
    expect(rows.single['amount_cents'],300000);
    final source=await db.customSelect('SELECT state FROM sync_outbox').getSingle();
    expect(source.read<String>('state'),'conflict');
  });

  test('ordinary conflict payments are not projected as received', () async {
    await db.customStatement(
      '''INSERT INTO sync_outbox(business_id,entity_type,entity_id,
        operation,payload_json,state,attempt_count,created_at,last_error)
        VALUES(?, 'invoice_payment_received', ?, 'record_received_payment',
        ?, 'conflict', 0, 1793301845, ?)''',
      ['business-a','invoice-a',
       jsonEncode({'operation_id':'synthetic-ambiguous','amount_cents':300000}),
       'Unrelated sync conflict'],
    );
    final rows=await OfflineInvoicePaymentLedger(database:db)
      .pendingForInvoice('business-a','invoice-a');
    expect(rows,isEmpty);
  });
}
