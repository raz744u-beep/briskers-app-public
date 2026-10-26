// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';

/// Read-only, local TEST financial projection from week drafts, task-linked
/// test records, and historical test disbursements. Never posts shop money.
class LabPayrollPeriodProjection {
  const LabPayrollPeriodProjection({
    required this.hours, required this.grossCents,
    required this.paidCents, required this.balanceCents,
  });
  final double? hours;
  final int? grossCents;
  final int paidCents;
  final int? balanceCents;

  static DateTime weekMonday(DateTime day) =>
    DateTime(day.year, day.month, day.day)
      .subtract(Duration(days: day.weekday - 1));

  static String weekKey(DateTime day) {
    final w = weekMonday(day);
    return w.year.toString().padLeft(4,'0') + '-' +
      w.month.toString().padLeft(2,'0') + '-' +
      w.day.toString().padLeft(2,'0');
  }

  static LabPayrollPeriodProjection calculate({
    required String employeeId,
    required DateTime from,
    required DateTime until,
    required int? hourlyRateCents,
    required List<Map<String,dynamic>> drafts,
    required List<Map<String,dynamic>> payments,
    required List<Map<String,dynamic>> taskPayments,
  }) {
    bool inPeriod(DateTime t) => !t.isBefore(from) && t.isBefore(until);
    final weeks = <String, ({double hours, int? gross})>{};
    for (final row in drafts) {
      if (row['employee_id'] != employeeId) { continue; }
      final key = row['week_key']?.toString() ?? '';
      final week = DateTime.tryParse(key);
      if (week == null || !inPeriod(week)) continue;
      double hrs = 0;
      try {
        final data = jsonDecode(row['selected_json']?.toString() ?? '{}');
        if (data is Map) {
          for (final n in data.values) {
            if (n is num && n.isFinite && n > 0) hrs += n.toDouble();
          }
        }
      } catch (_) { continue; }
      final override = row['override_cents'];
      final gross = override is int && override >= 0
        ? override : hourlyRateCents == null ? null
        : (hrs * hourlyRateCents).round();
      weeks[key] = (hours:hrs,gross:gross);
    }
    final linkedHours = <String,double>{};
    for (final task in taskPayments) {
      if (task['employee_id'] != employeeId) { continue; }
      final key = task['week_key']?.toString() ?? '';
      final week = DateTime.tryParse(key);
      final value = task['hours'];
      if (week == null || !inPeriod(week) ||
          value is! num || !value.isFinite || value <= 0) { continue; }
      linkedHours[key] = (linkedHours[key] ?? 0) + value.toDouble();
    }
    for (final item in linkedHours.entries) {
      final current = weeks[item.key];
      final linked = item.value;
      final hours = current == null || current.hours < linked
        ? linked : current.hours;
      final linkedGross = hourlyRateCents == null
        ? null : (linked * hourlyRateCents).round();
      final draftGross = current?.gross;
      final gross = draftGross == null ? linkedGross
        : linkedGross == null ? draftGross
        : draftGross > linkedGross ? draftGross : linkedGross;
      weeks[item.key] = (hours:hours,gross:gross);
    }
    var paid = 0;
    for (final row in payments) {
      if (row['employee_id'] != employeeId || row['kind'] != 'pay' ||
          row['paid_at'] is! int || row['cents'] is! int) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(row['paid_at'] as int);
      if (inPeriod(date)) paid += row['cents'] as int;
    }
    if (weeks.isEmpty) {
      return LabPayrollPeriodProjection(
        hours:null,grossCents:null,paidCents:paid,balanceCents:null);
    }
    var hours = 0.0, gross = 0;
    var known = true;
    for (final week in weeks.values) {
      hours += week.hours;
      if (week.gross == null) { known = false; }
      else { gross += week.gross!; }
    }
    final resultGross = known ? gross : null;
    final balance = resultGross == null ? null
      : (resultGross - paid).clamp(0, 1000000000).toInt();
    return LabPayrollPeriodProjection(
      hours:hours,grossCents:resultGross,
      paidCents:paid,balanceCents:balance);
  }
}
