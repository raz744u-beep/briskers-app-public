import 'support/empty_retirement_gateway.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/document_index_sync_service.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/test_job_cleanup_gateway.dart';

class _DocumentsApi extends BriskersApi {
  int reads = 0;
  @override
  Future<List<Map<String, dynamic>>> documents(String businessId, {required String kind}) async {
    reads++;
    return [];
  }
}

class _CleanupFeed extends TestJobCleanupGateway {
  _CleanupFeed(this.api);
  final _DocumentsApi api;
  @override
  Future<Map<String, dynamic>> tombstones(String businessId) async {
    expect(api.reads, 2, reason: 'classify deletions after document responses');
    return {'schema_version': 1, 'business_id': businessId,
      'deleted_job_ids': ['job'], 'deleted_document_ids': ['doc']};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late DocumentIndexSyncService sync;
  late LocalDocumentDetailCache cache;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    cache = LocalDocumentDetailCache(database:db);
    final api = _DocumentsApi();
    sync = DocumentIndexSyncService(retirementGateway: const EmptyRetirementGateway(), api: api, database: db, cleanupGateway: _CleanupFeed(api));
    await db.customStatement("INSERT INTO local_documents "
      "(id,business_id,kind) VALUES ('doc','00000000-0000-4000-8000-000000000001','estimate')");
  });
  tearDown(() => db.close());

  test('interrupted cache-only edit survives cleanup pull with synced index', () async {
    await cache.save('00000000-0000-4000-8000-000000000001', 'doc', {'id': 'doc', 'memo': 'Unsent note', 'sync_state': 'pending'});
    await expectLater(sync.pull('00000000-0000-4000-8000-000000000001'), throwsStateError);
    expect((await cache.load('00000000-0000-4000-8000-000000000001', 'doc'))?['memo'], 'Unsent note');
    expect((await db.customSelect('SELECT * FROM local_documents').get()).length, 1);
  });

  test('clean acknowledged tombstones remove index and matching snapshot', () async {
    await cache.save('00000000-0000-4000-8000-000000000001', 'doc', {'id': 'doc', 'sync_state': 'synced'});
    await sync.pull('00000000-0000-4000-8000-000000000001');
    expect(await cache.load('00000000-0000-4000-8000-000000000001', 'doc'), isNull);
    expect(await db.customSelect('SELECT * FROM local_documents').get(), isEmpty);
  });

  test('queued payment preserves deleted document until explicit reconciliation', () async {
    await db.customStatement("INSERT INTO sync_outbox "
      "(business_id,entity_type,entity_id,operation,payload_json) "
      "VALUES ('00000000-0000-4000-8000-000000000001','invoice_payment_received','doc','create','{}')");
    await expectLater(sync.pull('00000000-0000-4000-8000-000000000001'), throwsStateError);
    expect((await db.customSelect('SELECT * FROM local_documents').get()).length, 1);
    expect((await db.customSelect('SELECT * FROM sync_outbox').get()).length, 1);
  });
}

