import 'support/empty_retirement_gateway.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/job_sync_service.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:briskers_app/services/test_job_cleanup_gateway.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cleanup extends TestJobCleanupGateway {
  @override
  Future<Map<String, dynamic>> tombstones(String businessId) async => {
    'schema_version': 1,
    'business_id': businessId,
    'deleted_job_ids': <String>[],
    'deleted_document_ids': <String>[],
  };
}

class _Api extends BriskersApi {
  String status = 'open';
  String? completedAt;
  int version = 1;

  Map<String, dynamic> bundle() => {
    'job': {
      'id': 'synthetic-j6',
      'job_number': 'J-6',
      'title': 'Synthetic completion test',
      'status': status,
      'status_name': status,
      'completed_at': completedAt,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-10-14T00:00:00Z',
      'row_version': version,
      'assignments': <dynamic>[],
      'visits': <dynamic>[],
      'capabilities': {'manage_job': true},
    },
    'pre_inspection': null,
    'findings': <dynamic>[],
  };

  @override
  Future<Map<String, dynamic>> syncPullJobsBootstrap(
    String businessId, {
    String? afterJobId,
    int limit = 25,
  }) async => {
    'mode': 'bootstrap',
    'bootstrap_cursor': version,
    'next_job_id': 'synthetic-j6',
    'has_more': false,
    'revoked_job_ids': <dynamic>[],
    'bundles': [bundle()],
  };

  @override
  Future<Map<String, dynamic>> syncPullJobs(
    String businessId, {
    int? afterCursor,
    int limit = 250,
  }) async => {
    'mode': 'incremental',
    'next_cursor': version,
    'has_more': false,
    'revoked_job_ids': <dynamic>[],
    'bundles': [bundle()],
  };
}

void main() {
  test(
    'pull preserves queued completion/reopen and accepts acknowledged server dates',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final api = _Api();
      final sync = JobSyncService(retirementGateway: const EmptyRetirementGateway(),
        api: api,
        database: db,
        cleanupGateway: _Cleanup(),
      );
      final admin = OfflineJobAdminService(database: db);
      final jobs = LocalJobRepository(database: db);
      await sync.pull('00000000-0000-4000-8000-000000000001');
      await admin.queueStatus(
        '00000000-0000-4000-8000-000000000001',
        'synthetic-j6',
        code: 'completed',
        name: 'Completed',
      );
      var row = (await jobs.listJobs('00000000-0000-4000-8000-000000000001', status: 'completed')).single;
      final localCompletion = row['completed_at'];
      expect(localCompletion, isNotNull);

      api.version = 2;
      await sync.pull('00000000-0000-4000-8000-000000000001');
      row = (await jobs.listJobs('00000000-0000-4000-8000-000000000001', status: 'completed')).single;
      expect(row['completed_at'], localCompletion);
      var saved = await db
          .customSelect("SELECT * FROM local_jobs WHERE id='synthetic-j6'")
          .getSingle();
      expect(saved.read<String>('sync_state'), 'pending');
      expect(saved.read<int>('row_version'), 2);
      expect(
        await db.customSelect('SELECT * FROM sync_outbox').get(),
        hasLength(1),
      );

      // Once the operation has been acknowledged, the authoritative server date
      // replaces the local projection. No sync payload or RPC is changed.
      await db.customStatement(
        "DELETE FROM sync_outbox WHERE business_id='00000000-0000-4000-8000-000000000001'",
      );
      api.status = 'completed';
      api.completedAt = '2026-10-14T14:00:00Z';
      api.version = 3;
      await sync.pull('00000000-0000-4000-8000-000000000001');
      row = (await jobs.listJobs('00000000-0000-4000-8000-000000000001', status: 'completed')).single;
      expect(
        row['completed_at'],
        DateTime.parse(api.completedAt!).toIso8601String(),
      );
      saved = await db
          .customSelect("SELECT * FROM local_jobs WHERE id='synthetic-j6'")
          .getSingle();
      expect(saved.read<String>('sync_state'), 'synced');

      await admin.queueStatus(
        '00000000-0000-4000-8000-000000000001',
        'synthetic-j6',
        code: 'open',
        name: 'Open',
      );
      api.version = 4;
      await sync.pull('00000000-0000-4000-8000-000000000001');
      row = (await jobs.listJobs('00000000-0000-4000-8000-000000000001')).single;
      expect(row['status'], 'open');
      expect(row['completed_at'], isNull);
      expect(await jobs.listJobs('00000000-0000-4000-8000-000000000001', status: 'completed'), isEmpty);

      // A similarly named queued operation in another business cannot retain a
      // local status in this business after its own operation is acknowledged.
      await db.customStatement(
        "UPDATE sync_outbox SET business_id='other-00000000-0000-4000-8000-000000000001'",
      );
      api.version = 5;
      await sync.pull('00000000-0000-4000-8000-000000000001');
      row = (await jobs.listJobs('00000000-0000-4000-8000-000000000001')).single;
      expect(row['status'], 'completed');
      expect(
        row['completed_at'],
        DateTime.parse(api.completedAt!).toIso8601String(),
      );
    },
  );
}

