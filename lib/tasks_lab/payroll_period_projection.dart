// ignore_for_file: prefer_interpolation_to_compose_strings

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
    List<Map<String,dynamic>> settlements=const [],
  }) {
    bool inPeriod(DateTime t) => !t.isBefore(from) && t.isBefore(until);
    // Task assignment and draft selection are not wages already owed.
    // Only confirmed, task-linked TEST payroll contributes to earned gross.
    final hoursByWeek=<String,double>{};
    for(final task in taskPayments) {
      if(task['employee_id']!=employeeId) {continue;}
      final key=task['week_key']?.toString()??'';
      final when=DateTime.tryParse(key);
      final raw=task['hours'];
      if(when==null||!inPeriod(when)||raw is! num||
        !raw.isFinite||raw<=0) {continue;}
      hoursByWeek[key]=(hoursByWeek[key]??0)+raw.toDouble();
    }
    final grossByWeek=<String,int>{};
    for(final record in settlements) {
      if(record['employee_id']!=employeeId) {continue;}
      final key=record['week_key']?.toString()??'';
      final when=DateTime.tryParse(key);
      final raw=record['gross_cents'];
      if(when==null||!inPeriod(when)||raw is! int||raw<0) {continue;}
      grossByWeek[key]=(grossByWeek[key]??0)+raw;
    }
    // An advance deduction settles wages without transferring cash.
    // Count it toward settled compensation, but never toward Paid cash.
    var deducted = 0;
    for (final record in settlements) {
      if (record['employee_id'] != employeeId) continue;
      final key = record['week_key']?.toString() ?? '';
      final when = DateTime.tryParse(key);
      final cents = record['debt_cents'];
      if (when != null && inPeriod(when) && cents is int && cents > 0) {
        deducted += cents;
      }
    }
    var paid = 0;
    for (final row in payments) {
      if (row['employee_id'] != employeeId || row['kind'] != 'pay' ||
          row['paid_at'] is! int || row['cents'] is! int) { continue; }
      final cents = row['cents'] as int;
      // Repayment and adjustments have separate ledger entries. The paid
      // figure must represent actual positive payroll disbursements only.
      if (cents <= 0) { continue; }
      final date = DateTime.fromMillisecondsSinceEpoch(row['paid_at'] as int);
      if (inPeriod(date)) { paid += cents; }
    }
    if(hoursByWeek.isEmpty) {
      // Fixed-weekly employees may have a confirmed settlement without any
      // invoice-linked mechanic hours. A missing rate must not hide their
      // recorded gross pay or pretend that payment itself created labor.
      if (grossByWeek.isNotEmpty) {
        final gross = grossByWeek.values.fold<int>(0, (sum, n) => sum + n);
        return LabPayrollPeriodProjection(
          hours:null, grossCents:gross, paidCents:paid,
          balanceCents:(gross-paid-deducted).clamp(0,1000000000).toInt());
      }
      return LabPayrollPeriodProjection(
        hours:null,grossCents:null,paidCents:paid,balanceCents:null);
    }
    final hrs=hoursByWeek.values.fold<double>(0,(sum,n)=>sum+n);
    var gross=0;
    for(final entry in hoursByWeek.entries) {
      if(grossByWeek.containsKey(entry.key)) {
        gross+=grossByWeek[entry.key]!;
      } else if(hourlyRateCents!=null) {
        gross+=(entry.value*hourlyRateCents).round();
      } else {
        // Preserve known confirmed settlements even when another week's
        // task hours have no hourly rate. Never invent the missing wages
        // or a zero balance for an incompletely priced period.
        final confirmedGross = grossByWeek.values.fold<int>(
          0, (sum, cents) => sum + cents);
        // The gross displayed here is confirmed only; unpriced task
        // labor remains unknown, so the outstanding balance stays unknown.
        return LabPayrollPeriodProjection(
          hours:hrs,
          grossCents:confirmedGross > 0 ? confirmedGross : null,
          paidCents:paid, balanceCents:null);
      }
    }
    // Include confirmed weekly-base settlements even if that week has no
    // task-linked hours; they are distinct from labor allocations.
    for (final entry in grossByWeek.entries) {
      if (!hoursByWeek.containsKey(entry.key)) gross += entry.value;
    }
    return LabPayrollPeriodProjection(
      hours:hrs,grossCents:gross,paidCents:paid,
      balanceCents:(gross-paid-deducted).clamp(0,1000000000).toInt());

  }
}
