import 'package:drift/drift.dart' show Variable;

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'customer_vehicle_sync_service.dart';
import 'job_sync_service.dart';

class ImportCacheRepairResult {
  const ImportCacheRepairResult({
    required this.customersRemoved,
    required this.vehiclesRemoved,
    required this.jobsRemoved,
  });

  final int customersRemoved;
  final int vehiclesRemoved;
  final int jobsRemoved;
}

/// Reconcile caches after a bulk legacy import/cutover, when old rows may
/// have been removed server-side without individual incremental tombstones.
///
/// No remote records are modified. Ordinary "Sync now" stays incremental.
/// A full authoritative snapshot is required before any local cleanup.
class ImportCacheRepairService {
  ImportCacheRepairService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
  })  : _api = api,
        _database = database ?? localDatabase,
        _customers = CustomerVehicleSyncService(
          api: api,
          database: database ?? localDatabase,
        ),
        _jobs = JobSyncService(
          api: api,
          database: database ?? localDatabase,
        );

  final BriskersApi _api;
  final BriskersLocalDatabase _database;
  final CustomerVehicleSyncService _customers;
  final JobSyncService _jobs;

  Future<int> _count(String businessId, String sql) async {
    final row = await _database.customSelect(
      sql,
      variables: [Variable<String>(businessId)],
    ).getSingle();
    return row.read<int>('count');
  }

  Future<void> _assertNoLocalWork(String businessId) async {
    final queued = await _count(
      businessId,
      'SELECT COUNT(*) AS count FROM sync_outbox WHERE business_id = ?',
    );
    if (queued != 0) {
      throw StateError(
        'Repair blocked: $queued locally queued changes remain. '
        'Sync or resolve them before repairing imported data.',
      );
    }
    for (final table in const [
      'local_customers',
      'local_vehicles',
      'local_jobs',
      'local_job_visits',
      'local_findings',
      'local_pre_inspections',
      'local_appointments',
      'local_documents',
    ]) {
      final dirty = await _count(
        businessId,
        "SELECT COUNT(*) AS count FROM $table "
        "WHERE business_id = ? AND sync_state <> 'synced'",
      );
      if (dirty != 0) {
        throw StateError(
          'Repair blocked: $dirty unsynced records in $table. '
          'Sync or resolve offline edits before proceeding.',
        );
      }
    }
    for (final table in const [
      'local_pre_inspection_photos',
      'local_finding_photos',
    ]) {
      final pending = await _count(
        businessId,
        "SELECT COUNT(*) AS count FROM $table "
        "WHERE business_id = ? AND upload_state <> 'synced'",
      );
      if (pending != 0) {
        throw StateError(
          'Repair blocked: $pending locally stored photos in $table '
          'have not finished uploading.',
        );
      }
    }
  }

  Future<Set<String>> _serverCustomers(String businessId) async {
    final ids = <String>{};
    String? afterId;
    int? snapshotCursor;
    var pages = 0;
    while (true) {
      if (++pages > 10000) {
        throw StateError('Customer snapshot exceeded page safety limit.');
      }
      final response = await _api.syncPullCustomersVehicles(
        businessId,
        afterCustomerId: afterId,
      );
      if (response['revoke_all'] == true ||
          response['mode']?.toString() != 'bootstrap') {
        throw StateError('Cannot verify a complete customer snapshot.');
      }
      final cursor =
          int.tryParse(response['bootstrap_cursor']?.toString() ?? '');
      if (cursor == null ||
          (snapshotCursor != null && snapshotCursor != cursor)) {
        throw StateError(
          'Customers changed during the snapshot. Retry the repair.',
        );
      }
      snapshotCursor = cursor;
      final bundles = response['bundles'];
      if (bundles is! List) {
        throw StateError('Invalid customer snapshot response.');
      }
      for (final bundle in bundles) {
        if (bundle is! Map || bundle['customer'] is! Map) {
          throw StateError('Invalid customer in server snapshot.');
        }
        final id = (bundle['customer'] as Map)['id']?.toString() ?? '';
        if (id.isEmpty || !ids.add(id)) {
          throw StateError('Duplicate or missing customer snapshot ID.');
        }
      }
      if (response['has_more'] != true) break;
      final nextId = response['next_customer_id']?.toString() ?? '';
      if (nextId.isEmpty || nextId == afterId) {
        throw StateError('Incomplete customer snapshot pagination.');
      }
      afterId = nextId;
    }
    return ids;
  }

  Future<Set<String>> _serverJobs(String businessId) async {
    final response = await _api.syncPullJobs(
      businessId,
      afterCursor: null,
    );
    if (response['mode']?.toString() != 'bootstrap' ||
        response['has_more'] == true) {
      throw StateError('Cannot verify a complete job snapshot.');
    }
    final bundles = response['bundles'];
    if (bundles is! List) {
      throw StateError('Invalid job snapshot response.');
    }
    final ids = <String>{};
    for (final bundle in bundles) {
      if (bundle is! Map || bundle['job'] is! Map) {
        throw StateError('Invalid job in server snapshot.');
      }
      final id = (bundle['job'] as Map)['id']?.toString() ?? '';
      if (id.isEmpty || !ids.add(id)) {
        throw StateError('Duplicate or missing job snapshot ID.');
      }
    }
    return ids;
  }

  Future<void> _checkLocalCoverage(
    String businessId,
    String table,
    Set<String> serverIds,
  ) async {
    final rows = await _database.customSelect(
      'SELECT id FROM $table WHERE business_id = ?',
      variables: [Variable<String>(businessId)],
    ).get();
    final localIds = rows.map((row) => row.read<String>('id')).toSet();
    final missing = serverIds.difference(localIds);
    if (missing.isNotEmpty) {
      throw StateError(
        'Repair stopped: ${missing.length} server records were not cached '
        'in $table. Finish the download, then retry.',
      );
    }
  }

  Future<ImportCacheRepairResult> repair(String businessId) async {
    await _assertNoLocalWork(businessId);

    // Get the latest changes without discarding locally saved photos.
    await _customers.pull(businessId);
    await _jobs.pull(businessId);
    await _assertNoLocalWork(businessId);

    // Snapshot all IDs before making any destructive local change.
    final customerIds = await _serverCustomers(businessId);
    final jobIds = await _serverJobs(businessId);
    if (customerIds.isEmpty || jobIds.isEmpty) {
      throw StateError('Empty server snapshot: local cleanup is blocked.');
    }
    await _checkLocalCoverage(
      businessId, 'local_customers', customerIds,
    );
    await _checkLocalCoverage(
      businessId, 'local_jobs', jobIds,
    );
    await _assertNoLocalWork(businessId);

    final vehiclesBefore = await _count(
      businessId,
      'SELECT COUNT(*) AS count FROM local_vehicles WHERE business_id = ?',
    );
    // Jobs are checked for cached photo paths *before* any removal.
    final jobsRemoved = await _jobs.pruneObsoleteCache(
      businessId, jobIds,
    );
    final customersRemoved = await _customers.pruneObsoleteCache(
      businessId, customerIds,
    );
    final vehiclesAfter = await _count(
      businessId,
      'SELECT COUNT(*) AS count FROM local_vehicles WHERE business_id = ?',
    );
    return ImportCacheRepairResult(
      customersRemoved: customersRemoved,
      vehiclesRemoved: vehiclesBefore - vehiclesAfter,
      jobsRemoved: jobsRemoved,
    );
  }
}
