import 'dart:async';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_job_quarantine.dart';

/// Invalidates retained summaries as soon as a durable revocation is observed.
/// A load started before that event must not publish its result, even if the
/// separately fetched cleanup tombstones fail. Fresh reads consult the durable
/// block list; this class never restores archived work or authorizes a Job.
class JobSummaryVisibility {
  JobSummaryVisibility({
    required this.businessId,
    required void Function(Set<String> jobIds) onQuarantine,
    BriskersLocalDatabase? database,
  }) : _database = database ?? localDatabase {
    _subscription = LocalJobQuarantine.events.listen((event) {
      if (_disposed || event.businessId != businessId) return;
      _epoch++;
      onQuarantine(event.jobIds);
    });
  }

  final String businessId;
  final BriskersLocalDatabase _database;
  late final StreamSubscription<({String businessId, Set<String> jobIds})>
      _subscription;
  int _epoch = 0;
  bool _disposed = false;

  int get epoch => _epoch;

  int beginLoad() => ++_epoch;

  bool isCurrent(int epoch) => !_disposed && epoch == _epoch;

  Future<Set<String>> blockedJobIds() =>
      LocalJobQuarantine.blockedJobIds(_database, businessId);

  Future<int> captureSnapshotGeneration() =>
      LocalJobQuarantine.captureGeneration(_database, businessId);

  static const _snapshotGenerationKey = '_job_quarantine_generation';

  static List<Map<String, dynamic>> stampSnapshot(
    Iterable<Map<String, dynamic>> rows, int generation,
  ) => rows.map((row) => <String, dynamic>{
      ...row, _snapshotGenerationKey: generation,
    }).toList();

  Future<List<Map<String, dynamic>>> filter(
    Iterable<Map<String, dynamic>> rows, {
    String jobIdKey = 'id',
    bool cached = false,
  }) async {
    final blocked = await blockedJobIds();
    final generations = cached
        ? await LocalJobQuarantine.quarantineGenerations(_database, businessId)
        : const <String, int>{};
    return rows.where((row) {
      final id = row[jobIdKey]?.toString();
      return !blocked.contains(id) &&
          (!cached || _snapshotIsCurrent(row, generations[id]));
    }).toList();
  }

  Future<List<Map<String, dynamic>>> filterFindings(
    Iterable<Map<String, dynamic>> rows, {bool cached = false},
  ) async {
    final blockedJobs = await blockedJobIds();
    final blockedFindings = await LocalJobQuarantine.blockedEntityIds(
        _database, businessId, entityType: 'local_findings');
    final jobGenerations = cached
        ? await LocalJobQuarantine.quarantineGenerations(_database, businessId)
        : const <String, int>{};
    final findingGenerations = cached
        ? await LocalJobQuarantine.entityQuarantineGenerations(
            _database, businessId, entityType: 'local_findings')
        : const <String, int>{};
    return rows.where((row) {
      final id = row['id']?.toString();
      if (blockedFindings.contains(id) ||
          (cached && !_snapshotIsCurrent(row, findingGenerations[id]))) {
        return false;
      }
      for (final key in const ['job_id', 'found_job_id', 'repair_job_id']) {
        final jobId = row[key]?.toString();
        if (blockedJobs.contains(jobId) ||
            (cached && !_snapshotIsCurrent(row, jobGenerations[jobId]))) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  static bool _snapshotIsCurrent(Map<String, dynamic> row, int? quarantine) =>
      quarantine == null ||
      (int.tryParse(row[_snapshotGenerationKey]?.toString() ?? '') ?? 0) >=
          quarantine;

  static List<Map<String, dynamic>> withoutJobs(
    Iterable<Map<String, dynamic>> rows,
    Set<String> jobIds, {
    String jobIdKey = 'id',
  }) => rows.where((row) => !jobIds.contains(row[jobIdKey]?.toString())).toList();

  void dispose() {
    _disposed = true;
    _epoch++;
    unawaited(_subscription.cancel());
  }
}
