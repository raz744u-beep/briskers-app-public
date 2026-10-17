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
}
