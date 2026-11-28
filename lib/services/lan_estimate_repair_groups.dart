import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/repair_group.dart';
import '../local/briskers_local_database.dart';
import 'repair_group_schema.dart';

class LanEstimateRepairGroups {
  const LanEstimateRepairGroups(this.db);

  final BriskersLocalDatabase db;

  Future<Map<String, Map<String, List<Object?>>>> read(String business) async {
    await RepairGroupSchema.ensure(db);
    final rows = await db
        .customSelect(
          'SELECT estimate,id,name,description,position,evidence_json FROM '
          'repair_groups_v1 WHERE business=? ORDER BY estimate,position,id',
          variables: [Variable(business)],
        )
        .get();
    final members = await db
        .customSelect(
          'SELECT estimate,line,group_id FROM repair_group_members_v1 '
          'WHERE business=? ORDER BY estimate,line',
          variables: [Variable(business)],
        )
        .get();
    final snapshots = <String, Map<String, List<Object?>>>{};
    Map<String, List<Object?>> snapshot(QueryRow row) => snapshots.putIfAbsent(
      row.read<String>('estimate'),
      () => {'groups': [], 'members': []},
    );
    for (final row in rows) {
      snapshot(row)['groups']!.add([
        row.read<String>('id'),
        row.read<String>('name'),
        row.read<String>('description'),
        row.read<int>('position'),
        row.read<String>('evidence_json'),
      ]);
    }
    for (final row in members) {
      snapshot(row)['members']!.add([
        row.read<String>('line'),
        row.read<String>('group_id'),
      ]);
    }
    return snapshots;
  }

  static bool isComplete(Object? raw, List<dynamic> lines) {
    if (raw is! Map || raw['groups'] is! List || raw['members'] is! List) {
      return false;
    }
    final groups = raw['groups'] as List;
    if (groups.isEmpty) return false;
    final groupIds = <String>{};
    for (final group in groups) {
      if (group is! List ||
          group.length != 5 ||
          group[0] is! String ||
          (group[0] as String).trim().isEmpty ||
          group[0] == RepairGroup.otherId ||
          !groupIds.add(group[0] as String) ||
          group[1] is! String ||
          (group[1] as String).trim().isEmpty ||
          group[2] is! String ||
          group[3] is! int ||
          group[4] is! String) {
        return false;
      }
      try {
        if (jsonDecode(group[4] as String) is! List) return false;
      } on FormatException {
        return false;
      }
    }
    final lineIds = <String>{};
    final assignable = <String>{};
    for (final line in lines.cast<Map<String, dynamic>>()) {
      final id = line['id'];
      if (id is! String || id.trim().isEmpty || !lineIds.add(id)) return false;
      if (!RepairGroup.isGeneralCharge(line)) assignable.add(id);
    }
    final assigned = <String>{};
    for (final member in raw['members'] as List) {
      if (member is! List ||
          member.length != 2 ||
          !assignable.contains(member[0]) ||
          !assigned.add(member[0] as String) ||
          !groupIds.contains(member[1])) {
        return false;
      }
    }
    return true;
  }

  Future<void> insert(String business, String estimate, Map raw) async {
    for (final group in raw['groups'] as List) {
      await db.customStatement(
        'INSERT INTO repair_groups_v1 VALUES(?,?,?,?,?,?,?)',
        [business, estimate, ...(group as List)],
      );
    }
    for (final member in raw['members'] as List) {
      await db.customStatement(
        'INSERT INTO repair_group_members_v1 VALUES(?,?,?,?)',
        [business, estimate, ...(member as List)],
      );
    }
  }
}
