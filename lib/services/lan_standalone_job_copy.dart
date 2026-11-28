import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'lan_record_inventory.dart';
import 'local_job_deletion_v3.dart';
import 'local_job_quarantine.dart';
import 'local_job_retirement.dart';
import 'local_number_allocator.dart';

/// Copies the saved local projection of open jobs whose related work can be
/// represented by the job, customer, vehicle, and ownership link alone.
class LanStandaloneJobCopy {
  const LanStandaloneJobCopy(this.db);

  final BriskersLocalDatabase db;

  Future<int?> _cursor(String business) async {
    final row =
        await (db.select(db.localSyncStates)..where(
              (row) =>
                  row.businessId.equals(business) &
                  row.scope.equals('jobs') &
                  row.bootstrapped.equals(true),
            ))
            .getSingleOrNull();
    return row?.lastServerCursor;
  }

  static int? _number(LocalJob job) =>
      LocalNumberAllocator.parseJobNumber(job.jobNumber);

  static bool _eligible(LocalJob job, String business) =>
      job.businessId == business &&
      job.id.isNotEmpty &&
      !job.id.startsWith('local-') &&
      job.accessScope == 'full' &&
      job.syncState == 'synced' &&
      job.status == 'open' &&
      job.isUnassigned &&
      job.assignedEmployeeId == null &&
      job.pendingRequestCount == 0 &&
      job.completedAt == null &&
      job.paymentState == null &&
      job.customerId != null &&
      job.vehicleId != null &&
      (_number(job) ?? 0) > 0;

  Future<Set<String>> _blocked(String business) async {
    final ids = {
      ...await LocalJobRetirement.blockedJobIds(db, business),
      ...await LocalJobQuarantine.blockedJobIds(db, business),
      ...await LocalJobDeletionV3.blockedJobIds(db, business),
    };
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    final names = {for (final row in tables) row.read<String>('name')};
    // Keep records with work or history on either phone in the review list
    // until all of their associated records can travel together.
    const references = {
      'local_appointments': ['job_id'],
      'local_documents': ['job_id'],
      'local_job_assignments': ['job_id'],
      'local_job_visits': ['job_id'],
      'local_pre_inspections': ['job_id'],
      'local_job_work_dates': ['job_id'],
      'local_job_status_intent_v1': ['job_id'],
      'local_job_task_activity_v1': ['job_id'],
      'local_job_identity_aliases': ['alias_id', 'canonical_id'],
      'regular_payroll_job_lead': ['job_id'],
      'regular_payroll_tasks': ['job_id'],
      'regular_payroll_shop_task_jobs': ['job_id'],
      'regular_payroll_jobs': ['id'],
      'sync_outbox': ['entity_id'],
    };
    for (final entry in references.entries) {
      if (!names.contains(entry.key)) continue;
      for (final column in entry.value) {
        final rows = await db
            .customSelect(
              'SELECT DISTINCT $column AS job_id FROM ${entry.key} '
              'WHERE business_id=? AND $column IS NOT NULL'
              "${entry.key == 'sync_outbox' ? " AND state<>'done'" : ''}",
              variables: [Variable(business)],
            )
            .get();
        ids.addAll(rows.map((row) => row.read<String>('job_id')));
      }
    }
    return ids;
  }

  Future<Map<String, dynamic>?> share(String business) async {
    final cursor = await _cursor(business);
    if (cursor == null || cursor < 0) return null;
    final blocked = await _blocked(business);
    final jobs = await (db.select(
      db.localJobs,
    )..where((row) => row.businessId.equals(business))).get();
    final numberCounts = <int?, int>{};
    for (final job in jobs) {
      numberCounts.update(
        _number(job),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return {
      'cursor': cursor,
      'records': [
        for (final job in jobs)
          if (_eligible(job, business) &&
              !blocked.contains(job.id) &&
              numberCounts[_number(job)] == 1)
            job.toJson(),
      ],
    };
  }

  Future<int> copyMissing({
    required String business,
    required Object? bundle,
    required Map<String, LocalCustomer> sourceCustomers,
    required Map<String, LocalVehicle> sourceVehicles,
    required Map<String, List<LocalCustomerVehicle>> sourceLinks,
    required Set<String> queuedIds,
    required Set<String> approvedIdentities,
  }) async {
    if (bundle == null) return 0;
    if (bundle is! Map<String, dynamic> ||
        bundle['cursor'] is! int ||
        bundle['records'] is! List) {
      throw const FormatException('Invalid job copy data.');
    }
    final cursor = await _cursor(business);
    if (cursor == null || cursor < 0 || (bundle['cursor'] as int) < cursor) {
      return 0;
    }

    final jobs = <LocalJob>[];
    final sourceIds = <String>{};
    final sourceNumbers = <int?, int>{};
    for (final raw in bundle['records'] as List<dynamic>) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid LAN job.');
      }
      final job = LocalJob.fromJson(raw);
      if (!_eligible(job, business) || !sourceIds.add(job.id)) {
        throw const FormatException('Invalid or duplicate LAN job.');
      }
      jobs.add(job);
      sourceNumbers.update(
        _number(job),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    if (jobs.isEmpty) return 0;

    final blocked = await _blocked(business);
    final saved = await db.select(db.localJobs).get();
    final savedIds = {for (final job in saved) job.id};
    final savedNumbers = await LocalNumberAllocator(db).occupiedNumbers(
      business,
      'job',
    );
    final customers = {
      for (final row in await (db.select(
        db.localCustomers,
      )..where((row) => row.businessId.equals(business))).get())
        row.id: row,
    };
    final vehicles = {
      for (final row in await (db.select(
        db.localVehicles,
      )..where((row) => row.businessId.equals(business))).get())
        row.id: row,
    };
    final links = await (db.select(
      db.localCustomerVehicles,
    )..where((row) => row.businessId.equals(business))).get();
    final owners = <String, Set<String>>{};
    for (final link in links) {
      (owners[link.vehicleId] ??= {}).add(link.customerId);
    }

    var copied = 0;
    for (final job in jobs) {
      final customer = sourceCustomers[job.customerId];
      final vehicle = sourceVehicles[job.vehicleId];
      final linkedOwners = owners[job.vehicleId];
      final originalLinks = sourceLinks[job.vehicleId];
      if (!approvedIdentities.contains(
            LanRecordInventory.recordIdentity(business, 'job', job.id),
          ) ||
          blocked.contains(job.id) ||
          savedIds.contains(job.id) ||
          savedNumbers.contains(_number(job)) ||
          sourceNumbers[_number(job)] != 1 ||
          customer == null ||
          customer != customers[customer.id] ||
          queuedIds.contains(customer.id) ||
          vehicle == null ||
          vehicle != vehicles[vehicle.id] ||
          queuedIds.contains(vehicle.id) ||
          originalLinks?.length != 1 ||
          originalLinks!.single.customerId != customer.id ||
          linkedOwners?.length != 1 ||
          !linkedOwners!.contains(customer.id)) {
        continue;
      }
      await db.into(db.localJobs).insert(job);
      copied++;
    }
    return copied;
  }
}
