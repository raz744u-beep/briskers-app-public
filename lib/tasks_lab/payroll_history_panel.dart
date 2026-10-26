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
  });
  final String employeeId;
  final int? rateCents;
  final List<Map<String, dynamic>> drafts;
  final List<Map<String, dynamic>> payments;
  final void Function(DateTime) onWeekTap;

  @override
  State<LabPayrollHistoryPanel> createState() =>
      _LabPayrollHistoryPanelState();
}

class _LabPayrollHistoryPanelState extends State<LabPayrollHistoryPanel> {
  String _period = 'All';
  DateTimeRange? _custom;
  static final _date = DateFormat('MMM d, yyyy');
  static final _currency = NumberFormat.simpleCurrency(locale: 'en_US');

  String _money(int? value) =>
      value == null ? '—' : _currency.format(value / 100);

  bool _matches(DateTime week) {
    final today = DateTime.now();
    switch (_period) {
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
      setState(() => _period = chosen);
      return;
    }
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      initialDateRange: _custom);
    if (range != null && mounted) {
      setState(() { _custom = range; _period = chosen; });
    }
  }

  Widget _filterChip(String label) => Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: () => _change(label),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFDCE4E9)),
            color: _period == label
              ? const Color(0xFF007E78) : Colors.white),
          child: Text(label, style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w700,
            color: _period == label ? Colors.white
              : const Color(0xFF354052))),
        ),
      ),
    ),
  );

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
    if (!mounted) { return; }
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Week of ' +
          _date.format(LabPayrollWeekSource.dateForKey(week.weekKey))),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (rows.isEmpty)
                const Text('No task-linked TEST payments for this week.'),
              for (final row in rows)
                ListTile(
                  isThreeLine: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(row.read<String>('description'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('J-24 · ' +
                    row.read<double>('hours').toStringAsFixed(2) + ' hrs · ' +
                    row.read<String>('method').toUpperCase() + '\n' +
                    _date.format(DateTime.fromMillisecondsSinceEpoch(
                      row.read<int>('paid_at'))) +
                    (row.read<String>('note').isEmpty ? '' :
                      '\n' + row.read<String>('note'))),
                  trailing: Text(_money(row.read<int>('cents'))),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
            child: const Text('Close')),
        ],
      ),
    );
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
              const Icon(Icons.chevron_right, size: 20),
            ]),
            const SizedBox(height: 13),
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
    )).where((week) => _matches(
      LabPayrollWeekSource.dateForKey(week.weekKey))).toList();
    final paid = weeks.fold<int>(0, (sum, w) => sum + w.paidCents);
    int gross = 0;
    final complete = weeks.every((w) => w.grossCents != null);
    for (final w in weeks) { gross += w.grossCents ?? 0; }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 7),
        child: Row(children: [
          const Expanded(child: Text('Payroll History',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
          const Icon(Icons.history, color: BriskersColors.jobs),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 6),
        child: Row(children: [
          _filterChip('All'),
          _filterChip('2026'),
          _filterChip('2025'),
          _filterChip('Custom'),
        ]),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(alignment: Alignment.centerRight,
          child: DropdownButton<String>(
            value: const [
              'This Month','Last Month','Last 3 Months',
              'Last 6 Months','Year to Date',
            ].contains(_period) ? _period : null,
            hint: const Text('More date filters', style: TextStyle(
              fontSize: 12, color: Color(0xFF64748B))),
            items: const [
              'This Month','Last Month','Last 3 Months',
              'Last 6 Months','Year to Date',
            ].map((label) => DropdownMenuItem(
              value: label, child: Text(label))).toList(),
            onChanged: (value) {
              if (value != null) { _change(value); }
            },
          ),
        )),
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 9),
        children: [
          if (weeks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No TEST payroll weeks in this period.',
                style: TextStyle(color: Color(0xFF64748B)))),
          for (final week in weeks) _card(week),
        ],
      )),
      Container(
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
      ),
    ]);
  }
}
