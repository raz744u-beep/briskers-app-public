import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_repository.dart';

class _StandaloneApi extends BriskersApi {
  final List<String> operationIds=[];
  var detailAttempts=0;
  @override
  Future<String> syncOfflineStandaloneEstimate(
    String businessId, {
    required String customerId,
    String? vehicleId,
    required String operationId,
    required String documentDate,
    required List<Map<String,dynamic>> lines,
    String? memo,
  }) async {
    operationIds.add(operationId);
    expect(customerId,'customer-id');
    expect(lines,hasLength(1));
    expect(lines.single['name'],'Labor');
    expect(memo,'Price subject to inspection');
    return '00000000-0000-4000-8000-00000000e888';
  }
  @override
  Future<Map<String,dynamic>> documentDetail(
      String businessId,String documentId) async {
    detailAttempts++;
    if (detailAttempts==1) throw StateError('Simulated dropped response');
    return {
      'id':documentId,'kind':'estimate','document_number':null,
      'job_id':null,'status':'draft','customer_id':'customer-id',
      'customer_name':'Test Customer','document_date':'2026-10-10',
      'row_version':2,'net_amount':220,'tax_amount':0,'total_amount':220,
      'origin':'native','legacy_read_only':false,
      'lines':[{'id':'server-line','name':'Labor','quantity':4.4,
        'unit_price':50,'line_kind':'labor'}],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('standalone offline estimate uses no Job and idempotent upload',() async {
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final api=_StandaloneApi();
    final cache=const LocalDocumentDetailCache();
    final drafts=OfflineDocumentDraftService(
      database:db,api:api,cache:cache,
      documents:LocalDocumentRepository(database:db),
    );
    final localId=await drafts.createStandaloneEstimate(
      'shop',customerId:'customer-id',customerName:'Test Customer',
    );
    expect(localId,startsWith('local-estimate-'));
    expect((await cache.load('shop',localId))?['job_id'],isNull);
    final jobs=await db.customSelect(
      "SELECT id FROM local_jobs WHERE business_id='shop'",
    ).get();
    expect(jobs,isEmpty);
    await drafts.addLine('shop',localId,name:'Labor',lineKind:'labor',
      quantity:4.4,unitPrice:50,taxRate:0);
    await drafts.saveMemo('shop',localId,'Price subject to inspection');
    await drafts.flush('shop');
    final retry=await db.customSelect(
      "SELECT state FROM sync_outbox WHERE business_id='shop'",
    ).get();
    expect(retry,hasLength(1));
    await drafts.flush('shop');
    expect(api.operationIds,hasLength(2));
    expect(api.operationIds.first,api.operationIds.last);
    final details=await cache.load('shop',localId);
    expect(details?['_server_document_id'],
      '00000000-0000-4000-8000-00000000e888');
    final documents=await LocalDocumentRepository(database:db)
      .listByKind('shop',kind:'estimate');
    expect(documents,hasLength(1));
    expect(documents.single['job_id'],isNull);
    expect((await db.customSelect(
      "SELECT id FROM local_jobs WHERE business_id='shop'",
    ).get()),isEmpty);
    await db.close();
  });
}
