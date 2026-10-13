import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/job_sync_service.dart';
import 'package:briskers_app/services/local_job_quarantine.dart';
import 'package:briskers_app/services/test_job_cleanup_gateway.dart';


class _CleanupGateway extends TestJobCleanupGateway {
  bool deleted = false;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> tombstones(String businessId) async {
    if (fail) throw StateError('Deletion feed unavailable');
    return {'schema_version': 1, 'business_id': businessId,
      'deleted_job_ids': deleted ? ['job-1'] : <String>[],
      'deleted_document_ids': <String>[]};
  }
}

class _FakeBriskersApi extends BriskersApi {
  _FakeBriskersApi();

  var calls = 0;
  void Function()? onPull;
  List<String> revokedIds = ['job-1'];
  String mode = 'incremental';
  List<Map<String, dynamic>> bundles = [];
  Future<void> Function()? beforePullReturns;

  @override
  Future<Map<String, dynamic>> syncPullJobsBootstrap(
    String businessId, {
    String? afterJobId,
    int limit = 25,
  }) async {
    expect(afterJobId, isNull);
    return {
      'mode': 'bootstrap',
      'bootstrap_cursor': 10,
      'next_job_id': 'job-1',
      'has_more': false,
      'revoked_job_ids': <dynamic>[],
      'bundles': [
        {
          'job': {
            'id': 'job-1',
            'job_number': '1001',
            'title': 'Brake repair',
            'requested_work': 'Brake noise',
            'status': 'open',
            'status_name': 'Open',
            'status_color': '#2563EB',
            'status_icon': 'build',
            'customer_id': 'customer-1',
            'customer_name': 'Test Customer',
            'vehicle_id': 'vehicle-1',
            'vehicle': '2020 BMW X5',
            'vehicle_vin': 'TESTVIN',
            'vehicle_plate': 'ABC123',
            'planned_hours': 2,
            'odometer_in': 50000,
            'is_unassigned': true,
            'assignments': <dynamic>[],
            'visits': <dynamic>[],
            'capabilities': {
              'manage_job': false,
              'request_job': true,
            },
            'row_version': 3,
            'updated_at': '2026-09-30T15:00:00Z',
            'created_at': '2026-09-30T14:00:00Z',
          },
          'pre_inspection': null,
          'findings': <dynamic>[],
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> syncPullJobs(
    String businessId, {
    int? afterCursor,
    int limit = 250,
  }) async {
    calls++;
    onPull?.call();
    await beforePullReturns?.call();
    expect(afterCursor, 10);
    return {
      'mode': mode,
      'next_cursor': 11,
      'has_more': false,
      'bundles': bundles,
      'revoked_job_ids': revokedIds,
    };
  }

}

class _PagedApi extends BriskersApi {
  final requestedAfterIds = <String?>[];
  Future<void> Function(String?)? beforePage;

  @override
  Future<Map<String, dynamic>> syncPullJobsBootstrap(
    String businessId, {
    String? afterJobId,
    int limit = 25,
  }) async {
    requestedAfterIds.add(afterJobId);
    await beforePage?.call(afterJobId);
    final second = afterJobId != null;
    return {
      'mode': 'bootstrap',
      'bootstrap_cursor': second ? 21 : 20,
      'next_job_id': second ? 'job-2' : 'job-1',
      'has_more': !second,
      'bundles': [
        {
          'job': {
            'id': second ? 'job-2' : 'job-1',
            'job_number': second ? '1002' : '1001',
            'title': 'Service',
            'status': 'completed',
            'customer_id': 'customer-1',
            'vehicle_id': 'vehicle-1',
            'assignments': <dynamic>[],
            'visits': <dynamic>[],
            'capabilities': {'manage_job': true},
          },
          'findings': <dynamic>[],
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> syncPullJobs(
    String businessId, {
    int? afterCursor,
    int limit = 250,
  }) async {
    expect(afterCursor, 20);
    return {
      'mode': 'incremental',
      'next_cursor': 21,
      'has_more': false,
      'bundles': <dynamic>[],
      'revoked_job_ids': <dynamic>[],
    };
  }
}

void main() {
  test('paged bootstrap keeps all jobs and original snapshot cursor',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _PagedApi();
    final sync = JobSyncService(api: api, database: db, cleanupGateway: _CleanupGateway());
    await sync.pull('business-1');
    expect(api.requestedAfterIds, [null, 'job-1']);
    final rows = await db.customSelect(
      'SELECT id FROM local_jobs WHERE business_id=? ORDER BY id',
      variables: [const Variable<String>('business-1')],
    ).get();
    expect(rows.map((r) => r.read<String>('id')).toList(),
        ['job-1', 'job-2']);
    final state = await db.customSelect(
      "SELECT last_server_cursor,bootstrapped FROM local_sync_states "
      "WHERE business_id='business-1' AND scope='jobs'",
    ).getSingle();
    expect(state.read<int>('last_server_cursor'), 20);
    expect(state.read<int>('bootstrapped'), 1);
    await sync.pull('business-1');
    await db.close();
  });

  test('paged reset never revokes from first-page omissions', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _PagedApi();
    final sync = JobSyncService(api: api, database: db, cleanupGateway: _CleanupGateway());
    try {
      await db.customStatement("INSERT INTO local_jobs "
        "(id,business_id,access_scope,title,status) "
        "VALUES ('job-2','business-1','full','On next page','open'),"
        "('omitted','business-1','full','No longer authorized','open')");
      api.beforePage = (afterId) async {
        if (afterId != null) {
          final ids = (await db.customSelect('SELECT id FROM local_jobs').get())
              .map((row) => row.read<String>('id')).toSet();
          expect(ids, containsAll(['job-2', 'omitted']));
        }
      };
      await sync.pull('business-1');
      final ids = (await db.customSelect('SELECT id FROM local_jobs').get())
          .map((row) => row.read<String>('id')).toSet();
      expect(ids, {'job-1', 'job-2'});
    } finally { await db.close(); }
  });

  test('newly synced Job and pending media created during paging are not revoked', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _PagedApi();
    final sync = JobSyncService(api: api, database: db, cleanupGateway: _CleanupGateway());
    try {
      api.beforePage = (afterId) async {
        if (afterId == null) return;
        await db.customStatement("INSERT INTO local_jobs "
          "(id,business_id,access_scope,title,status,row_version,server_updated_at) "
          "VALUES ('new-before-first-key','business-1','full','Newly synced','open',1,123)");
        await db.customStatement("INSERT INTO local_pre_inspections "
          "(id,business_id,job_id,sync_state) "
          "VALUES ('new-inspection','business-1','new-before-first-key','pending')");
        await db.customStatement("INSERT INTO local_pre_inspection_photos "
          "(id,business_id,inspection_id,attachment_id,local_file_path,upload_state) "
          "VALUES ('new-photo','business-1','new-inspection','new-photo','/keep/new.jpg','pending')");
      };
      await expectLater(sync.pull('business-1'), throwsStateError);
      expect((await db.customSelect("SELECT * FROM local_jobs WHERE id='new-before-first-key'").get()).length, 1);
      expect((await db.customSelect('SELECT * FROM local_pre_inspection_photos').get()).length, 1);
    } finally { await db.close(); }
  });

  test('explicit cleanup archives pending work and media without replay', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final gateway = _CleanupGateway();
    final sync = JobSyncService(api: _FakeBriskersApi(), database: db, cleanupGateway: gateway);
    try {
      await sync.pull('business-1');
      gateway.deleted = true;
      await db.customStatement("INSERT INTO local_pre_inspections "
        "(id,business_id,job_id,sync_state) VALUES ('inspection','business-1','job-1','pending')");
      await db.customStatement("INSERT INTO local_pre_inspection_photos "
        "(id,business_id,inspection_id,attachment_id,local_file_path,upload_state) "
        "VALUES ('photo','business-1','inspection','photo','/recovery/keep.jpg','pending')");
      await db.customStatement("INSERT INTO sync_outbox "
        "(business_id,entity_type,entity_id,operation,payload_json) "
        "VALUES ('business-1','preinspection','inspection','upsert',?)",
        [jsonEncode({'nested': {'job_id': 'job-1'}})]);
      await sync.pull('business-1');
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
      expect(await db.customSelect('SELECT * FROM local_jobs').get(), isEmpty);
      expect(await db.customSelect('SELECT * FROM local_pre_inspection_photos').get(), isEmpty);
      final archive = await db.customSelect('SELECT table_name,row_json FROM local_job_recovery_rows').get();
      expect(archive.map((row) => row.read<String>('table_name')), containsAll(['sync_outbox', 'local_pre_inspection_photos']));
      expect(archive.any((row) => row.read<String>('row_json').contains('/recovery/keep.jpg')), isTrue);
      final state = await db.customSelect('SELECT state FROM local_job_quarantines').getSingle();
      expect(state.read<String>('state'), 'cleanup_deleted');
    } finally { await db.close(); }
  });

  test('unknown cleanup feed hides revoked IDs, preserves recovery and keeps cursor', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final gateway = _CleanupGateway();
    final sync = JobSyncService(api: _FakeBriskersApi(), database: db,
      cleanupGateway: gateway);
    try {
      await sync.pull('business-1');
      gateway.fail = true;
      await expectLater(sync.pull('business-1'), throwsStateError);
      expect(await db.customSelect('SELECT * FROM local_jobs').get(), isEmpty);
      expect(await LocalJobQuarantine.isJobBlocked(db, 'business-1', 'job-1'), isTrue);
      expect(await LocalJobQuarantine.hasRecovery(db, 'business-1'), isTrue);
      final state = await db.customSelect("SELECT last_server_cursor FROM local_sync_states WHERE scope='jobs'").getSingle();
      expect(state.read<int>('last_server_cursor'), 10);
      gateway.fail = false;
      await sync.pull('business-1');
      expect(await LocalJobQuarantine.unclassifiedJobIds(db, 'business-1'), isEmpty);
      expect(await LocalJobQuarantine.isJobBlocked(db, 'business-1', 'job-1'), isTrue);
    } finally { await db.close(); }
  });

  test('cleanup committed during pull is classified by the later tombstone read', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final gateway = _CleanupGateway();
    final api = _FakeBriskersApi()..onPull = () => gateway.deleted = true;
    final sync = JobSyncService(api: api, database: db, cleanupGateway: gateway);
    try {
      await sync.pull('business-1');
      await db.customStatement("UPDATE local_jobs SET sync_state='pending'");
      await sync.pull('business-1');
      expect(await db.customSelect('SELECT * FROM local_jobs').get(), isEmpty);
      expect(await LocalJobQuarantine.hasRecovery(db, 'business-1'), isTrue);
    } finally { await db.close(); }
  });

  test('permission revocation commits even when another cleanup needs recovery', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final gateway = _CleanupGateway();
    final api = _FakeBriskersApi()..revokedIds = ['job-1', 'permission-revoked'];
    final sync = JobSyncService(api: api, database: db, cleanupGateway: gateway);
    try {
      await sync.pull('business-1');
      gateway.deleted = true;
      await db.customStatement("INSERT INTO local_jobs "
        "(id,business_id,access_scope,title,status) "
        "VALUES ('permission-revoked','business-1','full','Restricted','open')");
      await db.customStatement("UPDATE local_jobs SET sync_state='pending' WHERE id='job-1'");
      await sync.pull('business-1');
      expect(await db.customSelect('SELECT id FROM local_jobs').get(), isEmpty);
      final states = await db.customSelect('SELECT state FROM local_job_quarantines ORDER BY job_id').get();
      expect(states.map((row) => row.read<String>('state')), ['cleanup_deleted', 'permission_revoked']);
    } finally { await db.close(); }
  });

  test('cleanup never purges other Jobs findings or photos on the same vehicle', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final gateway = _CleanupGateway();
    final sync = JobSyncService(api: _FakeBriskersApi(), database: db,
      cleanupGateway: gateway);
    try {
      await sync.pull('business-1');
      gateway.deleted = true;
      await db.customStatement("INSERT INTO local_jobs (id,business_id,access_scope,title,status,vehicle_id) VALUES ('other-job','business-1','full','Still authorized','open','vehicle-1')");
      await db.customStatement("INSERT INTO local_findings "
        "(id,business_id,vehicle_id,found_job_id,body,status,sync_state) "
        "VALUES ('other-finding','business-1','vehicle-1','other-job','Keep','open','pending')");
      await db.customStatement("INSERT INTO local_finding_photos "
        "(id,business_id,finding_id,attachment_id,local_file_path,upload_state) "
        "VALUES ('other-photo','business-1','other-finding','other-photo','/keep/photo.jpg','pending')");
      await db.customStatement("INSERT INTO sync_outbox "
        "(business_id,entity_type,entity_id,operation,payload_json) "
        "VALUES ('business-1','finding','other-finding','upsert',?)",
        [jsonEncode({'job_id': 'other-job', 'finding_id': 'other-finding'})]);
      await sync.pull('business-1');
      expect((await db.customSelect('SELECT id FROM local_jobs').get()).single.read<String>('id'), 'other-job');
      expect((await db.customSelect('SELECT * FROM local_findings').get()).length, 1);
      expect((await db.customSelect('SELECT * FROM local_finding_photos').get()).length, 1);
      expect((await db.customSelect('SELECT * FROM sync_outbox').get()).length, 1);
    } finally { await db.close(); }
  });

  test('server-requested bootstrap preserves verified cleanup with unqueued local photos', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeBriskersApi()..mode = 'bootstrap'..revokedIds = [];
    final gateway = _CleanupGateway();
    final sync = JobSyncService(api: api, database: db, cleanupGateway: gateway);
    try {
      await sync.pull('business-1');
      gateway.deleted = true;
      await db.customStatement("INSERT INTO local_pre_inspections "
        "(id,business_id,job_id) VALUES ('inspection','business-1','job-1')");
      await db.customStatement("INSERT INTO local_pre_inspection_photos "
        "(id,business_id,inspection_id,attachment_id,local_file_path) "
        "VALUES ('photo','business-1','inspection','photo','/keep/photo.jpg')");
      await sync.pull('business-1');
      expect(await db.customSelect('SELECT * FROM local_pre_inspection_photos').get(), isEmpty);
      expect(await LocalJobQuarantine.hasRecovery(db, 'business-1'), isTrue);
    } finally { await db.close(); }
  });

  test('complete authorized snapshot removes omitted ordinary Job despite local media', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeBriskersApi()..mode = 'bootstrap'..revokedIds = [];
    final sync = JobSyncService(api: api, database: db, cleanupGateway: _CleanupGateway());
    try {
      await sync.pull('business-1');
      await db.customStatement("INSERT INTO local_pre_inspections "
        "(id,business_id,job_id,sync_state) VALUES ('inspection','business-1','job-1','pending')");
      await db.customStatement("INSERT INTO local_pre_inspection_photos "
        "(id,business_id,inspection_id,attachment_id,local_file_path,upload_state) "
        "VALUES ('photo','business-1','inspection','photo','/no-longer-authorized/photo.jpg','pending')");
      await sync.pull('business-1');
      expect(await db.customSelect('SELECT * FROM local_jobs').get(), isEmpty);
      expect(await db.customSelect('SELECT * FROM local_pre_inspections').get(), isEmpty);
      expect(await db.customSelect('SELECT * FROM local_pre_inspection_photos').get(), isEmpty);
    } finally { await db.close(); }
  });

  test('shared vehicle finding from revoked Job cannot abort authorized Job bundle', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeBriskersApi();
    final sync = JobSyncService(api: api, database: db, cleanupGateway: _CleanupGateway());
    try {
      await sync.pull('business-1');
      await db.customStatement("INSERT INTO local_jobs (id,business_id,access_scope,title,status,vehicle_id) "
        "VALUES ('job-2','business-1','full','Authorized','open','vehicle-1')");
      api.bundles = [{
        'job': {'id': 'job-2', 'title': 'Updated authorized', 'status': 'open',
          'vehicle_id': 'vehicle-1', 'capabilities': {'manage_job': true},
          'assignments': [], 'visits': []},
        'findings': [
          {'id': 'restricted-finding', 'found_job_id': 'job-1', 'body': 'Hidden', 'status': 'open'},
          {'id': 'allowed-finding', 'found_job_id': 'job-2', 'body': 'Allowed', 'status': 'open'},
        ],
      }];
      await sync.pull('business-1');
      final jobs = await db.customSelect('SELECT id,title FROM local_jobs').get();
      expect(jobs.single.read<String>('id'), 'job-2');
      expect(jobs.single.read<String>('title'), 'Updated authorized');
      final findings = await db.customSelect('SELECT id FROM local_findings').get();
      expect(findings.single.read<String>('id'), 'allowed-finding');
    } finally { await db.close(); }
  });

  test('positive bundle requested before a second revocation cannot resurface Job', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeBriskersApi();
    final sync = JobSyncService(api: api, database: db, cleanupGateway: _CleanupGateway());
    try {
      await sync.pull('business-1');
      await LocalJobQuarantine.quarantineJobs(db, 'business-1', ['job-1']);
      await LocalJobQuarantine.classifyJobs(db, 'business-1', ['job-1'], cleanupJobIds: {});
      api.revokedIds = [];
      api.bundles = [{'job': {'id': 'job-1', 'title': 'Stale positive', 'status': 'open'}}];
      api.beforePullReturns = () => LocalJobQuarantine.quarantineJobs(db, 'business-1', ['job-1']);
      await expectLater(sync.pull('business-1'), throwsA(isA<LocalJobQuarantineException>()));
      expect(await db.customSelect('SELECT * FROM local_jobs').get(), isEmpty);
      expect(await LocalJobQuarantine.isJobBlocked(db, 'business-1', 'job-1'), isTrue);
    } finally { await db.close(); }
  });

  test('job sync bootstraps and later revokes local job access', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeBriskersApi();
    final sync = JobSyncService(api: api, database: database, cleanupGateway: _CleanupGateway());

    await sync.pull('business-1');

    final afterBootstrap = await database.customSelect(
      'SELECT id, access_scope FROM local_jobs WHERE business_id = ?',
      variables: [const Variable<String>('business-1')],
    ).get();

    expect(afterBootstrap, hasLength(1));
    expect(afterBootstrap.single.read<String>('id'), 'job-1');
    expect(afterBootstrap.single.read<String>('access_scope'), 'available');

    final temp = await Directory.systemTemp.createTemp(
      'briskers-revoke-test-',
    );
    final staged = File('${temp.path}/queued.jpg');
    await staged.writeAsBytes([1, 2, 3], flush: true);
    final syncedFindingPhoto =
        File('${temp.path}/synced-finding.jpg');
    await syncedFindingPhoto.writeAsBytes(
      [4, 5, 6],
      flush: true,
    );

    await database.customStatement(
      '''
      INSERT INTO local_pre_inspections (
        id, business_id, job_id, vehicle_id, notes, sync_state
      ) VALUES (?, ?, ?, ?, ?, 'pending')
      ''',
      [
        'local-inspection',
        'business-1',
        'job-1',
        'vehicle-1',
        'Unsent mechanic note',
      ],
    );
    await database.customStatement(
      '''
      INSERT INTO local_pre_inspection_photos (
        id, business_id, inspection_id, attachment_id,
        local_file_path, filename, mime_type, upload_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending')
      ''',
      [
        'local-photo',
        'business-1',
        'local-inspection',
        'local-photo',
        staged.path,
        'queued.jpg',
        'image/jpeg',
      ],
    );

    await database.customStatement(
      '''
      INSERT INTO local_findings (
        id, business_id, vehicle_id, found_job_id,
        body, status, include_on_invoice, created_at,
        can_edit, can_delete, row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, 'open', 0, ?, 1, 0, 1, 'synced')
      ''',
      [
        'finding-1',
        'business-1',
        'vehicle-1',
        'job-1',
        'Finding',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );
    await database.customStatement(
      '''
      INSERT INTO local_finding_photos (
        id, business_id, finding_id, attachment_id,
        local_file_path, filename, mime_type, upload_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 'synced')
      ''',
      [
        'finding-photo-1',
        'business-1',
        'finding-1',
        'finding-photo-1',
        syncedFindingPhoto.path,
        'synced-finding.jpg',
        'image/jpeg',
      ],
    );

    final createdAt =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    for (final entry in <Map<String, String>>[
      {
        'entity_type': 'preinspection',
        'entity_id': 'job-1',
        'operation': 'upsert',
      },
      {
        'entity_type': 'preinspection_photo',
        'entity_id': 'local-photo',
        'operation': 'upload',
      },
    ]) {
      await database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation,
          payload_json, state, attempt_count, created_at
        ) VALUES (?, ?, ?, ?, ?, 'pending', 0, ?)
        ''',
        [
          'business-1',
          entry['entity_type'],
          entry['entity_id'],
          entry['operation'],
          jsonEncode({'job_id': 'job-1'}),
          createdAt,
        ],
      );
    }

    await sync.pull('business-1');

    final afterRevoke = await database.customSelect(
      'SELECT id FROM local_jobs WHERE business_id = ?',
      variables: [const Variable<String>('business-1')],
    ).get();

    expect(afterRevoke, isEmpty);

    final remainingOutbox = await database.customSelect(
      'SELECT COUNT(*) AS count FROM sync_outbox WHERE business_id = ?',
      variables: [const Variable<String>('business-1')],
    ).getSingle();
    expect(remainingOutbox.read<int>('count'), 0);

    final remainingInspection = await database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM local_pre_inspections
      WHERE business_id = ? AND job_id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        const Variable<String>('job-1'),
      ],
    ).getSingle();
    expect(remainingInspection.read<int>('count'), 0);
    expect(await staged.exists(), isTrue);
    expect(await syncedFindingPhoto.exists(), isTrue);

    final syncState = await database.customSelect(
      '''
      SELECT last_server_cursor, bootstrapped
      FROM local_sync_states
      WHERE business_id = ? AND scope = 'jobs'
      ''',
      variables: [const Variable<String>('business-1')],
    ).getSingle();

    expect(syncState.read<int>('last_server_cursor'), 11);
    expect(syncState.read<int>('bootstrapped'), 1);

    await database.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });
}
