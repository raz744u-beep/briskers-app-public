// ignore_for_file: prefer_const_constructors
// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import 'approved_tasks_ui.dart';
import 'payroll_payment_correction.dart';

/// Restored from Tasks TEST. All figures come from recorded settlements and
/// their immutable work snapshots, grouped by the selected payroll week.
class PayrollHistoryPanel extends StatefulWidget {
  const PayrollHistoryPanel({
    super.key,
    required this.payments,
    required this.onOpenJob,
    required this.onOpenInvoice,
    required this.unlocked,
    this.employeeName,
    this.onOpenTask,
    this.onPaymentAction,
  });

  final String? employeeName;
  final Future<bool> Function(Map<String, dynamic>, PayrollPaymentAction)? onPaymentAction;
  final ValueChanged<Map<String, dynamic>>? onOpenTask;

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

  void _showTaskHistory(_RecordedWeek initialWeek) {
    var visibleTaskCount = 10;
    final expanded = <String>{};
    var selectedDate = initialWeek.date;
    final grouped = <DateTime, List<Map<String, dynamic>>>{};
    for (final payment in widget.payments) {
      (grouped[DateTime.parse(payment['week'] as String)] ??= []).add(payment);
    }
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (context) => ValueListenableBuilder<bool>(
        valueListenable: widget.unlocked,
        builder: (context, unlocked, _) => StatefulBuilder(
            builder: (context, updatePage) {
              final week = _RecordedWeek(
                selectedDate,
                grouped[selectedDate] ?? [],
              );
              final work = week.work;
              void move(int offset) => updatePage(() {
                selectedDate = selectedDate.add(Duration(days: offset * 7));
                expanded.clear();
                visibleTaskCount = 10;
              });
              return Scaffold(
                backgroundColor: taskCanvas,
                appBar: const ApprovedTasksHeader(title: 'Weekly Payroll Details',
                ),
          body: !unlocked
              ? const Center(child: Text('Owner payroll locked.'))
              : SafeArea(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 22),
                          children: [
                            Text(
                              '${widget.employeeName ?? 'Employee'} — Weekly Payroll Details',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Previous paid week',
                                  onPressed: () => move(-1),
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Expanded(
                  child: Text(
                                    '${DateFormat('MMM d').format(selectedDate)} – ${_date.format(selectedDate.add(const Duration(days: 4)))}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Next paid week',
                                  onPressed: () => move(1),
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                _detailMetric(
                                  'Gross Pay',
                                  week.gross + week.balance,
                                  const Color(0xFFD6E9FF),
                                  taskNavy,
                                ),
                                _detailMetric(
                                  'Debt Repaid',
                                  week.repaid,
                                  const Color(0xFFFFE5C5),
                                  taskAmber,
                                ),
                                _detailMetric(
                                  'Transferred',
                                  week.net,
                                  const Color(0xFFE1F6D9),
                                  taskGreen,
                                ),
                              ],
                            ),
                            if (week.balance != 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text('${week.balance > 0 ? 'Remaining payment' : 'Overpayment'} · ${_money(week.balance.abs())}'),
                              ),
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                Text('Paid tasks (${work.length})',
                        style: const TextStyle(fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                  ),
                                ),
                                Text(
                                  'Total: ${(week.minutes / 60).toStringAsFixed(2)} hrs · ${_money(week.net)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: taskGreen,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                      for (final row in work.take(visibleTaskCount))
                        _paidWork(
                          row,
                          expanded: expanded.contains(
                                  '${row['operation_id']}:${row['credit_id']}',
                                ),
                          onExpansion: (open) => updatePage(() {
                                  final id =
                                      '${row['operation_id']}:${row['credit_id']}';
                                  if (open) {
                              expanded.add(id);
                            } else {
                              expanded.remove(id);
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
                        if ((payment['work'] as List).isEmpty || payment['reversed_at'] != null || widget.onPaymentAction != null)
                          ListTile(
                            title: Text('${payment['reversed_at'] == null ? 'Payment' : 'Reversed payment'} · ${_money(payment['net'] as int)}'),
                            subtitle: Text('${payment['method']} · ${payment['verified_date']}'
                                '${payment['reversal_reason'] == null ? '' : '\n${payment['reversal_reason']}'}'),
                            trailing: widget.onPaymentAction == null || payment['reversed_at'] != null
                                ? null
                                : PopupMenuButton<PayrollPaymentAction>(
                                    tooltip: 'Payment actions',
                                    onSelected: (action) async {
                                      if (await widget.onPaymentAction!(payment, action) && context.mounted) {
                                        Navigator.of(context).pop();
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: PayrollPaymentAction.edit,
                                        child: Text('Edit'),
                                      ),
                                      PopupMenuItem(
                                        value: PayrollPaymentAction.delete,
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                          ),
                            if (work.isEmpty && week.payments.isEmpty)
                              const ListTile(
                                title: Text(
                                  'No recorded payroll for this week.',
                                ),
                              ),
                          ],
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _detailMetric(
    String title,
    int cents,
    Color background,
    Color color,
  ) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _money(cents),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _paidWork(
    Map<String, dynamic> row, {
    required bool expanded,
    required ValueChanged<bool> onExpansion,
  }) {
    final job = row['job_id'] as String?,
        invoice = row['invoice_id'] as String?;
    final description = row['description']?.toString() ?? 'Paid work';
    final date = DateTime.tryParse(row['verified_date']?.toString() ?? '');
    return ApprovedTaskCardSurface(
      borderColor: taskGreen,
      child: Material(
        color: Colors.transparent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => onExpansion(!expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Job ${row['job_number'] ?? '—'} · ${row['customer_name'] ?? 'Customer unavailable'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: taskGreen,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Paid',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          color: taskNavy,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${row['vehicle_label'] ?? 'Vehicle unavailable'} · $description',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${widget.employeeName ?? row['employee_name'] ?? 'Employee'} · ${((row['actual_minutes'] as int? ?? 0) / 60).toStringAsFixed(2)} h · ${row['method'] ?? 'Unknown'} · ${date == null ? 'Date unavailable' : DateFormat('MMM d, yyyy').format(date)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF596574),
                            ),
                          ),
                        ),
                        Text(
                          _money(row['gross_cents'] as int?),
                          style: const TextStyle(
                            color: taskGreen,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 12),
                    Text('Description: $description'),
                    Text(
                      'Recorded labor: ${_money(row['gross_cents'] as int?)} · ${row['method']} · ${row['verified_date']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                        if (row['task_id'] is String && widget.onOpenTask != null)
                          Expanded(child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8), visualDensity: VisualDensity.compact),
                            onPressed: () => widget.onOpenTask!(row),
                            icon: const Icon(Icons.build_outlined, size: 15),
                            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('View Task')),
                          )),
                        if (row['task_id'] is String && widget.onOpenTask != null && (job != null || invoice != null))
                          const SizedBox(width: 5),
                        if (job != null)
                          Expanded(child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8), visualDensity: VisualDensity.compact),
                            onPressed: () => widget.onOpenJob(job),
                            icon: const Icon(Icons.work_outline, size: 15),
                            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Open Job')),
                          )),
                        if (job != null && invoice != null) const SizedBox(width: 5),
                        if (invoice != null)
                          Expanded(child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8), visualDensity: VisualDensity.compact),
                            onPressed: () => widget.onOpenInvoice(invoice),
                            icon: const Icon(Icons.receipt_long_outlined, size: 15),
                            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Open Invoice')),
                          )),
                      ]),
                    if (row['task_id'] == null ||
                        job == null ||
                        invoice == null)
                      const Text(
                        'Some original links are unavailable in this saved record.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
              ),
          ],
        ),
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
              _metric('Gross', _money(week.gross + week.balance), const Color(0xFF101828)),
              // Recorded gross was settled through net transfer and any
              // debt repayment. Remaining unrecorded tasks are not included.
              _metric('Paid', _money(week.gross), const Color(0xFF117C56)),
              if (week.balance == 0)
                _metric('Balance', '—', const Color(0xFF64748B))
              else
                _metric('Balance', _money(week.balance), const Color(0xFF64748B)),
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
    final gross = weeks.fold<int>(0, (sum, week) => sum + week.gross + week.balance);
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
      if (payment['reversed_at'] == null)
        ...(payment['work'] as List<Map<String, dynamic>>),
  ];
  int get minutes => work.fold(0, (sum, row) => sum + (row['actual_minutes'] as int? ?? 0));
  int get gross => _sum('gross');
  int get repaid => _sum('repayment');
  int get net => _sum('net');
  int get balance => payments.fold(0, (sum, row) {
    final net = row['net'] as int;
    return row['reversed_at'] == null ? sum + (row['original_net'] as int? ?? net) - net : sum;
  });
  int _sum(String field) => payments.fold(0, (sum, row) => sum + (row['reversed_at'] == null ? row[field] as int : 0));
}
