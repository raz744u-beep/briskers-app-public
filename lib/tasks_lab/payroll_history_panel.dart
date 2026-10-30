// ignore_for_file: prefer_const_constructors
// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../local/local_database_provider.dart';
import 'package:drift/drift.dart' show Variable;
import 'payroll_week_projection.dart';

/// Owner-approved Payroll History visual: grouped week cards in Reports.
/// Values are read from local TEST drafts and dated TEST disbursements only.
class LabPayrollHistoryPanel extends StatefulWidget {
  const LabPayrollHistoryPanel({
    super.key, required this.employeeId,
    required this.rateCents, required this.drafts,
    required this.payments, required this.onWeekTap,
    this.taskPayments=const [],this.settlements=const [],
  });
  final String employeeId;
  final int? rateCents;
  final List<Map<String, dynamic>> drafts;
  final List<Map<String, dynamic>> payments;
  final List<Map<String,dynamic>> taskPayments;
  final List<Map<String,dynamic>> settlements;
  final void Function(DateTime) onWeekTap;

  @override
  State<LabPayrollHistoryPanel> createState() =>
      _LabPayrollHistoryPanelState();
}

class _LabPayrollHistoryPanelState extends State<LabPayrollHistoryPanel> {
  String _period = 'All';
  int _visibleWeeks = 10;
  DateTimeRange? _custom;
  static final _date = DateFormat('MMM d, yyyy');
  static final _currency = NumberFormat.simpleCurrency(locale: 'en_US');

  String _money(int? value) =>
      value == null ? '—' : _currency.format(value / 100);

  bool _matches(DateTime week) {
    final today = DateTime.now();
    switch (_period) {
      case 'This Week':
        final monday=DateTime(today.year,today.month,today.day)
          .subtract(Duration(days:today.weekday-1));
        return !week.isBefore(monday) &&
          week.isBefore(monday.add(const Duration(days:7)));
      case 'Last Week':
        final monday=DateTime(today.year,today.month,today.day)
          .subtract(Duration(days:today.weekday-1));
        return !week.isBefore(monday.subtract(const Duration(days:7)))
          && week.isBefore(monday);
      case 'Last 30 Days':
        return !week.isBefore(DateTime(today.year,today.month,today.day)
          .subtract(const Duration(days:29)));
      case 'All': return true;
      case '2026': return week.year == 2026;
      case '2025': return week.year == 2025;
      case 'This Month': return week.year == today.year &&
          week.month == today.month;
      case 'Last Month':
        final m = DateTime(today.year, today.month - 1);
        return week.year == m.year && week.month == m.month;
      case 'Last 3 Months':
        return !week.isBefore(DateTime(today.year, today.month - 2));
      case 'Last 6 Months':
        return !week.isBefore(DateTime(today.year, today.month - 5));
      case 'Year to Date':
        return !week.isBefore(DateTime(today.year)) &&
          !week.isAfter(today);
      case 'Custom':
        return _custom != null &&
          !week.isBefore(_custom!.start) &&
          !week.isAfter(_custom!.end);
      default: return true;
    }
  }

  Future<void> _change(String chosen) async {
    if (chosen != 'Custom') {
      setState(() { _period = chosen; _visibleWeeks = 10; });
      return;
    }
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      initialDateRange: _custom);
    if (range != null && mounted) {
      setState(() { _custom = range; _period = chosen; _visibleWeeks = 10; });
    }
  }

  Widget _metric(String title, String value, Color color) =>
    Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(title, style: const TextStyle(
        fontSize: 11, color: Color(0xFF697687))),
      const SizedBox(height: 5),
      FittedBox(fit: BoxFit.scaleDown, child: Text(value,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
          color: color))),
    ]));

  Future<void> _showTaskHistory(LabPayrollWeek week) async {
    var visibleTaskCount = 10;
    await localDatabase.customStatement('CREATE TABLE IF NOT EXISTS lab_payroll_task_payments ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL, employee_id TEXT NOT NULL, '
      'document_id TEXT NOT NULL, line_id TEXT NOT NULL, week_key TEXT NOT NULL, '
      'description TEXT NOT NULL, hours REAL NOT NULL, cents INTEGER NOT NULL, '
      "method TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', paid_at INTEGER NOT NULL)");
    final rows = await localDatabase.customSelect(
      'SELECT description, hours, cents, method, note, paid_at, '
      'document_id, line_id FROM lab_payroll_task_payments '
      'WHERE business_id=? AND employee_id=? AND week_key=? '
      'ORDER BY paid_at DESC',
      variables: [
        const Variable<String>('briskers-tasks-test-only'),
        Variable<String>(widget.employeeId),
        Variable<String>(week.weekKey),
      ],
    ).get();
    final records=widget.settlements.where((row)=>
      row['employee_id']==widget.employeeId&&
      row['week_key']==week.weekKey).toList();
    final gross=records.fold<int>(0,(sum,row)=>
      sum+(row['gross_cents'] as int));
    final repaid=records.fold<int>(0,(sum,row)=>
      sum+(row['debt_cents'] as int));
    final transferred=records.fold<int>(0,(sum,row)=>
      sum+(row['net_cents'] as int));
    if (!mounted) { return; }
    // Full-screen payroll history keeps task details readable on narrow phones.
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (routeContext) => StatefulBuilder(
        builder: (context, updatePage) => Scaffold(
          appBar: AppBar(
            title: Text('Week of ' +
              _date.format(LabPayrollWeekSource.dateForKey(week.weekKey))),
          ),
          body: SafeArea(child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
            children: [
              const Text('2012 Hyundai Equus',
                style: TextStyle(fontSize: 13,
                  color: Color(0xFF64748B))),
              const SizedBox(height: 10),
              if (records.isNotEmpty) ...[
                Text('Gross pay: ' + _money(gross),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('Debt repaid: ' + _money(repaid)),
                Text('Transferred: ' + _money(transferred)),
                const Divider(height: 22),
              ],
              if (rows.isEmpty)
                const Text('No task-linked TEST payments for this week.'),
              for (final row in rows.take(visibleTaskCount))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text(row.read<String>('description'),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      row.read<double>('hours').toStringAsFixed(2) +
                      ' hrs · ' + _money(row.read<int>('cents')) +
                      ' · Paid\\nTap to expand',
                      style: const TextStyle(fontSize: 11.5,
                        color: Color(0xFF64748B))),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      const Align(alignment: Alignment.centerLeft,
                        child: Text('Job J-24 · Invoice #6342')),
                      Align(alignment: Alignment.centerLeft,
                        child: Text(
                          row.read<String>('method').toUpperCase() + ' · ' +
                          _date.format(DateTime.fromMillisecondsSinceEpoch(
                            row.read<int>('paid_at'))))),
                      if (row.read<String>('note').isNotEmpty)
                        Align(alignment: Alignment.centerLeft,
                          child: Text('Notes: ' + row.read<String>('note'))),
                      const Align(alignment: Alignment.centerRight,
                        child: Text('Tap to collapse',
                          style: TextStyle(fontSize: 10.5,
                            color: Color(0xFF64748B)))),
                    ],
                  ),
                ),
              if (rows.length > visibleTaskCount)
                TextButton(
                  key: const Key('paid-task-history-load-more'),
                  onPressed: () => updatePage(() => visibleTaskCount += 10),
                  child: Text('Load More · ${rows.length - visibleTaskCount} remaining')),
            ],
          )),
        ),
      ),
    ));
  }

  Widget _card(LabPayrollWeek week) {
    final paid = week.isPaid;
    final partial = week.isPartial ||
      (week.balanceCents != null && week.balanceCents! > 0);
    final bg = paid ? const Color(0xFFE9F8EF)
      : partial ? const Color(0xFFFFF2E8)
      : const Color(0xFFF5F8FB);
    final label = paid ? 'Paid'
      : partial ? 'Partial' : 'Unverified';
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      color: bg, elevation: 0.6,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTaskHistory(week),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(children: [
            Row(children: [
              Expanded(child: Text('Week of ' +
                  _date.format(LabPayrollWeekSource.dateForKey(week.weekKey)),
                style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800))),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: paid ? const Color(0xFFB6EDC5)
                    : partial ? const Color(0xFFFFDF90)
                    : const Color(0xFFE2E8F0)),
                child: Text(label,
                  style: const TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 13),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('Tap to view details',
                style: TextStyle(fontSize: 10.5,
                  color: Color(0xFF64748B)))),
            const SizedBox(height: 5),
            Row(children: [
              _metric('Hours',
                week.hasDraft ? week.hours.toStringAsFixed(1) : '—',
                const Color(0xFF101828)),
              _metric('Gross', _money(week.grossCents),
                const Color(0xFF101828)),
              _metric('Paid', _money(week.paidCents),
                const Color(0xFF101828)),
              _metric('Balance', _money(week.balanceCents),
                week.balanceCents == null ? const Color(0xFF64748B)
                  : week.balanceCents! > 0
                    ? const Color(0xFFDA6118)
                    : const Color(0xFF117C56)),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weeks = LabPayrollWeekSource.historyWeekKeys(
      employeeId: widget.employeeId,
      drafts: widget.drafts, payments: widget.payments,
    ).map((key) => LabPayrollWeekSource.summarize(
      employeeId: widget.employeeId,
      week: LabPayrollWeekSource.dateForKey(key),
      hourlyCents: widget.rateCents,
      drafts: widget.drafts, payments: widget.payments,
      taskPayments:widget.taskPayments,
      settlements:widget.settlements,
      confirmedOnly:true,
    )).where((week) => _matches(
      LabPayrollWeekSource.dateForKey(week.weekKey))).toList();
    final paid = weeks.fold<int>(0, (sum, w) => sum + w.paidCents);
    int gross = 0;
    final complete = weeks.every((w) => w.grossCents != null);
    for (final w in weeks) { gross += w.grossCents ?? 0; }
    return Column(children: [
      Padding(
        padding:const EdgeInsets.fromLTRB(12,10,12,9),
        child:Row(children:[
          const Expanded(child:Text('Payroll History',
            maxLines:1,overflow:TextOverflow.ellipsis,
            style:TextStyle(fontSize:18,fontWeight:FontWeight.w800))),
          SizedBox(width:159,child:DropdownButtonFormField<String>(
            key:ValueKey('reports-period-$_period'),
            initialValue:_period,
            isExpanded:true,
            decoration:InputDecoration(
              isDense:true,
              contentPadding:const EdgeInsets.symmetric(
                horizontal:10,vertical:9),
              border:OutlineInputBorder(
                borderRadius:BorderRadius.circular(14))),
            items:const [
              'All','2026','2025','This Week','Last Week',
              'Last 30 Days','This Month','Last Month',
              'Last 3 Months','Last 6 Months','Year to Date','Custom',
            ].map((label)=>DropdownMenuItem(value:label,
              child:Text(label,overflow:TextOverflow.ellipsis,
                style:const TextStyle(fontSize:12)))).toList(),
            onChanged:(value) {
              if(value!=null) {_change(value);}
            },
          )),
          const SizedBox(width:7),
          const Icon(Icons.history,color:BriskersColors.jobs,size:22),
        ]),
      ),
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 9),
        children: [
          if (weeks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No TEST payroll weeks in this period.',
                style: TextStyle(color: Color(0xFF64748B)))),
          for (final week in weeks.take(_visibleWeeks)) _card(week),
          if (weeks.length > _visibleWeeks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton.icon(
                key: const Key('payroll-history-load-more'),
                onPressed: () => setState(() => _visibleWeeks += 10),
                icon: const Icon(Icons.expand_more),
                label: Text('Load More · ${weeks.length - _visibleWeeks} weeks remaining'),
              ),
            ),
        ],
      )),
      SafeArea(top:false,child:Container(
        key: const Key('reports-fixed-payment-total'),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFDDE6E8)))),
        padding: const EdgeInsets.fromLTRB(15, 9, 15, 12),
        child: Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total paid · ' + _period, style: const TextStyle(
                fontSize: 11, color: Color(0xFF64748B))),
              Text(_money(paid), style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800,
                color: BriskersColors.jobs)),
            ],
          )),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Total gross (draft)',
                style: TextStyle(
                  fontSize: 11, color: Color(0xFF64748B))),
              Text(complete ? _money(gross) : '—',
                style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800)),
            ],
          )),
        ]),
      )),
    ]);
  }
}
