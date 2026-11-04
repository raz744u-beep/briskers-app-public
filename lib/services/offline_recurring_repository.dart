import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';

typedef RecurringRow = Map<String, dynamic>;

/// Runs INSIDE the same SQLite transaction as occurrence/schedule changes.
/// The adapter must use [database] for expense-cache and totals writes. Do not
/// perform network calls or write files here: those cannot roll back with SQLite.
typedef RecurringProjection = Future<void> Function(
  BriskersLocalDatabase database,
  RecurringRow? before,
  RecurringRow after,
);

/// Independently integratable recurrence engine. No network, timers, global
/// singleton or generic financial_create operations. All IDs are caller-owned;
/// use server UUIDs for downloaded schedules and fresh UUIDs for new schedules.
class OfflineRecurringRepository {
  OfflineRecurringRepository({
    required this.database,
    required this.businessId,
    required this.userId,
    required this.currentUserId,
    required this.canRead,
    required this.canWrite,
    required this.projectOccurrence,
  });

  final BriskersLocalDatabase database;
  final String businessId;
  final String userId;
  final String? Function() currentUserId;
  final bool Function() canRead;
  final bool Function() canWrite;
  final RecurringProjection projectOccurrence;

  void _authorize({bool write = false}) {
    if (businessId.isEmpty || userId.isEmpty || currentUserId() != userId ||
        !canRead() || (write && !canWrite())) {
      throw StateError('Recurring transaction authorization is unavailable.');
    }
  }

  Future<T> _atomic<T>(Future<T> Function() action, {bool write = false}) async {
    _authorize(write: write);
    return database.transaction(() async {
      await database.customStatement('''
        CREATE TABLE IF NOT EXISTS offline_recurring_v1 (
          business_id TEXT NOT NULL,
          user_id TEXT NOT NULL,
          kind TEXT NOT NULL CHECK(kind IN ('rule','occurrence')),
          entity_key TEXT NOT NULL,
          payload TEXT NOT NULL,
          revision INTEGER NOT NULL,
          state TEXT NOT NULL CHECK(state IN ('synced','pending','conflict')),
          server_payload TEXT,
          PRIMARY KEY (business_id, user_id, kind, entity_key)
        )
      ''');
      final result = await action();
      // A logout or permission change during an awaited projection rolls back
      // the ledger, generated expense, and next-date advance together.
      _authorize(write: write);
      return result;
    });
  }

  Future<List<RecurringRow>> _rows(String kind) async {
    final rows = await database.customSelect('''
      SELECT entity_key, payload, revision, state, server_payload
      FROM offline_recurring_v1
      WHERE business_id = ? AND user_id = ? AND kind = ?
      ORDER BY entity_key
    ''', variables: [
      Variable<String>(businessId), Variable<String>(userId),
      Variable<String>(kind),
    ]).get();
    return rows.map((row) => <String, dynamic>{
      ...Map<String, dynamic>.from(jsonDecode(row.read<String>('payload')) as Map),
      '_key': row.read<String>('entity_key'),
      '_revision': row.read<int>('revision'),
      '_state': row.read<String>('state'),
      if (row.readNullable<String>('server_payload') != null)
        '_server': jsonDecode(row.read<String>('server_payload')),
    }).toList();
  }

  static RecurringRow _payload(RecurringRow row) => {
    for (final entry in row.entries)
      if (!entry.key.startsWith('_')) entry.key: entry.value,
  };

  Future<void> _put(String kind, String key, RecurringRow row,
      int revision, String state, {RecurringRow? server}) async {
    await database.customStatement('''
      INSERT INTO offline_recurring_v1
        (business_id,user_id,kind,entity_key,payload,revision,state,server_payload)
      VALUES (?,?,?,?,?,?,?,?)
      ON CONFLICT(business_id,user_id,kind,entity_key) DO UPDATE SET
        payload=excluded.payload, revision=excluded.revision,
        state=excluded.state, server_payload=excluded.server_payload
    ''', [businessId, userId, kind, key, jsonEncode(_payload(row)), revision,
      state, server == null ? null : jsonEncode(_payload(server))]);
  }

  static DateTime day(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw FormatException('Expected a calendar date', value);
    }
    final parsed = DateTime.tryParse('${value}T00:00:00Z');
    if (parsed == null || dateText(parsed) != value) {
      throw FormatException('Invalid calendar date', value);
    }
    return parsed;
  }

  static String dateText(DateTime value) =>
      value.toIso8601String().substring(0, 10);

  /// Matches PostgreSQL recurring_next_date: month/year arithmetic clamps to
  /// the last day of the target month; subsequent steps start from that date.
  static String nextDate(String value, String frequency, int interval) {
    if (interval < 1 || interval > 1000) {
      throw ArgumentError.value(interval, 'interval');
    }
    final date = day(value);
    if (frequency == 'daily' || frequency == 'weekly') {
      return dateText(date.add(Duration(
        days: interval * (frequency == 'weekly' ? 7 : 1),
      )));
    }
    if (frequency != 'monthly' && frequency != 'yearly') {
      throw ArgumentError.value(frequency, 'frequency');
    }
    final first = DateTime.utc(date.year,
        date.month + interval * (frequency == 'yearly' ? 12 : 1));
    final lastDay = DateTime.utc(first.year, first.month + 1, 0).day;
    return dateText(DateTime.utc(first.year, first.month,
        date.day > lastDay ? lastDay : date.day));
  }

  void _validate(RecurringRow row, {required bool rule}) {
    if (row['business_id'] != businessId ||
        row['id'] is! String || (row['id'] as String).isEmpty ||
        !const ['expense', 'income'].contains(row['direction']) ||
        row['amount_minor'] is! int || (row['amount_minor'] as int) <= 0 ||
        row['account_id'] is! String || (row['account_id'] as String).isEmpty ||
        row['category_id'] is! String || (row['category_id'] as String).isEmpty) {
      throw ArgumentError('Invalid scoped recurring record.');
    }
    if (rule) {
      if (row['interval_count'] is! int || row['is_repeating'] is! bool) {
        throw ArgumentError('Missing recurrence interval or active state.');
      }
      nextDate(row['next_date'] as String, row['frequency'] as String,
          row['interval_count'] as int);
      if (row['end_date'] != null) day(row['end_date'] as String);
    } else {
      if (row['recurring_rule_id'] is! String ||
          (row['recurring_rule_id'] as String).isEmpty) {
        throw ArgumentError('Missing occurrence schedule identity.');
      }
      day(row['recurring_occurrence_date'] as String);
      day(row['date'] as String);
    }
  }

  static String occurrenceKey(String ruleId, String dueDate) =>
      jsonEncode([ruleId, dueDate]);

  static String _key(RecurringRow row, bool rule) => rule
      ? row['id'] as String
      : occurrenceKey(row['recurring_rule_id'] as String,
          row['recurring_occurrence_date'] as String);

  Future<List<RecurringRow>> rules() => _atomic(() => _rows('rule'));
  Future<List<RecurringRow>> occurrences() => _atomic(() => _rows('occurrence'));

  /// Includes stopped rules. Callers send base row_version and _revision;
  /// never send these operations through the manual-expense creation endpoint.
  Future<List<RecurringRow>> pending() => _atomic(() async => [
    for (final kind in ['rule', 'occurrence'])
      for (final row in await _rows(kind))
        if (row['_state'] != 'synced') {...row, '_kind': kind},
  ]);

  /// Create, edit, or stop a rule. Persisted offline edits are never erased by
  /// a later snapshot. Existing occurrence amounts/receipts remain unchanged.
  Future<void> saveRule(RecurringRow rule) => _atomic(() async {
    _validate(rule, rule: true);
    final old = (await _rows('rule')).where((r) => r['id'] == rule['id']);
    final previous = old.isEmpty ? null : old.single;
    if (previous?['_state'] == 'conflict') {
      throw StateError('Resolve the schedule conflict before editing.');
    }
    await _put('rule', rule['id'] as String, {
      ...rule,
      // Keep the downloaded base revision, not a caller-supplied revision.
      'row_version': previous?['row_version'],
    }, (previous?['_revision'] as int? ?? 0) + 1, 'pending');
  }, write: true);

  /// Import an authenticated complete snapshot, including inactive rules and
  /// posted occurrences. The adapter must fetch all pages before calling this.
  /// Absence is NEVER deletion; no network writes happen during recovery.
  Future<void> importSnapshot({
    required List<RecurringRow> rules,
    required List<RecurringRow> occurrences,
  }) => _atomic(() async {
    for (final group in [(true, rules), (false, occurrences)]) {
      final isRule = group.$1;
      final kind = isRule ? 'rule' : 'occurrence';
      final saved = {for (final row in await _rows(kind)) row['_key']: row};
      final seen = <String>{};
      for (final incoming in group.$2) {
        _validate(incoming, rule: isRule);
        if (incoming['row_version'] is! int ||
            (incoming['row_version'] as int) < 0) {
          throw ArgumentError('Recovery requires the server row version.');
        }
        final key = _key(incoming, isRule);
        if (!seen.add(key)) throw StateError('Duplicate recovery identity.');
        final old = saved[key];
        if (!isRule && old != null && old['_state'] == 'synced' &&
            old['id'] != incoming['id']) {
          throw StateError('Server identity changed for a stored occurrence.');
        }
        if (old != null && old['_state'] != 'synced') {
          // Explicit acknowledgement handles in-flight edits. A download alone
          // is never proof that this device's pending write was accepted.
          await _put(kind, key, old, old['_revision'] as int,
              old['row_version'] == incoming['row_version']
                  ? old['_state'] as String : 'conflict', server: incoming);
          continue;
        }
        if (old != null && (old['row_version'] as int? ?? -1) >
            (incoming['row_version'] as int)) {
          continue;
        }
        final merged = {...incoming,
          if (!isRule && old?['attachments'] != null)
            'attachments': old!['attachments'],
        };
        await _put(kind, key, merged,
            (old?['_revision'] as int? ?? 0) + 1, 'synced');
        if (!isRule) await projectOccurrence(database, old, merged);
      }
    }
  });

  /// One commit for generated expenses, their pending identities, and cursors.
  /// Bounded catch-up allows another call for very old schedules; no dates are
  /// skipped. Pass the SHOP'S calendar date, not UTC or a travelling phone date.
  Future<int> generateThrough(String throughDate, {int limit = 100}) =>
      _atomic(() async {
    day(throughDate);
    if (limit < 1 || limit > 1000) throw ArgumentError.value(limit, 'limit');
    var generated = 0;
    var visited = 0;
    final all = {for (final row in await _rows('occurrence')) row['_key']: row};
    for (final rule in await _rows('rule')) {
      if (rule['_state'] == 'conflict' || rule['is_repeating'] != true ||
          (rule['paused_reason']?.toString().isNotEmpty ?? false)) {
        continue;
      }
      final latest = all.values.where((r) =>
          r['recurring_rule_id'] == rule['id'] &&
          r['direction'] == rule['direction']).toList()
        ..sort((a, b) => (b['recurring_occurrence_date'] as String)
            .compareTo(a['recurring_occurrence_date'] as String));
      // A disputed corrected amount must not silently propagate to new dates.
      if (latest.isNotEmpty && latest.first['_state'] == 'conflict') continue;
      final amount = latest.isEmpty
          ? rule['amount_minor'] : latest.first['amount_minor'];
      var due = rule['next_date'] as String;
      var advanced = false;
      while (due.compareTo(throughDate) <= 0 && visited < limit &&
          (rule['end_date'] == null || due.compareTo(rule['end_date'] as String) <= 0)) {
        visited++;
        final key = occurrenceKey(rule['id'] as String, due);
        if (!all.containsKey(key)) {
          final row = <String, dynamic>{
            'id': 'local-recurring-${Uri.encodeComponent(businessId)}-'
                '${Uri.encodeComponent(rule['id'] as String)}-$due',
            'business_id': businessId,
            'recurring_rule_id': rule['id'],
            'recurring_occurrence_date': due,
            'date': due,
            'direction': rule['direction'],
            'account_id': rule['account_id'],
            'category_id': rule['category_id'],
            'vendor_id': rule['vendor_id'],
            'counterparty': rule['counterparty'],
            'account': rule['account'],
            'category': rule['category'],
            'remarks': rule['remarks'] ?? '',
            'amount_minor': amount,
            'row_version': null,
            'attachments': <dynamic>[],
          };
          await _put('occurrence', key, row, 1, 'pending');
          await projectOccurrence(database, null, row);
          all[key] = row;
          generated++;
        }
        due = nextDate(due, rule['frequency'] as String,
            rule['interval_count'] as int);
        advanced = true;
      }
      final ended = rule['end_date'] != null &&
          due.compareTo(rule['end_date'] as String) > 0;
      if (advanced || ended) {
        await _put('rule', rule['id'] as String, {
          ...rule, 'next_date': due, 'amount_minor': amount,
          if (ended) 'is_repeating': false,
        }, (rule['_revision'] as int) + 1, 'pending');
      }
      if (visited >= limit) break;
    }
    return generated;
  }, write: true);

  /// Correct an occurrence without changing its schedule/date identity. Future
  /// generation inherits the latest amount. Original images remain local.
  Future<void> correctAmount(String ruleId, String dueDate, int amountMinor) =>
      _atomic(() async {
    if (amountMinor <= 0) throw ArgumentError.value(amountMinor, 'amountMinor');
    final key = occurrenceKey(ruleId, dueDate);
    final matches = (await _rows('occurrence')).where((r) => r['_key'] == key);
    if (matches.isEmpty) throw StateError('Occurrence is not stored locally.');
    final old = matches.single;
    if (old['_state'] == 'conflict') throw StateError('Occurrence has a conflict.');
    final updated = {...old, 'amount_minor': amountMinor};
    await _put('occurrence', key, updated, (old['_revision'] as int) + 1, 'pending');
    await projectOccurrence(database, old, updated);
  }, write: true);

  /// Call only after a server CAS/idempotent write returns the canonical row.
  /// A changed local revision rejects a stale acknowledgement; retry/refetch.
  /// Occurrence adapter must also remap receipt/cache IDs atomically here.
  Future<bool> acknowledge({required bool rule, required String key,
    required int revision, required RecurringRow canonical}) => _atomic(() async {
    _validate(canonical, rule: rule);
    if (_key(canonical, rule) != key || canonical['row_version'] is! int) {
      throw StateError('Acknowledgement identity/version mismatch.');
    }
    final kind = rule ? 'rule' : 'occurrence';
    final matches = (await _rows(kind)).where((r) => r['_key'] == key);
    if (matches.isEmpty || matches.single['_revision'] != revision) return false;
    final old = matches.single;
    final fields = rule
        ? ['direction', 'account_id', 'category_id', 'vendor_id', 'amount_minor',
            'frequency', 'interval_count', 'next_date', 'end_date', 'is_repeating']
        : ['direction', 'account_id', 'category_id', 'vendor_id', 'amount_minor', 'date'];
    if (fields.any((field) => old[field] != canonical[field]) ||
        (old['remarks'] ?? '') != (canonical['remarks'] ?? '')) {
      // A uniqueness hit is not permission to discard a corrected amount.
      await _put(kind, key, old, revision, 'conflict', server: canonical);
      return false;
    }
    final merged = {...canonical,
      if (!rule && old['attachments'] != null) 'attachments': old['attachments'],
    };
    await _put(kind, key, merged, revision + 1, 'synced');
    if (!rule) await projectOccurrence(database, old, merged);
    return true;
  }, write: true);
}
