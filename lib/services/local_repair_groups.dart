import 'dart:math';
import 'package:drift/drift.dart';
import '../core/repair_group.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_document_detail_cache.dart';

class LocalRepairGroups {
  LocalRepairGroups({BriskersLocalDatabase? database, LocalDocumentDetailCache? cache})
    : db = database ?? localDatabase,
      cache = cache ?? LocalDocumentDetailCache(database: database);
  final BriskersLocalDatabase db;
  final LocalDocumentDetailCache cache;
  static final _random = Random.secure();
  static String newId() => List.generate(24, (_) => _random.nextInt(256)
    .toRadixString(16).padLeft(2, '0')).join();
  List<Variable<String>> _vars(String business, String estimate) =>
    [Variable(business), Variable(estimate)];

  Future<Map<String, dynamic>> _editable(String business, String estimate) async {
    if (business.isEmpty || estimate.isEmpty) { throw ArgumentError('Missing document scope.'); }
    final detail = await cache.load(business, estimate);
    if (detail == null || detail['kind'] != 'estimate' || detail['converted'] == true ||
        (detail['business_id'] != null && detail['business_id'] != business)) {
      throw StateError('Select an editable saved estimate.');
    }
    final canonical = detail['_server_document_id'] ?? detail['id'];
    if (canonical != estimate) {
      throw StateError('Reopen the estimate after it finishes syncing.');
    }
    return detail;
  }

  Future<List<RepairGroup>> groups(String business, String estimate,
      Map<String, dynamic> detail) => db.transaction(() async {
    final rows = await db.customSelect('SELECT * FROM repair_groups_v1 WHERE business=? AND estimate=? ORDER BY position,id',
      variables: _vars(business, estimate)).get();
    final members = await db.customSelect('SELECT line,group_id FROM repair_group_members_v1 WHERE business=? AND estimate=?',
      variables: _vars(business, estimate)).get();
    final membership = {for (final row in members) row.read<String>('line'): row.read<String>('group_id')};
    final ids = rows.map((row) => row.read<String>('id')).toSet();
    final lines = (detail['lines'] as List? ?? const []).whereType<Map>()
      .map((line) => Map<String, dynamic>.from(line)).where((line) => !RepairGroup.isGeneralCharge(line)).toList();
    return [
      for (final row in rows) RepairGroup(id: row.read<String>('id'), name: row.read<String>('name'),
        description: row.read<String>('description'),
        lines: lines.where((line) => membership[line['id']] == row.read<String>('id')).toList()),
      RepairGroup(id: RepairGroup.otherId, name: 'Other Items',
        lines: lines.where((line) => !ids.contains(membership[line['id']])).toList()),
    ];
  });

  Future<void> add(String business, String estimate, {required String name,
      required String description}) => db.transaction(() async {
    await _editable(business, estimate);
    if (name.trim().isEmpty) throw ArgumentError('Enter a repair group name.');
    await db.customStatement('''INSERT INTO repair_groups_v1
      SELECT ?,?,?,?,?,coalesce(max(position),0)+1,'[]' FROM repair_groups_v1 WHERE business=? AND estimate=?''',
      [business, estimate, newId(), name.trim(), description.trim(), business, estimate]);
  });

  Future<void> edit(String business, String estimate, String id, {required String name,
      required String description}) => db.transaction(() async {
    await _editable(business, estimate);
    if (id == RepairGroup.otherId || name.trim().isEmpty) {
      throw ArgumentError('Enter a repair group name.');
    }
    await db.customStatement('UPDATE repair_groups_v1 SET name=?,description=? WHERE business=? AND estimate=? AND id=?',
      [name.trim(), description.trim(), business, estimate, id]);
  });

  Future<void> remove(String business, String estimate, String id) => db.transaction(() async {
    await _editable(business, estimate);
    await db.customStatement('DELETE FROM repair_group_members_v1 WHERE business=? AND estimate=? AND group_id=?', [business, estimate, id]);
    await db.customStatement('DELETE FROM repair_groups_v1 WHERE business=? AND estimate=? AND id=?', [business, estimate, id]);
  });

  Future<void> reorder(String business, String estimate, List<String> ids) => db.transaction(() async {
    final detail = await _editable(business, estimate);
    final current = (await groups(business, estimate, detail)).where((group) => !group.isOther).map((group) => group.id).toSet();
    if (ids.length != current.length || ids.toSet().length != ids.length || !current.containsAll(ids)) {
      throw ArgumentError('Group order must contain each saved group once.');
    }
    for (var i = 0; i < ids.length; i++) {
      await db.customStatement('UPDATE repair_groups_v1 SET position=? WHERE business=? AND estimate=? AND id=?', [i, business, estimate, ids[i]]);
    }
  });

  /// Transfer organization when the normal estimate upload replaces local IDs.
  /// Source order and content must agree before assigning a new line identity.
  Future<void> remapDraft(
    String business, String local, String server,
    List<Map<String, dynamic>> before, List<Map<String, dynamic>> after,
  ) => db.transaction(() async {
    if (local == server) return;
    final variables = _vars(business, local);
    final existing = await db.customSelect(
      'SELECT 1 FROM repair_groups_v1 WHERE business=? AND estimate=? LIMIT 1',
      variables: variables,
    ).getSingleOrNull();
    if (existing == null) return;
    final memberRows = await db.customSelect(
      'SELECT line,group_id FROM repair_group_members_v1 WHERE business=? AND estimate=?',
      variables: variables,
    ).get();
    final active = {for (final row in before) row['id']};
    final members = memberRows.where((row) => active.contains(row.data['line']));
    final replacements = <String, String>{};
    if (members.isNotEmpty) {
      final ordered = [...after]..sort(
        (a, b) => _position(a).compareTo(_position(b)),
      );
      if (ordered.length != before.length ||
          before.any((line) => line['id'] is! String || line['id'] == '') ||
          before.map((line) => line['id']).toSet().length != before.length ||
          ordered.any((line) => _position(line) < 1) ||
          ordered.map(_position).toSet().length != ordered.length ||
          ordered.map((line) => line['id']).toSet().length != ordered.length ||
          ordered.any((line) => line['id'] is! String || line['id'] == '')) {
        throw StateError('Review estimate item identities before completing sync.');
      }
      for (var i = 0; i < before.length; i++) {
        if (!_matchingLine(before[i], ordered[i])) {
          throw StateError('Review estimate item identities before completing sync.');
        }
        replacements[before[i]['id'] as String] = ordered[i]['id'] as String;
      }
    }
    await db.customStatement(
      'UPDATE repair_groups_v1 SET estimate=? WHERE business=? AND estimate=?',
      [server, business, local],
    );
    await db.customStatement(
      'DELETE FROM repair_group_members_v1 WHERE business=? AND estimate=?',
      [business, local],
    );
    for (final row in members) {
      await db.customStatement(
        'INSERT INTO repair_group_members_v1 VALUES(?,?,?,?)',
        [business, server, replacements[row.read<String>('line')], row.read<String>('group_id')],
      );
    }
  });

  Future<void> remapLine(String business, String estimate, String local, String server) =>
      db.customStatement(
        'UPDATE repair_group_members_v1 SET line=? WHERE business=? AND estimate=? AND line=?',
        [server, business, estimate, local],
      );

  static int _position(Map<String, dynamic> line) =>
      int.tryParse('${line['position']}') ?? -1;

  static bool _matchingLine(Map<String, dynamic> first, Map<String, dynamic> second) {
    for (final field in ['name', 'line_kind', 'item_id', 'description']) {
      if ((first[field] ?? '').toString().trim() !=
          (second[field] ?? '').toString().trim()) return false;
    }
    for (final field in ['quantity', 'unit_price', 'tax_rate']) {
      if (num.tryParse('${first[field]}') != num.tryParse('${second[field]}')) return false;
    }
    return true;
  }

  Future<void> move(String business, String estimate, Set<String> lineIds, String groupId) =>
      db.transaction(() async {
    final detail = await _editable(business, estimate);
    final all = await groups(business, estimate, detail);
    final validIds = all.expand((group) => group.lines).map((line) => line['id']).toSet();
    if (!all.any((group) => group.id == groupId) || !validIds.containsAll(lineIds)) {
      throw ArgumentError('Select existing estimate items and a repair group.');
    }
    for (final lineId in lineIds) {
      if (groupId == RepairGroup.otherId) {
        await db.customStatement(
          'DELETE FROM repair_group_members_v1 WHERE business=? AND estimate=? AND line=?',
          [business, estimate, lineId],
        );
      } else {
        await db.customStatement(
          'INSERT INTO repair_group_members_v1 VALUES(?,?,?,?) '
          'ON CONFLICT(business,estimate,line) DO UPDATE SET group_id=excluded.group_id',
          [business, estimate, lineId, groupId],
        );
      }
    }
  });
}
