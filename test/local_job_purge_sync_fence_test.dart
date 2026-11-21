import 'support/empty_retirement_gateway.dart';
import 'package:briskers_app/services/test_job_cleanup_gateway.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/job_sync_service.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_job_deletion_v3.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const business = '10000000-0000-4000-8000-000000000001';
const job = '10000000-0000-4000-8000-000000000002';
const otherJob = '10000000-0000-4000-8000-000000000004';
const doc = '10000000-0000-4000-8000-000000000003';

Map<String, dynamic> _bundle(String id) => {
  'job': {
    'id': id,
    'job_number': id == job ? 'TEST-7001' : 'TEST-7002',
    'title': 'A stale server job snapshot',
    'status': 'open',
    'assignments': <dynamic>[],
    'visits': <dynamic>[],
    'capabilities': {'manage_job': true},
  },
  'findings': <dynamic>[],
};

class _EmptyCleanupGateway extends TestJobCleanupGateway {
  const _EmptyCleanupGateway();
  @override
  Future<Map<String,dynamic>> tombstones(String businessId) async => {
    'schema_version':1,'business_id':businessId,
    'deleted_job_ids':<String>[],'deleted_document_ids':<String>[]};
}

class _StaleServerApi extends BriskersApi {
  @override
  Future<Map<String, dynamic>> syncPullJobsBootstrap(
    String businessId, {String? afterJobId, int limit = 25}
  ) async => {
    'mode': 'bootstrap',
    'bootstrap_cursor': 20,
    'next_job_id': otherJob,
    'has_more': false,
    'bundles': [_bundle(job), _bundle(otherJob)],
  };

  @override
  Future<Map<String, dynamic>> syncPullJobs(
    String businessId, {int? afterCursor, int limit = 250}
  ) async {
    expect(afterCursor, 20);
    return {
      'mode': 'incremental',
      'next_cursor': 21,
      'has_more': false,
      'bundles': [_bundle(job), _bundle(otherJob)],
      'revoked_job_ids': <String>[],
    };
  }
}

Future<void> _markDeleted(BriskersLocalDatabase db,
    String kind, String id) async {
  await db.customStatement(
    'INSERT INTO local_offline_job_purge_entities '
    '(business_id,job_id,operation_id,entity_kind,entity_id) '
    'VALUES (?,?,?,?,?)',
    [business, job, 'synthetic-delete-operation', kind, id],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bootstrap and subsequent incremental sync never resurrect a purged job',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await LocalJobDeletionV3.ensureSchema(db);
      await _markDeleted(db, 'job', job);
      final sync = JobSyncService(api: _StaleServerApi(), database: db,retirementGateway:const EmptyRetirementGateway(),cleanupGateway:const _EmptyCleanupGateway());
      await sync.pull(business);
      var rows = await db.customSelect(
        'SELECT id FROM local_jobs WHERE business_id=? ORDER BY id',
        variables: [
          const Variable<String>(business),
        ],
      ).get();
      expect(rows.map((row) => row.read<String>('id')), [otherJob]);
      await sync.pull(business);
      rows = await db.customSelect(
        'SELECT id FROM local_jobs WHERE business_id=? ORDER BY id',
        variables: [const Variable<String>(business)],
      ).get();
      expect(rows.map((row) => row.read<String>('id')), [otherJob]);
      expect(await LocalJobDeletionV3.blockedJobIds(db, business), contains(job));
    } finally {
      await db.close();
    }
  });

  test('both document refresh paths exclude purged docs and purged parents',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await LocalJobDeletionV3.ensureSchema(db);
      await _markDeleted(db, 'job', job);
      await _markDeleted(db, 'invoice', doc);
      const unknownDoc = '10000000-0000-4000-8000-000000000008';
      const safeDoc = '10000000-0000-4000-8000-000000000009';
      final documents = LocalDocumentRepository(database: db);
      await documents.replaceFromServer(business, [
        {'id': doc, 'job_id': job, 'kind': 'invoice', 'document_number': 'TEST-8001'},
        {'id': unknownDoc, 'job_id': job, 'kind': 'invoice', 'document_number': 'TEST-8008'},
        {'id': safeDoc, 'job_id': otherJob, 'kind': 'invoice', 'document_number': 'TEST-8009'},
      ]);
      var rows = await db.customSelect(
        'SELECT id FROM local_documents WHERE business_id=? ORDER BY id',
        variables: [const Variable<String>(business)],
      ).get();
      expect(rows.map((row) => row.read<String>('id')), [safeDoc]);

      await documents.upsertFromServer(business, [
        {'id': doc, 'job_id': job, 'kind': 'invoice'},
        {'id': unknownDoc, 'job_id': job, 'kind': 'invoice'},
        {'id': safeDoc, 'job_id': otherJob, 'kind': 'invoice', 'document_number': 'UPDATED'},
      ]);
      rows = await db.customSelect(
        'SELECT id,document_number FROM local_documents WHERE business_id=?',
        variables: [const Variable<String>(business)],
      ).get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('id'), safeDoc);
      expect(rows.single.read<String>('document_number'), 'UPDATED');
    } finally {
      await db.close();
    }
  });

  test('same identity on unrelated business is not blocked by this tenant fence',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await LocalJobDeletionV3.ensureSchema(db);
      await _markDeleted(db, 'invoice', doc);
      final docs = LocalDocumentRepository(database: db);
      await docs.upsertFromServer('different-business', [
        {'id': doc, 'job_id': otherJob, 'kind': 'invoice', 'document_number': '100'},
      ]);
      final rows = await db.customSelect(
        "SELECT COUNT(*) AS n FROM local_documents WHERE business_id='different-business'",
      ).getSingle();
      expect(rows.read<int>('n'), 1);
    } finally {
      await db.close();
    }
  });
}
