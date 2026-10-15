import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';

const _line = <String, dynamic>{
  'id': 'line', 'name': 'Labor', 'line_kind': 'labor',
  'quantity': 1, 'unit_price': 100, 'tax_rate': 0,
};

class _ConvertedInvoiceApi extends BriskersApi {
  @override
  Future<Map<String, dynamic>> documentDetail(
    String businessId, String documentId,
  ) async {
    if (documentId == 'estimate') {
      // Simulate a server-committed conversion whose response was lost.
      return {'id': 'estimate', 'converted': true,
        'converted_invoice_id': 'server-invoice'};
    }
    return {
      'id': 'server-invoice', 'kind': 'invoice', 'document_number': '501',
      'job_id': 'server-job', 'job_number': 'J-501',
      'customer_id': 'customer', 'status': 'issued', 'row_version': 1,
      'total_amount': 100, 'lines': [_line],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('converted offline invoice remaps its Job and payment operation together',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final documents = LocalDocumentRepository(database: db);
    final jobs = LocalJobRepository(database: db);
    final ledger = OfflineInvoicePaymentLedger(database: db);
    final drafts = OfflineDocumentDraftService(database: db,
        api: _ConvertedInvoiceApi(), cache: cache, documents: documents);
    try {
      const estimate = <String, dynamic>{
        'id': 'estimate', 'kind': 'estimate', 'customer_id': 'customer',
        'customer_name': 'Customer', 'title': 'Offline repair',
        'total_amount': 100, 'document_date': '2026-10-12',
        'lines': [_line],
      };
      await documents.upsertFromServer('shop', [estimate]);
      await cache.save('shop', 'estimate', estimate);
      final invoiceId = await drafts.convertEstimateOffline('shop', 'estimate');
      final initial = await cache.load('shop', invoiceId);
      expect(initial?['job_number'], startsWith('TEMP-'));
      expect((await jobs.listJobs('shop')).single['job_number'],
          initial?['job_number']);
      final paymentOperation = await ledger.recordReceivedPayment(
        'shop', invoiceId, amount: 50, remainingBeforePaymentCents: 10000,
        methodId: 'card', methodName: 'Card',
      );

      await drafts.flush('shop');

      final result = await cache.load('shop', invoiceId);
      expect(result?['_server_document_id'], 'server-invoice');
      expect(result?['job_number'], 'J-501');
      final jobRows = await jobs.listJobs('shop');
      expect(jobRows, hasLength(1));
      expect(jobRows.single['id'], 'server-job');
      expect(jobRows.single['job_number'], 'J-501');
      expect(jobRows.single['title'], 'Offline repair');
      expect(await ledger.pendingForInvoice('shop', invoiceId), isEmpty);
      final receipts = await ledger.pendingForInvoice('shop', 'server-invoice');
      expect(receipts, hasLength(1));
      expect(receipts.single['operation_id'], paymentOperation);
      expect(receipts.single['invoice_id'], 'server-invoice');
      expect(receipts.single['amount_cents'], 5000);

      await drafts.flush('shop');
      expect(await jobs.jobCount('shop'), 1);
      expect(await ledger.pendingForInvoice('shop', 'server-invoice'),
          hasLength(1));
    } finally {
      await db.close();
    }
  });
}

