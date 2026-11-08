import 'package:flutter/material.dart';

/// Read-only calculation using existing mechanic allocation snapshots.
/// This never calls a repository or records a payment, paid-credit, or expense.
class PayrollDryRunTotals {
  const PayrollDryRunTotals({
    required this.lines,
    required this.assignedMinutes,
    required this.recordedMinutes,
    required this.laborCents,
    required this.unknownRateLines,
    required this.historicalLines,
  });

  final int lines;
  final int assignedMinutes;
  final int recordedMinutes;
  final int laborCents;
  final int unknownRateLines;
  final int historicalLines;

  static PayrollDryRunTotals fromSavedWork(
      List<Map<String, dynamic>> rows) {
    int assigned=0, recorded=0, value=0, unknown=0, history=0;
    for(final row in rows) {
      final estimated=row['estimated_minutes'];
      final actual=row['recorded_actual_minutes'] ?? row['actual_minutes'];
      final rate=row['rate_cents'];
      if(estimated is int && estimated>=0)assigned+=estimated;
      if(actual is int && actual>=0) {
        recorded+=actual;
        if(rate is int && rate>0) {
          value+=(actual*rate+30)~/60;
        } else if(actual>0) {
          unknown++;
        }
      }
      if(row['archived_labor']==1)history++;
    }
    return PayrollDryRunTotals(
      lines:rows.length,assignedMinutes:assigned,
      recordedMinutes:recorded,laborCents:value,
      unknownRateLines:unknown,historicalLines:history);
  }
}

class PayrollDryRunPreview extends StatelessWidget {
  const PayrollDryRunPreview({
    super.key,
    required this.employeeName,
    required this.weekStart,
    required this.rows,
  });

  final String employeeName;
  final DateTime weekStart;
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final totals=PayrollDryRunTotals.fromSavedWork(rows);
    String hours(int minutes)=>(minutes/60).toStringAsFixed(2);
    String usd(int cents)=>'\$\{(cents/100).toStringAsFixed(2)}';
    final friday=weekStart.add(const Duration(days:4));
    final sunday=weekStart.add(const Duration(days:6));
    return Scaffold(
      appBar:AppBar(title:const Text('Payroll Test · Read only')),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        Text(employeeName,style:Theme.of(context).textTheme.titleLarge),
        Text('Week: \$\{weekStart.month}/\$\{weekStart.day}–\$\{sunday.month}/\$\{sunday.day}/\$\{sunday.year}'),
        const SizedBox(height:12),
        const Text('TEST ONLY · No payment will be saved.',
          style:TextStyle(color:Colors.teal,fontWeight:FontWeight.w800)),
        const SizedBox(height:12),
        ListTile(title:const Text('Recorded mechanic labor lines'),
          trailing:Text('\$\{totals.lines}')),
        ListTile(title:const Text('Assigned hours'),
          trailing:Text(hours(totals.assignedMinutes))),
        ListTile(title:const Text('Recorded actual hours'),
          trailing:Text(hours(totals.recordedMinutes))),
        ListTile(title:const Text('Recorded hourly labor value'),
          trailing:Text(usd(totals.laborCents))),
        if(totals.unknownRateLines>0)
          Text('\$\{totals.unknownRateLines} line(s) have recorded hours without a verified hourly rate; their amounts are excluded.',
            style:const TextStyle(color:Colors.deepOrange)),
        if(totals.historicalLines>0)
          Text('\$\{totals.historicalLines} historical line(s) are excluded from live payroll.'),
        const Divider(height:24),
        const Text('This is an hourly labor calculation from saved allocations, not the complete weekly paycheck. Weekly base, supplements, deductions, and previously paid expenses require separate reconciliation.'),
        const SizedBox(height:10),
        Text('Compare with original Expenses for Friday \$\{friday.month}/\$\{friday.day}/\$\{friday.year}.'),
        const SizedBox(height:14),
        if(rows.isEmpty)
          const Text('No dated mechanic allocations are linked to this week. Original invoice labor may still exist separately.'),
        for(final row in rows)
          ListTile(
            title:Text('\$\{row['job_number']??'Job'} · \$\{row['description']??'Labor'}'),
            subtitle:Text(row['archived_labor']==1
              ? 'Historical · not payable again'
              : 'Saved mechanic allocation · read only'),
            trailing:Text(hours(row['recorded_actual_minutes'] is int
              ? row['recorded_actual_minutes'] as int
              : row['actual_minutes'] is int ? row['actual_minutes'] as int : 0)),
          ),
      ]),
    );
  }
}
