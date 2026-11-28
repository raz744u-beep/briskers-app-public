import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'lan_record_inventory.dart';
import 'local_job_deletion_v3.dart';
import 'local_job_quarantine.dart';
import 'local_job_retirement.dart';
import 'local_job_work_date.dart';
import 'local_number_allocator.dart';
import 'local_task_schedule.dart';

/// Copies the saved local projection of open jobs whose related work can be
/// represented by the job, its saved visits, and its customer and vehicle.
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
      'local_pre_inspections': ['job_id'],
      'local_findings': ['found_job_id', 'repair_job_id'],
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

  static bool _validVisits(List<LocalJobVisit> visits, LocalJob job) {
    final ids = <String>{};
    final numbers = <int>{};
    return visits.every(
      (visit) =>
          visit.businessId == job.businessId &&
          visit.jobId == job.id &&
          visit.id.isNotEmpty &&
          !visit.id.startsWith('local-') &&
          visit.syncState == 'synced' &&
          visit.visitNumber > 0 &&
          ids.add(visit.id) &&
          numbers.add(visit.visitNumber),
    );
  }

  static bool _validWorkDate(Object? value) =>
      LocalTaskSchedule.parse(value) != null;

  Future<Set<String>> _blockedVisits(String business) async => {
    ...await LocalJobDeletionV3.blockedIds(db, business, kind: 'job_visit'),
    ...await LocalJobQuarantine.blockedEntityIds(
      db,
      business,
      entityType: 'local_job_visits',
    ),
  };

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
    final visits = await (db.select(
      db.localJobVisits,
    )..where((row) => row.businessId.equals(business))).get();
    final visitsByJob = <String, List<LocalJobVisit>>{};
    for (final visit in visits) {
      (visitsByJob[visit.jobId] ??= []).add(visit);
    }
    final blockedVisits = await _blockedVisits(business);
    final dates = await LocalJobWorkDate(db).savedDates(business);
    final records = <Map<String, dynamic>>[];
    final recordsWithVisits = <Map<String, dynamic>>[];
    final recordsWithWorkDates = <Map<String, dynamic>>[];
    for (final job in jobs) {
      if (!_eligible(job, business) ||
          blocked.contains(job.id) ||
          numberCounts[_number(job)] != 1) {
        continue;
      }
      final history = visitsByJob[job.id] ?? const [];
      final workDate = dates[job.id];
      if (!_validVisits(history, job) ||
          history.any(
            (visit) =>
                blockedVisits.contains(visit.id) || blocked.contains(visit.id),
          ) ||
          (workDate != null && !_validWorkDate(workDate))) {
        continue;
      }
      final record = job.toJson();
      if (workDate != null || history.isNotEmpty) {
        final bundle = {
          'job': record,
          'visits': [for (final visit in history) visit.toJson()],
        };
        if (workDate == null) {
          recordsWithVisits.add(bundle);
        } else {
          recordsWithWorkDates.add({...bundle, 'workDate': workDate});
        }
      } else {
        records.add(record);
      }
    }
    // Older receivers skip bundles with fields they cannot preserve.
    return {
      'cursor': cursor,
      'records': records,
      'recordsWithVisits': recordsWithVisits,
      'recordsWithWorkDates': recordsWithWorkDates,
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
        bundle['records'] is! List ||
        (bundle.containsKey('recordsWithVisits') &&
            bundle['recordsWithVisits'] is! List) ||
        (bundle.containsKey('recordsWithWorkDates') &&
            bundle['recordsWithWorkDates'] is! List)) {
      throw const FormatException('Invalid job copy data.');
    }
    final cursor = await _cursor(business);
    if (cursor == null || cursor < 0 || (bundle['cursor'] as int) < cursor) {
      return 0;
    }

    final jobs =
        <({LocalJob job, List<LocalJobVisit> visits, String? workDate})>[];
    final sourceIds = <String>{};
    final sourceVisitIds = <String>{};
    final sourceNumbers = <int?, int>{};
    for (final (raw, nested, dated) in [
      for (final raw in bundle['records'] as List) (raw, false, false),
      for (final raw in bundle['recordsWithVisits'] as List? ?? const [])
        (raw, true, false),
      for (final raw in bundle['recordsWithWorkDates'] as List? ?? const [])
        (raw, true, true),
    ]) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid LAN job.');
      }
      final payload = nested ? raw['job'] : raw;
      final rawVisits = nested ? raw['visits'] : const [];
      final workDate = dated ? raw['workDate'] : null;
      if (payload is! Map<String, dynamic> ||
          rawVisits is! List ||
          (nested && !dated && rawVisits.isEmpty) ||
          (dated && !_validWorkDate(workDate)) ||
          (!dated && raw.containsKey('workDate')) ||
          rawVisits.any((visit) => visit is! Map<String, dynamic>)) {
        throw const FormatException('Invalid LAN job history or Job Date.');
      }
      final job = LocalJob.fromJson(payload);
      final visits = [
        for (final visit in rawVisits.cast<Map<String, dynamic>>())
          LocalJobVisit.fromJson(visit),
      ];
      if (!_eligible(job, business) ||
          !sourceIds.add(job.id) ||
          !_validVisits(visits, job) ||
          visits.any((visit) => !sourceVisitIds.add(visit.id))) {
        throw const FormatException('Invalid or duplicate LAN job or visit.');
      }
      jobs.add((job: job, visits: visits, workDate: workDate as String?));
      sourceNumbers.update(
        _number(job),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    if (jobs.isEmpty) return 0;

    final blocked = await _blocked(business);
    final localDates = await LocalJobWorkDate(db).savedDates(business);
    final localVisits = await db.select(db.localJobVisits).get();
    final occupiedVisitIds = {
      ...await _blockedVisits(business),
      for (final visit in localVisits) visit.id,
    };
    final jobsWithLocalVisits = {
      for (final visit in localVisits)
        if (visit.businessId == business) visit.jobId,
    };
    final saved = await db.select(db.localJobs).get();
    final savedIds = {for (final job in saved) job.id};
    final savedNumbers = await LocalNumberAllocator(
      db,
    ).occupiedNumbers(business, 'job');
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
    for (final (:job, :visits, :workDate) in jobs) {
      final customer = sourceCustomers[job.customerId];
      final vehicle = sourceVehicles[job.vehicleId];
      final linkedOwners = owners[job.vehicleId];
      final originalLinks = sourceLinks[job.vehicleId];
      if (!approvedIdentities.contains(
            LanRecordInventory.recordIdentity(business, 'job', job.id),
          ) ||
          blocked.contains(job.id) ||
          savedIds.contains(job.id) ||
          jobsWithLocalVisits.contains(job.id) ||
          localDates.containsKey(job.id) ||
          visits.any(
            (visit) =>
                occupiedVisitIds.contains(visit.id) ||
                blocked.contains(visit.id),
          ) ||
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
      for (final visit in visits) {
        await db.into(db.localJobVisits).insert(visit);
      }
      if (workDate != null) {
        await db.customStatement(
          'INSERT INTO local_job_work_dates (business_id,job_id,work_date) VALUES (?,?,?)',
          [business, job.id, workDate],
        );
      }
      copied++;
    }
    return copied;
  }
}
