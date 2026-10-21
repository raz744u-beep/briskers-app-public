import '../core/connection_mode.dart';
import 'briskers_api.dart';
import 'customer_detail_cache.dart';
import 'job_summary_visibility.dart';
import 'offline_work_findings_service.dart';
import 'vehicle_finding_actions_service.dart';
import 'work_finding_merge.dart';

/// Read-only per-customer totals. One finding identity is counted only once,
/// even when the same finding is visible in a past Job and vehicle history.
class CustomerFindingCounts {
  const CustomerFindingCounts({
    required this.open,
    required this.inJob,
    required this.resolved,
  });

  final int open;
  final int inJob;
  final int resolved;

  int get total => open + inJob + resolved;

  static CustomerFindingCounts fromRows(Iterable<Map<String, dynamic>> rows) {
    final ids = <String>{};
    var open = 0;
    var inJob = 0;
    var resolved = 0;
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty || !ids.add(id)) continue;
      final status = row['status']?.toString();
      if (status == 'resolved') {
        resolved++;
      } else if (status == 'in_job') {
        inJob++;
      } else {
        open++;
      }
    }
    return CustomerFindingCounts(open: open, inJob: inJob, resolved: resolved);
  }
}

/// Only vehicles belonging to this customer are queried. The same
/// quarantined/permission-filtered source, local edits, and pending actions
/// used in All Vehicle Findings are applied to the counts.
class CustomerFindingOverviewService {
  CustomerFindingOverviewService({
    BriskersApi api = const BriskersApi(),
    CustomerDetailCache cache = const CustomerDetailCache(),
    OfflineWorkFindingsService? work,
    VehicleFindingActionsService? actions,
  }) : _api = api,
       _cache = cache,
       _work = work ?? OfflineWorkFindingsService(),
       _actions = actions ?? VehicleFindingActionsService();

  final BriskersApi _api;
  final CustomerDetailCache _cache;
  final OfflineWorkFindingsService _work;
  final VehicleFindingActionsService _actions;

  Future<CustomerFindingCounts> load({
    required String businessId,
    required String customerId,
    required List<dynamic> vehicles,
  }) async {
    final ids = <String>{};
    for (final vehicle in vehicles.whereType<Map>()) {
      final id = vehicle['id']?.toString() ?? '';
      if (id.isNotEmpty) ids.add(id);
    }
    if (ids.isEmpty) {
      return const CustomerFindingCounts(open: 0, inJob: 0, resolved: 0);
    }

    final visibility = JobSummaryVisibility(
      businessId: businessId,
      onQuarantine: (_) {},
    );
    try {
      final raw = await _cache.load(businessId, customerId, 'findings');
      final cached = raw is List
          ? raw.whereType<Map>().map(Map<String, dynamic>.from)
              .where((row) => ids.contains(
                  (row['_vehicle_id'] ?? row['vehicle_id'])?.toString()))
              .toList()
          : <Map<String, dynamic>>[];
      final cachedVisible = await visibility.filterFindings(
        cached, cached: true,
      );

      final local = <Map<String, dynamic>>[];
      for (final vehicleId in ids) {
        final localRows = await _work.loadLocalFindings(
          businessId, vehicleId,
        );
        local.addAll(localRows.map((row) => <String, dynamic>{
          ...row,
          '_vehicle_id': vehicleId,
        }));
      }
      final permittedLocal = await visibility.filterFindings(local);

      List<Map<String, dynamic>> serverOrCache = cachedVisible;
      var fetchedServer = false;
      if (!BriskersConnectionModeController.instance.forceOffline) {
        try {
          final server = <Map<String, dynamic>>[];
          for (final vehicleId in ids) {
            final rows = await _api.vehicleFindings(
              businessId,
              vehicleId,
              includeResolved: true,
            );
            server.addAll(rows.map((row) => <String, dynamic>{
              ...row,
              '_vehicle_id': vehicleId,
            }));
          }
          final permittedServer = await visibility.filterFindings(server);
          fetchedServer = true;
          // A locally created finding has no permanent server ID yet. Keep
          // only unread/sync-pending local drafts from the cached section;
          // never resurrect a previously synced or revoked cached record.
          final pendingDrafts = cachedVisible.where((row) =>
              (row['id']?.toString() ?? '').startsWith('local-finding-') &&
              const {'pending', 'conflict'}.contains(
                row['sync_state']?.toString())).toList();
          serverOrCache = mergeWorkFindings(
            permittedServer, pendingDrafts,
          );
        } catch (_) {
          // Offline/temporarily unavailable server: retain permitted
          // cached and local counts without clearing notifications/data.
          serverOrCache = cachedVisible;
        }
      }
      // Never present a confident zero when the device has no recorded
      // findings snapshot and the server could not be checked. The row
      // remains tappable and offers the full screen for retry.
      if (!fetchedServer && raw is! List && permittedLocal.isEmpty) {
        throw StateError('No trusted findings snapshot is available.');
      }
      final merged = mergeWorkFindings(serverOrCache, permittedLocal);
      final projected = await _actions.project(businessId, merged);
      return CustomerFindingCounts.fromRows(
        await visibility.filterFindings(projected),
      );
    } finally {
      visibility.dispose();
    }
  }
}
