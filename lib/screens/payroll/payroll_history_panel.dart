// ignore_for_file: prefer_const_constructors
// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';

/// Restored from Tasks TEST. All figures come from recorded settlements and
/// their immutable work snapshots, grouped by the selected payroll week.
class PayrollHistoryPanel extends StatefulWidget {
  const PayrollHistoryPanel({
    super.key,
    required this.payments,
    required this.onOpenJob,
    required this.onOpenInvoice,
    required this.unlocked,
  });

  final List<Map<String, dynamic>> payments;
  final ValueChanged<String> onOpenJob;
  final ValueChanged<String> onOpenInvoice;
  final ValueListenable<bool> unlocked;

  @override
  State<PayrollHistoryPanel> createState() => _PayrollHistoryPanelState();
}

class _PayrollHistoryPanelState extends State<PayrollHistoryPanel> {
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

  void _showTaskHistory(_RecordedWeek week) {
    var visibleTaskCount = 10;
    final expanded = <Object?>{};
    final work = week.work;
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (context) => ValueListenableBuilder<bool>(
        valueListenable: widget.unlocked,
        builder: (context, unlocked, _) => Scaffold(
          appBar: AppBar(title: Text('Week of ${_date.format(week.date)}')),
          body: !unlocked
              ? const Center(child: Text('Owner payroll locked.'))
              : StatefulBuilder(builder: (context, updatePage) => SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
                    children: [
                      Row(children: [
                        _metric('Gross pay', _money(week.gross), const Color(0xFF101828)),
                        _metric('Debt repaid', _money(week.repaid), const Color(0xFF101828)),
                        _metric('Transferred', _money(week.net), const Color(0xFF117C56)),
                      ]),
                      const Divider(height: 22),
                      Text('Paid tasks (${work.length})',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                      for (final row in work.take(visibleTaskCount))
                        _paidWork(
                          row,
                          expanded: expanded.contains(row['credit_id']),
                          onExpansion: (open) => updatePage(() {
                            if (open) {
                              expanded.add(row['credit_id']);
                            } else {
                              expanded.remove(row['credit_id']);
                            }
                          }),
                        ),
                      if (work.length > visibleTaskCount)
                        TextButton(
                          key: const Key('paid-task-history-load-more'),
                          onPressed: () => updatePage(() => visibleTaskCount += 10),
                          child: Text('Load More · ${work.length - visibleTaskCount} remaining'),
                        ),
                      for (final payment in week.payments)
                        if ((payment['work'] as List).isEmpty)
                          ListTile(
                            title: Text('Payment · ${_money(payment['net'] as int)}'),
                            subtitle: Text('${payment['method']} · ${payment['verified_date']}'),
                          ),
                    ],
                  ),
                )),
        ),
      ),
    ));
  }

  Widget _paidWork(
    Map<String, dynamic> row, {
    required bool expanded,
    required ValueChanged<bool> onExpansion,
  }) {
    final job = row['job_id'] as String?;
    final invoice = row['invoice_id'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: ValueKey(row['credit_id']),
        showTrailingIcon: false,
        onExpansionChanged: onExpansion,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(row['description'] as String? ?? 'Paid work',
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Paid · ${_money(row['gross_cents'] as int?)}',
            style: const TextStyle(color: Color(0xFF117C56))),
          if (row['vehicle_label'] case final String label) Text(label),
          Wrap(spacing: 8, children: [
            if (job != null)
              TextButton(onPressed: () => widget.onOpenJob(job),
                child: Text('Job ${row['job_number'] ?? 'details'}')),
            if (invoice != null)
              TextButton(onPressed: () => widget.onOpenInvoice(invoice),
                child: Text('Invoice ${row['document_number'] ?? 'details'}')),
          ]),
          Text('${((row['actual_minutes'] as int? ?? 0) / 60).toStringAsFixed(2)} hrs'
            ' · ${row['method']} · ${row['verified_date']}'),
          Text(expanded ? 'Tap to collapse' : 'Tap to expand',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
        ]),
        children: [
          ListTile(
            title: Text('Payment ${row['operation_id']}'),
            subtitle: Text('Credit ${row['credit_id']}'),
          ),
        ],
      ),
    );
  }

  Widget _card(_RecordedWeek week) {
    const bg = Color(0xFFE9F8EF);
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
                  _date.format(week.date),
                style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800))),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: const Color(0xFFB6EDC5)),
                // This is a record of verified pay, not proof that every
                // task in the week has been settled.
                child: Text('Paid portion',
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
              _metric('Hours', (week.minutes / 60).toStringAsFixed(1),
                const Color(0xFF101828)),
              _metric('Gross', _money(week.gross), const Color(0xFF101828)),
              // Recorded gross was settled through net transfer and any
              // debt repayment. Remaining unrecorded tasks are not included.
              _metric('Paid', _money(week.gross), const Color(0xFF117C56)),
              _metric('Balance', '—', const Color(0xFF64748B)),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <DateTime, List<Map<String, dynamic>>>{};
    for (final payment in widget.payments) {
      final date = DateTime.parse(payment['week'] as String);
      if (_matches(date)) (grouped[date] ??= []).add(payment);
    }
    final weeks = grouped.entries.map((entry) =>
      _RecordedWeek(entry.key, entry.value)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    // Paid denotes verified gross compensation, while net bank/cash
    // transfer is separately visible in each week detail alongside debt repaid.
    final paid = weeks.fold<int>(0, (sum, week) => sum + week.gross);
    final gross = weeks.fold<int>(0, (sum, week) => sum + week.gross);
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
              child: Text('No recorded payroll weeks in this period.',
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
              const Text('Total gross',
                style: TextStyle(
                  fontSize: 11, color: Color(0xFF64748B))),
              Text(_money(gross),
                style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800)),
            ],
          )),
        ]),
      )),
    ]);
  }
}

class _RecordedWeek {
  _RecordedWeek(this.date, this.payments);
  final DateTime date;
  final List<Map<String, dynamic>> payments;
  List<Map<String, dynamic>> get work => [
    for (final payment in payments)
      ...(payment['work'] as List<Map<String, dynamic>>),
  ];
  int get minutes => work.fold(0, (sum, row) => sum + (row['actual_minutes'] as int? ?? 0));
  int get gross => _sum('gross');
  int get repaid => _sum('repayment');
  int get net => _sum('net');
  int _sum(String field) => payments.fold(0, (sum, row) => sum + (row[field] as int));
}
