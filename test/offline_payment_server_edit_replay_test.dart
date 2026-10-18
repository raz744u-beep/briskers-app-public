import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';

class _PaymentServerFixture extends BriskersApi {
  int version=4;
  num amount=100;
  String method='old-method';
  String? date;
  String enteredAt='2026-10-16T21:18:33.879364Z';
  int editCalls=0;
  bool loseResponse=false;
  bool rejectConflict=false;

  @override
  Future<void> updatePendingInvoicePaymentV2(
    String businessId, String paymentId, {
    required num amount,
    required String methodId,
    required String paymentDate,
    required int expectedRowVersion,
  }) async {
    editCalls++;
    if(rejectConflict || expectedRowVersion!=version) {
      throw StateError('Version changed');
    }
    this.amount=amount;
    method=methodId;
    date=paymentDate;
    version++;
    if(loseResponse) throw StateError('Response lost after server commit');
  }

  @override
  Future<Map<String,dynamic>> documentDetailV4(
    String businessId,String documentId,
  ) async => {
    'id':documentId,
    'kind':'invoice',
    'total_amount':100,
    'pending_payment':amount,
    'paid_amount':0,
    'job_id':'',
    'payments':[{
      'id':'server-pending-payment',
      'state':'pending',
      'row_version':version,
      'amount':amount,
      'payment_method_id':method,
      'payment_method_name':'Cash',
      'payment_date':date,
      'entered_at':enteredAt,
    }],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('queued correction syncs by same payment ID and caches result', () async {
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final server=_PaymentServerFixture();
    try {
      const shop='safe-edit-1',invoice='invoice-1';
      final ledger=OfflineInvoicePaymentLedger(database:db,api:server);
      await ledger.queueServerPendingEdit(shop,invoice,'server-pending-payment',
        expectedRowVersion:4,amount:80.25,maximumAllowedCents:10000,
        methodId:'cash',methodName:'Cash',paymentDate:'2026-10-16');
      await ledger.flushPendingServerEdits(shop);
      expect(server.editCalls,1);
      expect(server.version,5);
      expect((await ledger.pendingEditsForInvoice(shop,invoice)),isEmpty);
      final detail=await LocalDocumentDetailCache(database:db)
          .load(shop,invoice);
      expect(detail?['pending_payment'],80.25);
      expect((detail?['payments'] as List).single['payment_date'],
        '2026-10-16');
    }finally{ await db.close(); }
  });

  test('lost reply acknowledged by exact ID and version without resending', () async {
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final server=_PaymentServerFixture()..loseResponse=true;
    try {
      const shop='safe-edit-2',invoice='invoice-2';
      final ledger=OfflineInvoicePaymentLedger(database:db,api:server);
      await ledger.queueServerPendingEdit(shop,invoice,'server-pending-payment',
        expectedRowVersion:4,amount:99.50,maximumAllowedCents:10000,
        methodId:'debit',methodName:'Debit Card',paymentDate:'2026-10-16');
      await ledger.flushPendingServerEdits(shop);
      expect(server.editCalls,1);
      expect((await ledger.pendingEditsForInvoice(shop,invoice)),isEmpty);
      await ledger.flushPendingServerEdits(shop);
      expect(server.editCalls,1);
    }finally{ await db.close(); }
  });

  test('different server version fails closed and keeps queued correction', () async {
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final server=_PaymentServerFixture()..rejectConflict=true;
    try {
      const shop='safe-edit-3',invoice='invoice-3';
      final ledger=OfflineInvoicePaymentLedger(database:db,api:server);
      await ledger.queueServerPendingEdit(shop,invoice,'server-pending-payment',
        expectedRowVersion:4,amount:80,maximumAllowedCents:10000,
        methodId:'cash',methodName:'Cash',paymentDate:'2026-10-16');
      await ledger.flushPendingServerEdits(shop);
      expect((await ledger.pendingEditsForInvoice(shop,invoice)),hasLength(1));
      expect(server.amount,100);
    }finally{ await db.close(); }
  });
  test('legacy cached pending receipt edits offline with original identity', () async {
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final server=_PaymentServerFixture()
      ..version=1
      ..amount=174.80
      ..method='cash';
    try {
      const shop='legacy-payment-shop',invoice='barbara-invoice';
      final ledger=OfflineInvoicePaymentLedger(database:db,api:server);
      final snapshot=await server.documentDetailV4(shop,invoice);
      final oldReceipt=Map<String,dynamic>.from(
          (snapshot['payments'] as List).single as Map);
      oldReceipt.remove('row_version'); // Cached before v4 existed.
      final cached=<String,dynamic>{
        ...snapshot,'payments':[oldReceipt],
      };
      await ledger.queueServerPendingEdit(shop,invoice,
        'server-pending-payment',
        expectedRowVersion:null,
        originalAmountCents:17480,
        originalMethodId:'cash',
        originalEnteredAt:server.enteredAt,
        originalPaymentDate:null,
        amount:175.60,maximumAllowedCents:17560,
        methodId:'cash',methodName:'Cash',paymentDate:'2026-10-16');
      final pending=await ledger.pendingEditsForInvoice(shop,invoice);
      final preview=OfflineInvoicePaymentLedger.projectPendingEdits(
          cached,pending);
      expect((preview['payments'] as List).single['id'],
          'server-pending-payment');
      expect((preview['payments'] as List).single['amount'],175.60);
      expect(preview['_payment_reconciliation_required'],isNot(true));
      expect(server.editCalls,0); // Force Offline capture never calls network.
      // Synthetic server replay uses verified version 1 and same payment ID.
      await ledger.flushPendingServerEdits(shop);
      expect(server.editCalls,1);
      expect(server.version,2);
      expect(server.amount,175.60);
      expect((await ledger.pendingEditsForInvoice(shop,invoice)),isEmpty);
    }finally{await db.close();}
  });

  test('legacy cached receipt blocks changed server version without writing', () async {
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final server=_PaymentServerFixture()
      ..version=2
      ..amount=174.80
      ..method='cash';
    try {
      const shop='legacy-stale-shop',invoice='legacy-stale-invoice';
      final ledger=OfflineInvoicePaymentLedger(database:db,api:server);
      await ledger.queueServerPendingEdit(shop,invoice,
        'server-pending-payment',
        expectedRowVersion:null,
        originalAmountCents:17480,
        originalMethodId:'cash',
        originalEnteredAt:server.enteredAt,
        amount:175.60,maximumAllowedCents:17560,
        methodId:'cash',methodName:'Cash',paymentDate:'2026-10-16');
      await ledger.flushPendingServerEdits(shop);
      expect(server.editCalls,0);
      final pending=await ledger.pendingEditsForInvoice(shop,invoice);
      expect(pending,singleElement);
      expect(pending.single['_queue_state'],'conflict');
      final cached=await server.documentDetailV4(shop,invoice);
      final projected=OfflineInvoicePaymentLedger.projectPendingEdits(
          cached,pending);
      expect(projected['_payment_reconciliation_required'],true);
      expect((projected['payments'] as List).single['amount'],174.80);
    }finally{await db.close();}
  });

  test('tax outbox blocks pending-payment replay until tax acknowledged', () async {
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final server=_PaymentServerFixture()..amount=174.80..method='cash';
    try {
      const shop='tax-before-payment-shop',invoice='invoice-6349';
      final ledger=OfflineInvoicePaymentLedger(database:db,api:server);
      await ledger.queueServerPendingEdit(shop,invoice,
        'server-pending-payment',expectedRowVersion:4,
        amount:175.60,maximumAllowedCents:17560,
        methodId:'cash',methodName:'Cash',paymentDate:'2026-10-16');
      await db.customStatement(
        """INSERT INTO sync_outbox
           (business_id,entity_type,entity_id,operation,payload_json,
            state,attempt_count,created_at)
           VALUES (?,'invoice_tax_edit',?,'change_tax_rate','{}',
                   'pending',0,1)""",
        [shop,invoice]);
      await ledger.flushPendingServerEdits(shop);
      expect(server.editCalls,0);
      expect((await ledger.pendingEditsForInvoice(shop,invoice)).single
        ['_queue_state'],'pending');
      await db.customStatement(
        "DELETE FROM sync_outbox WHERE entity_type='invoice_tax_edit'");
      await ledger.flushPendingServerEdits(shop);
      expect(server.editCalls,1);
      expect(server.amount,175.60);
    }finally{await db.close();}
  });

  test('owner local remove discards only a never-submitted receipt', () async {
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    try {
      const shop='local-remove-shop',invoice='local-remove-invoice';
      final ledger=OfflineInvoicePaymentLedger(database:db);
      final id=await ledger.recordReceivedPayment(shop,invoice,
        amount:20,remainingBeforePaymentCents:2000,
        methodId:'cash',methodName:'Cash');
      expect((await ledger.pendingForInvoice(shop,invoice)),hasLength(1));
      await ledger.deleteNeverSubmittedPayment(shop,invoice,id);
      expect((await ledger.pendingForInvoice(shop,invoice)),isEmpty);
      final secondId=await ledger.recordReceivedPayment(shop,invoice,
        amount:20,remainingBeforePaymentCents:2000,
        methodId:'cash',methodName:'Cash');
      await db.customStatement(
        """UPDATE sync_outbox SET attempt_count=1
           WHERE business_id=? AND entity_type='invoice_payment_received'""",
        [shop]);
      await expectLater(ledger.deleteNeverSubmittedPayment(
          shop,invoice,secondId),throwsStateError);
      expect((await ledger.pendingForInvoice(shop,invoice)),hasLength(1));
    }finally{await db.close();}
  });

}
