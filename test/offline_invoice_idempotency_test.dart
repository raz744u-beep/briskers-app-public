import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_repository.dart';

class _InterruptedSyncApi extends BriskersApi {
  final List<String> operationIds = [];
  var responseAttempt = 0;

  @override
  Future<String> syncOfflineQuickInvoice(
    String businessId, {
    required String customerId,
    String? vehicleId,
    required String operationId,
    required String documentDate,
    required List<Map<String, dynamic>> lines,
    String? memo,
  }) async {
    operationIds.add(operationId);
    expect(lines.single['name'], 'Water pump');
    return '00000000-0000-4000-8000-000000006332';
  }

  @override
  Future<Map<String,dynamic>> documentDetail(
      String businessId, String documentId) async {
    responseAttempt++;
    if (responseAttempt == 1) {
      throw StateError('Simulated disconnect after server commit');
    }
    return <String,dynamic>{
      'id':documentId,
      'kind':'invoice',
      'document_number':'6332',
      'customer_id':'customer-one',
      'document_date':'2026-10-09',
      'status':'issued',
      'row_version':1,
      'net_amount':100,
      'tax_amount':9.75,
      'total_amount':109.75,
      'origin':'native',
      'legacy_read_only':false,
      'closed_at':null,
      'lines':[{'id':'server-line','name':'Water pump','net_amount':100,'tax_amount':9.75}],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline invoice stays queued after interrupted server response, no double invoice',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _InterruptedSyncApi();
    final cache = const LocalDocumentDetailCache();
    final drafts = OfflineDocumentDraftService(
      database: db, api: api, cache: cache,
      documents: LocalDocumentRepository(database:db),
    );
    final id = await drafts.createQuickInvoice(
      'sandbox', customerId:'customer-one', customerName:'Customer One',
    );
    await drafts.addLine('sandbox', id,
        name:'Water pump', quantity:1, unitPrice:100,
        taxRate:0.0975, lineKind:'item');
    await drafts.flush('sandbox');
    final stillQueued = await db.customSelect(
      "select id from sync_outbox where business_id='sandbox' and state='pending'"
    ).get();
    expect(stillQueued, hasLength(1));
    expect((await cache.load('sandbox',id))?['_server_document_id'], isNull);

    await drafts.flush('sandbox');
    expect(api.operationIds, hasLength(2));
    expect(api.operationIds.first, api.operationIds.last);

    final remote = await cache.load('sandbox',id);
    expect(remote?['_server_document_id'],
        '00000000-0000-4000-8000-000000006332');
    final remains = await db.customSelect(
      "select id from sync_outbox where business_id='sandbox'"
    ).get();
    expect(remains, isEmpty);
    final stored = await LocalDocumentRepository(database:db)
        .listByKind('sandbox',kind:'invoice');
    expect(stored, hasLength(1));
    expect(stored.single['document_number'], '6332');
    await db.close();
  });
}
