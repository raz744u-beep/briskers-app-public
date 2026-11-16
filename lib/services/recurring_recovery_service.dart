import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'local_financial_cache.dart';
import 'offline_recurring_repository.dart';

typedef RecurringSnapshotReader = Future<Map<String, dynamic>> Function(String businessId);

/// Explicit download only. Inject an authenticated read-only RPC client; this
/// service never changes connection mode, flushes an outbox, or generates dues.
class RecurringRecoveryService {
  RecurringRecoveryService({required this.repository, required this.database,
    required this.readSnapshot, required this.currentUserId,
    required this.canRead});

  final OfflineRecurringRepository repository;
  final BriskersLocalDatabase database;
  final RecurringSnapshotReader readSnapshot;
  final String? Function() currentUserId;
  final bool Function() canRead;

  void _authorize() {
    if (currentUserId() != repository.userId || !canRead()) {
      throw StateError('Account or recurring permissions changed during recovery.');
    }
  }

  Future<({int schedules, int occurrences})> download() async {
    _authorize();
    final snapshot = await readSnapshot(repository.businessId);
    _authorize();
    if (snapshot['schema_version'] != 1 || snapshot['complete'] != true ||
        snapshot['business_id'] != repository.businessId ||
        snapshot['rules'] is! List || snapshot['occurrences'] is! List ||
        snapshot['options'] is! Map) {
      throw StateError('Incomplete or mismatched recurring recovery response.');
    }
    final rules = [for (final row in snapshot['rules'] as List)
      Map<String, dynamic>.from(row as Map)];
    final occurrences = [for (final row in snapshot['occurrences'] as List)
      Map<String, dynamic>.from(row as Map)];
    if (snapshot['rule_count'] != rules.length ||
        snapshot['occurrence_count'] != occurrences.length) {
      throw StateError('Recurring recovery was truncated.');
    }
    final options = Map<String, dynamic>.from(snapshot['options'] as Map);
    await database.transaction(() async {
      _authorize();
      await repository.importSnapshot(rules: rules, occurrences: occurrences);
      // Merge named references by ID. Never overwrite a pending local option.
      final cache = LocalFinancialCache(database: database);
      final old = await cache.loadOptions(repository.businessId);
      final merged = <String, dynamic>{...old};
      for (final entry in options.entries) {
        if (entry.value is! List) continue;
        final byId = <String, Map<String, dynamic>>{};
        for (final raw in (old[entry.key] as List? ?? const [])) {
          if (raw is Map && raw['id'] is String) {
            byId[raw['id'] as String] = Map<String, dynamic>.from(raw);
          }
        }
        for (final raw in entry.value as List) {
          if (raw is! Map || raw['id'] is! String ||
              (raw['business_id'] != null && raw['business_id'] != repository.businessId)) {
            throw StateError('Invalid recovery reference.');
          }
          final id = raw['id'] as String;
          if (byId[id]?['sync_state'] == 'pending') continue;
          byId[id] = Map<String, dynamic>.from(raw);
        }
        merged[entry.key] = byId.values.toList();
      }
      await cache.saveOptions(repository.businessId, merged);
      _authorize();
    });
    return (schedules: rules.length, occurrences: occurrences.length);
  }
}
