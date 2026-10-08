import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/job_sync_service.dart';

class _FakeBriskersApi extends BriskersApi {
  _FakeBriskersApi();

  var calls = 0;

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
    expect(afterCursor, 10);
    return {
      'mode': 'incremental',
      'next_cursor': 11,
      'has_more': false,
      'bundles': <dynamic>[],
      'revoked_job_ids': ['job-1'],
    };
  }

}

class _PagedApi extends BriskersApi {
  final requestedAfterIds = <String?>[];

  @override
  Future<Map<String, dynamic>> syncPullJobsBootstrap(
    String businessId, {
    String? afterJobId,
    int limit = 25,
  }) async {
    requestedAfterIds.add(afterJobId);
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
    final sync = JobSyncService(api: api, database: db);
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

  test('job sync bootstraps and later revokes local job access', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeBriskersApi();
    final sync = JobSyncService(api: api, database: database);

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
    expect(await staged.exists(), isFalse);
    expect(await syncedFindingPhoto.exists(), isFalse);

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
