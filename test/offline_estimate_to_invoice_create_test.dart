import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline estimate conversion retains one job and survives local restart', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = const LocalDocumentDetailCache();
    final service = OfflineDocumentDraftService(
      database: db,
      cache: cache,
      documents: LocalDocumentRepository(database: db),
    );
    final estimateId = await service.createStandaloneEstimate('shop',
      customerId: 'customer-id', customerName: 'Customer');
    await service.addLine('shop', estimateId,
      name: 'Oil change', quantity: 1, unitPrice: 100, taxRate: 0,
      lineKind: 'labor');
    await service.addLine('shop', estimateId,
      name: 'Oil filter', quantity: 1, unitPrice: 25, taxRate: 0,
      lineKind: 'part');

    final invoiceId = await service.convertEstimateOffline('shop', estimateId);
    expect(invoiceId, startsWith('local-invoice-'));
    final invoice = await cache.load('shop', invoiceId);
    expect(invoice?['kind'], 'invoice');
    expect(invoice?['job_id'], startsWith('local-conversion-job-'));
    expect(invoice?['total_amount'], 125);
    expect(invoice?['lines'], hasLength(2));
    expect(invoice?['converted_from_estimate_id'], estimateId);
    final source = await cache.load('shop', estimateId);
    expect(source?['converted'], isTrue);
    expect(source?['converted_invoice_id'], invoiceId);

    await service.addLine('shop', invoiceId,
      name: 'Additional labor', quantity: 1, unitPrice: 50,
      taxRate: 0, lineKind: 'labor');
    final edited = await cache.load('shop', invoiceId);
    expect(edited?['lines'], hasLength(3));
    expect(edited?['total_amount'], 175);
    await service.updateLine('shop', invoiceId,
      (edited?['lines'] as List).last['id'].toString(),
      name: 'Additional labor', quantity: 2, unitPrice: 50,
      taxRate: 0, lineKind: 'labor');
    final afterEdit = await cache.load('shop', invoiceId);
    expect(afterEdit?['total_amount'], 225);
    await service.savePendingInvoiceWarranty('shop', invoiceId, {
      'extended_warranty': true,
      'warranty_company_name': 'Example Warranty',
      'authorization_number': 'AUTH-123',
      'claim_number': 'CLAIM-8',
      'approved_amount': 125,
      'surcharge_rate': 0.03,
    });
    final warrantyInvoice = await cache.load('shop', invoiceId);
    final warranty = warrantyInvoice?['offline_warranty_detail'] as Map;
    expect(warranty['extended_warranty'], isTrue);
    expect(warranty['authorization_number'], 'AUTH-123');
    expect(warrantyInvoice?['total_amount'], 225);
    await service.savePendingInvoiceWarranty('shop', invoiceId, {
      ...Map<String, dynamic>.from(warranty),
      'extended_warranty': false,
    });
    final disabled = await cache.load('shop', invoiceId);
    expect((disabled?['offline_warranty_detail'] as Map)['extended_warranty'],
      isFalse);

    final outbox = await db.customSelect(
      "SELECT operation,payload_json FROM sync_outbox "
      "WHERE business_id='shop' AND operation='convert_estimate'").get();
    expect(outbox, hasLength(1));
    final localJobs = await db.customSelect(
      "SELECT id FROM local_jobs WHERE business_id='shop'").get();
    expect(localJobs, hasLength(1));
    expect(localJobs.single.read<String>('id'), invoice?['job_id']);
    final documents = await LocalDocumentRepository(database:db)
      .listByKind('shop', kind:'invoice');
    expect(documents, hasLength(1));
    expect(documents.single['id'], invoiceId);
    await db.close();
  });
}
