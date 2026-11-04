import 'dart:math';

import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'offline_recurring_repository.dart';

typedef RecurringBundleWriter = Future<Map<String, dynamic>> Function(
  String businessId, String operationId, RecurringRow rule,
  List<RecurringRow> occurrences,
);

class RecurringSyncService {
  RecurringSyncService({required this.database, required this.repository,
    required this.writeBundle, required this.synchronizationAllowed});
  final BriskersLocalDatabase database;
  final OfflineRecurringRepository repository;
  final RecurringBundleWriter writeBundle;
  final bool Function() synchronizationAllowed;
  final _random = Random.secure();

  void _networkAllowed() {
    if (!synchronizationAllowed()) {
      throw StateError('Recurring synchronization is disabled in Force Offline.');
    }
  }

  static RecurringRow _wire(RecurringRow row) => {
    for (final key in ['id','business_id','direction','account_id','category_id',
      'vendor_id','amount_minor','frequency','interval_count','next_date','end_date',
      'is_repeating','remarks','row_version','recurring_rule_id',
      'recurring_occurrence_date','date'])
      if (row.containsKey(key)) key: row[key],
  };

  /// Only this explicit service uploads recurrence operations. The server
  /// commits the schedule AND all outstanding occurrences as a single bundle.
  Future<int> flush() async {
    _networkAllowed();
    final rules = await repository.rules();
    final occurrences = await repository.occurrences();
    var acknowledged = 0;
    for (final rule in rules) {
      final pending = occurrences.where((row) =>
        row['recurring_rule_id'] == rule['id'] && row['_state'] != 'synced').toList();
      if (rule['_state'] == 'conflict' || pending.any((r) => r['_state'] == 'conflict')) {
        continue;
      }
      if (rule['_state'] == 'synced' && pending.isEmpty) continue;
      if (pending.length > 1000) {
        throw StateError('Too many unacknowledged occurrences for one atomic bundle.');
      }
      _networkAllowed();
      // Financial occurrence uniqueness remains the cross-device retry key.
      // This request token additionally protects network retries of one bundle.
      final operationId = List.generate(32, (_) => _random.nextInt(16).toRadixString(16)).join();
      final response = await writeBundle(repository.businessId, operationId,
        _wire(rule), pending.map(_wire).toList());
      _networkAllowed();
      if (response['business_id'] != repository.businessId ||
          response['rule'] is! Map || response['occurrences'] is! List) {
        throw StateError('Invalid recurring synchronization response.');
      }
      final canonicalRule = Map<String, dynamic>.from(response['rule'] as Map);
      if (canonicalRule['id'] != rule['id']) throw StateError('Server returned another schedule.');
      final canonical = <String, RecurringRow>{};
      for (final raw in response['occurrences'] as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final key = OfflineRecurringRepository.occurrenceKey(
          row['recurring_rule_id'] as String, row['recurring_occurrence_date'] as String);
        if (canonical.containsKey(key)) throw StateError('Duplicate server acknowledgement.');
        canonical[key] = row;
      }
      if (canonical.length != pending.length ||
          pending.any((row) => !canonical.containsKey(row['_key']))) {
        throw StateError('Server acknowledgement was incomplete.');
      }
      await database.transaction(() async {
        _networkAllowed();
        for (final row in pending) {
          final key = row['_key'] as String;
          if (await repository.acknowledge(rule: false, key: key,
              revision: row['_revision'] as int, canonical: canonical[key]!)) {
            acknowledged++;
          }
        }
        await repository.acknowledge(rule: true, key: rule['id'] as String,
          revision: rule['_revision'] as int, canonical: canonicalRule);
        _networkAllowed();
      });
    }
    return acknowledged;
  }
}
