import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Device-local inbox, scoped to the authenticated user and shop. Customer IDs
/// are stable creation-event IDs: updates and repeated imports cannot re-alert.
/// Reading a badge never consumes it; only explicitly reviewed IDs are read.
class CustomerNotificationService {
  CustomerNotificationService({
    required this.businessId,
    required this.userId,
    BriskersLocalDatabase? database,
    DateTime Function()? now,
  }) : _database = database ?? localDatabase,
       _now = now ?? DateTime.now;

  final String businessId;
  final String userId;
  final BriskersLocalDatabase _database;
  final DateTime Function() _now;
  static Future<void> _writes = Future<void>.value();
  static final _changes = StreamController<String>.broadcast();
  static Stream<String> get changes => _changes.stream;

  String get _key => 'briskers_customer_inbox_v1_${businessId}_$userId';

  // Refresh and review can race with sync or navigation. Serialize the whole
  // read/modify/write so one operation cannot resurrect a reviewed event.
  Future<T> _serialized<T>(Future<T> Function() work) {
    final result = _writes.then((_) => work());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Map<String, dynamic>?> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    // Fail closed if storage is corrupt; don't silently erase unread state.
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> _save(
    SharedPreferences prefs,
    Map<String, dynamic> state,
  ) async {
    if (!await prefs.setString(_key, jsonEncode(state))) {
      throw StateError('Could not save customer review state.');
    }
  }

  Future<List<String>> unreadCustomerIds() => _serialized(() async {
    if (userId.isEmpty || businessId.isEmpty) return const <String>[];
    // Read the completion marker and rows in one SQLite snapshot. A bootstrap
    // committing between two independent reads could otherwise look incremental.
    final (bootstrap, rows) = await _database.transaction(() async {
      final bootstrap = await _database
          .customSelect(
            "SELECT s.bootstrapped, b.last_server_cursor AS baseline_revision "
            "FROM local_sync_states s LEFT JOIN local_sync_states b "
            "ON b.business_id=s.business_id AND b.scope='customer_notification_baseline' "
            "WHERE s.business_id=? AND s.scope='customers_vehicles'",
            variables: [Variable<String>(businessId)],
          )
          .getSingleOrNull();
      final rows = await _database
          .customSelect(
            'SELECT id,created_at,sync_state FROM local_customers WHERE business_id=?',
            variables: [Variable<String>(businessId)],
          )
          .get();
      return (bootstrap, rows);
    });
    final prefs = await SharedPreferences.getInstance();
    var state = await _read(prefs);
    final present = rows.map((row) => row.read<String>('id')).toSet();
    // A partial bootstrap is not a new baseline or evidence of new arrivals.
    // Previously unread records that remain available still retain their badge.
    if (bootstrap?.read<int>('bootstrapped') != 1) {
      if (state == null) return const <String>[];
      final read = Set<String>.from(state['read_ids'] as List);
      return List<String>.from(state['event_ids'] as List)
          .where((id) => !read.contains(id) && present.contains(id))
          .toList();
    }
    if (state == null) {
      // Existing data is the baseline, never a burst of imported notifications.
      state = {
        'started_at': _now().toUtc().millisecondsSinceEpoch ~/ 1000,
        'baseline_revision': bootstrap?.readNullable<int>('baseline_revision'),
        'known_ids': present.toList(),
        'event_ids': <String>[],
        'read_ids': <String>[],
      };
      await _save(prefs, state);
      return const <String>[];
    }

    final known = Set<String>.from(state['known_ids'] as List);
    final events = Set<String>.from(state['event_ids'] as List);
    final read = Set<String>.from(state['read_ids'] as List);
    final started = state['started_at'] as int;
    final revision = bootstrap?.readNullable<int>('baseline_revision');
    final rebuiltBaseline = state['baseline_revision'] != revision;
    var changed = rebuiltBaseline;
    for (final row in rows) {
      final id = row.read<String>('id');
      if (!known.add(id)) continue;
      changed = true;
      final created = row.readNullable<int>('created_at');
      // A newly downloaded old record (or a record with no creation evidence)
      // is not a new arrival. Never use the import/download/update time here.
      if (!rebuiltBaseline &&
          !id.startsWith('local-') &&
          row.read<String>('sync_state') == 'synced' &&
          created != null &&
          created >= started) {
        events.add(id);
      }
    }
    if (changed) {
      state['baseline_revision'] = revision;
      state['known_ids'] = known.toList();
      state['event_ids'] = events.toList();
      await _save(prefs, state);
    }
    // Revoked/deleted records must never remain accessible through the inbox.
    // Retain their event/read IDs so a restored import cannot notify twice.
    return events
        .where((id) => !read.contains(id) && present.contains(id))
        .toList();
  });

  Future<void> markReviewed(Iterable<String> customerIds) =>
      _serialized(() async {
        if (userId.isEmpty || businessId.isEmpty) return;
        final prefs = await SharedPreferences.getInstance();
        final state = await _read(prefs);
        if (state == null) return;
        final events = Set<String>.from(state['event_ids'] as List);
        final read = Set<String>.from(state['read_ids'] as List);
        read.addAll(customerIds.where(events.contains));
        state['read_ids'] = read.toList();
        await _save(prefs, state);
        _changes.add(businessId);
      });
}
