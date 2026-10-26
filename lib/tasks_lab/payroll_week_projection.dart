// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import '../local/local_database_provider.dart';

/// Pure local TEST projection. No payroll posting, sync or live shop records.
/// This legacy lab stores payment DATE, not covered-week IDs. The "paid" figure
/// reflects disbursements dated during a given week, not verified task payouts.
class LabPayrollWeek {
  const LabPayrollWeek({
    required this.weekKey, required this.employeeId,
    required this.taskCount, required this.hours,
    required this.grossCents, required this.paidCents,
    required this.hasDraft,
  });
  final String weekKey;
  final String employeeId;
  final int taskCount;
  final double hours;
  final int? grossCents;
  final int paidCents;
  final bool hasDraft;
  int? get balanceCents => grossCents == null
      ? null : (grossCents! - paidCents).clamp(0, 1000000000);
  bool get isPaid => hasDraft && grossCents != null &&
      grossCents! > 0 && paidCents >= grossCents!;
  bool get isPartial => hasDraft && paidCents > 0 &&
      grossCents != null && paidCents < grossCents!;
}

class LabPayrollWeekSource {
  static const businessId = 'briskers-tasks-test-only';

  static Future<List<Map<String, dynamic>>> readDrafts() async {
    await localDatabase.customStatement('''
      CREATE TABLE IF NOT EXISTS lab_weekly_payroll_drafts (
        business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
        week_key TEXT NOT NULL, selected_json TEXT NOT NULL,
        override_cents INTEGER, updated_at INTEGER NOT NULL,
        PRIMARY KEY (business_id, employee_id, week_key)
      )
    ''');
    final rows = await localDatabase.customSelect(
      'SELECT employee_id, week_key, selected_json, override_cents '
      'FROM lab_weekly_payroll_drafts WHERE business_id=? '
      'ORDER BY week_key DESC',
      variables: [const Variable<String>(businessId)],
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  static DateTime start(DateTime date) =>
      DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));

  static String weekKey(DateTime date) {
    final monday = start(date);
    return monday.year.toString().padLeft(4, '0') + '-' +
      monday.month.toString().padLeft(2, '0') + '-' +
      monday.day.toString().padLeft(2, '0');
  }

  static DateTime dateForKey(String key) =>
      DateTime.tryParse(key) ?? DateTime(2000);

  static LabPayrollWeek summarize({
    required String employeeId,
    required DateTime week,
    required int? hourlyCents,
    required List<Map<String, dynamic>> drafts,
    required List<Map<String, dynamic>> payments,
  }) {
    final weekId = weekKey(week);
    Map<String, dynamic>? draft;
    for (final row in drafts) {
      if (row['employee_id'] == employeeId && row['week_key'] == weekId) {
        draft = row;
        break;
      }
    }
    var taskCount = 0;
    var hours = 0.0;
    final json = draft?['selected_json'];
    if (json is String) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map) {
          for (final entry in decoded.values) {
            if (entry is num && entry.toDouble().isFinite && entry > 0) {
              hours += entry.toDouble();
              taskCount++;
            }
          }
        }
      } catch (_) {
        // Corrupted local test draft is treated as unverified.
        draft = null;
        taskCount = 0;
        hours = 0;
      }
    }
    final rawOverride = draft?['override_cents'];
    final override = rawOverride is int && rawOverride >= 0
      ? rawOverride : null;
    final gross = override ??
      (draft == null || hourlyCents == null ? null :
        (hours * hourlyCents).round());

    final selectedStart = start(week);
    final selectedEnd = selectedStart.add(const Duration(days: 7));
    var paid = 0;
    for (final row in payments) {
      if (row['employee_id'] != employeeId ||
          row['kind'] != 'pay' || row['paid_at'] is! int ||
          row['cents'] is! int) {
        continue;
      }
      final date = DateTime.fromMillisecondsSinceEpoch(row['paid_at'] as int);
      if (!date.isBefore(selectedStart) && date.isBefore(selectedEnd)) {
        paid += row['cents'] as int;
      }
    }
    return LabPayrollWeek(
      weekKey: weekId, employeeId: employeeId, taskCount: taskCount,
      hours: hours, grossCents: gross, paidCents: paid,
      hasDraft: draft != null,
    );
  }

  static int? previousBalance({
    required String employeeId,
    required DateTime selectedWeek,
    required int? rateCents,
    required List<Map<String, dynamic>> drafts,
    required List<Map<String, dynamic>> payments,
  }) {
    final before = weekKey(selectedWeek);
    final candidates = <String>{};
    for (final draft in drafts) {
      final key = draft['week_key']?.toString() ?? '';
      if (draft['employee_id'] == employeeId && key.compareTo(before) < 0) {
        candidates.add(key);
      }
    }
    var sum = 0;
    for (final key in candidates) {
      final projection = summarize(
        employeeId: employeeId, week: dateForKey(key),
        hourlyCents: rateCents, drafts: drafts, payments: payments,
      );
      final amount = projection.balanceCents;
      if (amount == null) return null;
      sum += amount;
    }
    return sum;
  }

  static List<String> historyWeekKeys({
    required String employeeId,
    required List<Map<String, dynamic>> drafts,
    required List<Map<String, dynamic>> payments,
  }) {
    final keys = <String>{};
    for (final row in drafts) {
      if (row['employee_id'] == employeeId &&
          row['week_key'] is String) {
        keys.add(row['week_key'] as String);
      }
    }
    for (final row in payments) {
      if (row['employee_id'] == employeeId && row['kind'] == 'pay' &&
          row['paid_at'] is int) {
        keys.add(weekKey(DateTime.fromMillisecondsSinceEpoch(
          row['paid_at'] as int)));
      }
    }
    return keys.toList()..sort((a,b) => b.compareTo(a));
  }
}
