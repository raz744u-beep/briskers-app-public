import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_job_retirement.dart';

class LocalSyncStatusSnapshot {
  const LocalSyncStatusSnapshot({
    this.lastSuccessfulPull,
    this.issues = const [],
    this.pendingUploads = 0,
  });

  final DateTime? lastSuccessfulPull;
  final List<String> issues;
  final int pendingUploads;
}

/// Read-only overview of actual persisted downloads and outstanding uploads.
/// A successful scope never implies that every other scope or upload succeeded.
class LocalSyncStatusRepository {
  LocalSyncStatusRepository({BriskersLocalDatabase? database})
    : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;
  static final _refreshEvents = StreamController<String>.broadcast();
  static Stream<String> get refreshEvents => _refreshEvents.stream;
  static void notifyStateChanged(String businessId) =>
      _refreshEvents.add(businessId);
  static final _manualFailures = <String, List<String>>{};
  static String _failureKey(String businessId) =>
      'sync-header:manual-refresh-failures:$businessId';

  /// Some Settings stages do not own a local_sync_states row. Retain their
  /// failed stage names until the next complete manual retry, including across
  /// restart. This does not manufacture a download timestamp or alter queues.
  static Future<void> recordManualRefreshResult(
    String businessId,
    List<String> failedStages,
  ) async {
    _manualFailures[businessId] = List<String>.unmodifiable(failedStages);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_failureKey(businessId), failedStages);
    } finally {
      _refreshEvents.add(businessId);
    }
  }

  Future<LocalSyncStatusSnapshot> load(String businessId) async {
    final rows = await _database
        .customSelect(
          'SELECT scope, last_pull_at, last_error, bootstrapped '
          'FROM local_sync_states WHERE business_id = ?',
          variables: [Variable<String>(businessId)],
        )
        .get();
    DateTime? latest;
    final issues = <String>[];
    for (final row in rows) {
      final scopeKey = row.read<String>('scope');
      // This cursor is local notification metadata, not a download attempt.
      if (scopeKey == 'customer_notification_baseline') continue;
      final scope = scopeKey.replaceAll('_', ' ');
      final error = row.readNullable<String>('last_error')?.trim();
      if (error != null && error.isNotEmpty) {
        issues.add('$scope: last attempt failed');
        continue;
      }
      if (row.read<int>('bootstrapped') != 1) {
        issues.add('$scope: download incomplete');
        continue;
      }
      final value = row.data['last_pull_at'];
      final pulled = value is DateTime
          ? value.toUtc()
          : value is int
          ? DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
          : DateTime.tryParse(value?.toString() ?? '')?.toUtc();
      if (pulled == null) {
        issues.add('$scope: no successful download recorded');
      } else if (latest == null || pulled.isAfter(latest)) {
        latest = pulled;
      }
    }
    final uploads = await _database
        .customSelect(
          "SELECT COUNT(*) AS pending, SUM(CASE WHEN state IN ('failed','conflict') "
          "OR NULLIF(TRIM(last_error), '') IS NOT NULL THEN 1 ELSE 0 END) AS failed "
          "FROM sync_outbox WHERE business_id = ? "
          "AND state IN ('pending','inflight','failed','conflict')",
          variables: [Variable<String>(businessId)],
        )
        .getSingle();
    final failed = uploads.readNullable<int>('failed') ?? 0;
    if (failed > 0) issues.add('$failed upload(s) need attention');
    await LocalJobRetirement.ensureSchema(_database);
    final retirements = await _database
        .customSelect(
          "SELECT state,last_error FROM local_job_retirement_requests WHERE business_id=? AND state IN ('pending','rejected')",
          variables: [Variable<String>(businessId)],
        )
        .get();
    final pendingRetirements = retirements
        .where((row) => row.read<String>('state') == 'pending')
        .length;
    for (final row in retirements) {
      issues.add(
        row.readNullable<String>('last_error') ??
            (row.read<String>('state') == 'pending'
                ? 'Job deletion awaiting server confirmation'
                : 'Job deletion rejected; refresh and review'),
      );
    }
    final held = await _database
        .customSelect(
          "SELECT COUNT(*) AS n FROM sync_outbox WHERE business_id=? AND state='retirement_quarantine'",
          variables: [Variable<String>(businessId)],
        )
        .getSingle();
    if (held.read<int>('n') > 0) {
      issues.add(
        '${held.read<int>('n')} preserved operation(s) require review after Job deletion',
      );
    }
    final scopeExists = await _database.customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='local_job_deletion_v3_scope'").get();
    if (scopeExists.isNotEmpty) {
      final scopes = await _database.customSelect(
        'SELECT state FROM local_job_deletion_v3_scope WHERE business_id=?',
        variables: [Variable<String>(businessId)]).get();
      if (scopes.any((row) => row.read<String>('state') == 'authorized_reconciliation_required')) {
        issues.add('Some saved offline work is hidden until its original account access is verified.');
      }
    }
    var pendingV3 = 0;
    final v3Exists = await _database.customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='local_job_deletion_v3_requests'").get();
    if (v3Exists.isNotEmpty) {
      final requests = await _database.customSelect(
        "SELECT state,last_error FROM local_job_deletion_v3_requests WHERE business_id=? AND state IN ('queued','pending','purging','rejected')",
        variables: [Variable<String>(businessId)]).get();
      for (final row in requests) {
        final state = row.read<String>('state');
        if (state != 'rejected') pendingV3++;
        issues.add(switch (state) {
          'purging' => 'Job deletion accepted; attachment or device cleanup pending',
          'rejected' => row.readNullable<String>('last_error') ?? 'Job deletion requires renewed review',
          _ => 'Job deletion awaiting verified server confirmation',
        });
      }
    }
    final cleanupExists = await _database.customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='local_job_deletion_v3_cleanup'").get();
    if (cleanupExists.isNotEmpty) {
      final cleanup = await _database.customSelect(
        "SELECT COUNT(*) AS n FROM local_job_deletion_v3_cleanup WHERE business_id=? AND state<>'complete'",
        variables: [Variable<String>(businessId)]).getSingle();
      if (cleanup.read<int>('n') > 0) {
        issues.add('${cleanup.read<int>('n')} deleted Job cleanup(s) still need completion or review');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final manualFailures =
        _manualFailures[businessId] ??
        prefs.getStringList(_failureKey(businessId)) ??
        const <String>[];
    if (manualFailures.isNotEmpty) {
      issues.add(
        'Last manual refresh incomplete: ${manualFailures.join(', ')}',
      );
    }
    return LocalSyncStatusSnapshot(
      lastSuccessfulPull: latest,
      issues: List<String>.unmodifiable(issues),
      pendingUploads: uploads.read<int>('pending') + pendingRetirements + pendingV3,
    );
  }
}
