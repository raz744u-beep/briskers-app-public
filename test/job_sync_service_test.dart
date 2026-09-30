import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/job_sync_service.dart';

class _FakeBriskersApi extends BriskersApi {
  _FakeBriskersApi();

  var calls = 0;

  @override
  Future<Map<String, dynamic>> syncPullJobs(
    String businessId, {
    int? afterCursor,
    int limit = 250,
  }) async {
    calls++;

    if (calls == 1) {
      expect(afterCursor, isNull);
      return {
        'mode': 'bootstrap',
        'next_cursor': 10,
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

void main() {
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

    await sync.pull('business-1');

    final afterRevoke = await database.customSelect(
      'SELECT id FROM local_jobs WHERE business_id = ?',
      variables: [const Variable<String>('business-1')],
    ).get();

    expect(afterRevoke, isEmpty);

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
  });
}
