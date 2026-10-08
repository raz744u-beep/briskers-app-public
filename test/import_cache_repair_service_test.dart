import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/import_cache_repair_service.dart';

class _RepairApi extends BriskersApi {
  @override
  Future<Map<String, dynamic>> syncPullCustomersVehicles(
    String businessId, {
    int? afterCursor,
    String? afterCustomerId,
    int limit = 250,
  }) async {
    if (afterCursor != null) {
      return {
        'mode': 'incremental',
        'next_cursor': afterCursor,
        'has_more': false,
        'bundles': <dynamic>[],
        'revoked_customer_ids': <dynamic>[],
      };
    }
    return {
      'mode': 'bootstrap',
      'revoke_all': false,
      'bootstrap_cursor': 10,
      'next_customer_id': 'current-customer',
      'has_more': false,
      'bundles': [
        {
          'customer': {'id': 'current-customer'},
          'vehicles': <dynamic>[],
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
    if (afterCursor != null) {
      return {
        'mode': 'incremental',
        'next_cursor': afterCursor,
        'has_more': false,
        'bundles': <dynamic>[],
        'revoked_job_ids': <dynamic>[],
      };
    }
    return {
      'mode': 'bootstrap',
      'next_cursor': 10,
      'has_more': false,
      'bundles': [
        {
          'job': {'id': 'current-job'},
        },
      ],
    };
  }
}

Future<void> _seed(BriskersLocalDatabase db) async {
  for (final scope in ['customers_vehicles', 'jobs']) {
    await db.customStatement(
      '''
      INSERT INTO local_sync_states
        (business_id, scope, last_server_cursor, bootstrapped)
      VALUES (?, ?, 10, 1)
      ''',
      ['business-1', scope],
    );
  }
  for (final id in ['current-customer', 'old-customer']) {
    await db.customStatement(
      '''
      INSERT INTO local_customers
        (id, business_id, display_name, sync_state)
      VALUES (?, ?, ?, 'synced')
      ''',
      [id, 'business-1', 'Raymond Taylor'],
    );
  }
  for (final id in ['current-vehicle', 'old-vehicle']) {
    await db.customStatement(
      '''
      INSERT INTO local_vehicles
        (id, business_id, make, model, sync_state)
      VALUES (?, ?, 'BMW', 'X5', 'synced')
      ''',
      [id, 'business-1'],
    );
  }
  for (final i in ['current', 'old']) {
    await db.customStatement(
      '''
      INSERT INTO local_customer_vehicles
        (business_id, customer_id, vehicle_id, is_primary)
      VALUES (?, ?, ?, 1)
      ''',
      ['business-1', '$i-customer', '$i-vehicle'],
    );
    await db.customStatement(
      '''
      INSERT INTO local_jobs
        (id, business_id, access_scope, title, status,
         customer_id, vehicle_id, sync_state)
      VALUES (?, ?, 'full', 'Service', 'completed', ?, ?, 'synced')
      ''',
      ['$i-job', 'business-1', '$i-customer', '$i-vehicle'],
    );
  }
  await db.customStatement(
    '''
    INSERT INTO local_documents
      (id, business_id, kind, sync_state)
    VALUES ('doc-1', 'business-1', 'invoice', 'synced')
    ''',
  );
}

Future<int> _rows(BriskersLocalDatabase db, String table) async {
  final row = await db.customSelect(
    'SELECT COUNT(*) AS count FROM $table WHERE business_id = ?',
    variables: [const Variable<String>('business-1')],
  ).getSingle();
  return row.read<int>('count');
}

void main() {
  test('repairs stale local customers, vehicles and jobs without touching invoices',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await _seed(db);
    final result = await ImportCacheRepairService(
      api: _RepairApi(),
      database: db,
    ).repair('business-1');

    expect(result.customersRemoved, 1);
    expect(result.vehiclesRemoved, 1);
    expect(result.jobsRemoved, 1);
    expect(await _rows(db, 'local_customers'), 1);
    expect(await _rows(db, 'local_vehicles'), 1);
    expect(await _rows(db, 'local_jobs'), 1);
    expect(await _rows(db, 'local_documents'), 1);
    await db.close();
  });

  test('refuses repair with queued offline changes', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await _seed(db);
    await db.customStatement(
      '''
      INSERT INTO sync_outbox
        (business_id, entity_type, entity_id, operation, payload_json)
      VALUES ('business-1', 'customer', 'old-customer', 'update', '{}')
      ''',
    );
    await expectLater(
      ImportCacheRepairService(api: _RepairApi(), database: db)
          .repair('business-1'),
      throwsStateError,
    );
    expect(await _rows(db, 'local_customers'), 2);
    expect(await _rows(db, 'local_jobs'), 2);
    await db.close();
  });

  test('refuses repair when old jobs have local photo files', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await _seed(db);
    await db.customStatement(
      '''
      INSERT INTO local_pre_inspections
        (id, business_id, job_id, vehicle_id, sync_state)
      VALUES ('inspection-1', 'business-1', 'old-job',
              'old-vehicle', 'synced')
      ''',
    );
    await db.customStatement(
      '''
      INSERT INTO local_pre_inspection_photos
        (id, business_id, inspection_id, attachment_id,
         local_file_path, upload_state)
      VALUES ('photo-1', 'business-1', 'inspection-1',
              'photo-1', '/photos/keep-this.jpg', 'synced')
      ''',
    );
    await expectLater(
      ImportCacheRepairService(api: _RepairApi(), database: db)
          .repair('business-1'),
      throwsStateError,
    );
    expect(await _rows(db, 'local_customers'), 2);
    expect(await _rows(db, 'local_jobs'), 2);
    expect(await _rows(db, 'local_pre_inspection_photos'), 1);
    await db.close();
  });
}
