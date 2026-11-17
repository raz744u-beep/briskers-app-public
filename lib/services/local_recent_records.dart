import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum RecentRecordKind { customer, job, invoice, estimate }

typedef RecentRecord = ({RecentRecordKind kind, String id, String label});

class LocalRecentRecords {
  const LocalRecentRecords(this.business, this.user);

  final String business, user;
  static Future<void> _writes = Future<void>.value();
  static final _changes = StreamController<(String, String)>.broadcast();
  static Stream<(String, String)> get changes => _changes.stream;

  String get _key =>
      'briskers_recent_records_v1_${jsonEncode([business, user])}';

  List<RecentRecord> _read(SharedPreferences prefs) {
    return [
      for (final raw in prefs.getStringList(_key) ?? const [])
        if (_parse(raw) case final RecentRecord record) record,
    ];
  }

  RecentRecord? _parse(String raw) {
    try {
      final values = List<String>.from(jsonDecode(raw) as List);
      if (values.length != 3 || values[1].isEmpty) return null;
      return (
        kind: RecentRecordKind.values.byName(values[0]),
        id: values[1],
        label: values[2],
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<RecentRecord>> load() async =>
      _read(await SharedPreferences.getInstance()).take(10).toList();

  Future<void> _update(Future<bool> Function(SharedPreferences) save) {
    final work = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await save(prefs)) {
        throw StateError('Could not save Recently Viewed.');
      }
      _changes.add((business, user));
    });
    _writes = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }

  Future<void> record(RecentRecord record) => _update((prefs) {
    final entries = [
      record,
      ..._read(
        prefs,
      ).where((saved) => saved.kind != record.kind || saved.id != record.id),
    ];
    return prefs.setStringList(_key, [
      for (final item in entries.take(10))
        jsonEncode([item.kind.name, item.id, item.label]),
    ]);
  });

  Future<void> clear() => _update((prefs) => prefs.remove(_key));
}
