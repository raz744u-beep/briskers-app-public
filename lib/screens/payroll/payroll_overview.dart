// ignore_for_file: prefer_const_constructors
// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/employee_role_style.dart';
import '../../services/payroll_period_totals.dart';
import '../../services/employee_nickname_store.dart';

class PayrollOverview extends StatefulWidget {
  const PayrollOverview({
    super.key, required this.employees, required this.work, required this.payments,
    required this.onOpenProfile, required this.onReviewWeek,
  });
  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> work;
  final List<Map<String, dynamic>> payments;
  final Future<void> Function(String, DateTime) onOpenProfile;
  final Future<void> Function(String, DateTime) onReviewWeek;
  @override
  State<PayrollOverview> createState() => _PayrollOverviewState();
}

class _PayrollOverviewState extends State<PayrollOverview> {
  DateTime _week = DateTime.now();
  static final _usd = NumberFormat.simpleCurrency(locale: 'en_US');
  static final _short = DateFormat('MMM d, yyyy');
  String _money(int? cents) => cents == null ? '—' : _usd.format(cents / 100);
  DateTime get _monday =>
      DateTime(_week.year, _week.month, _week.day - _week.weekday + 1);

  PayrollPeriodTotals _summary(String employee) => PayrollPeriodTotals.calculate(
    work: widget.work.where((row) => row['employee_id'] == employee),
    payments: widget.payments.where((row) => row['employee_id'] == employee),
    from: _monday, until: _monday.add(const Duration(days: 7)),
  );

  int? _previous(String employee) => PayrollPeriodTotals.calculate(
    work: widget.work.where((row) => row['employee_id'] == employee),
    payments: widget.payments.where((row) => row['employee_id'] == employee),
    from: DateTime(2000), until: _monday,
  ).balanceCents;

  int _taskCount(String employee) => _monday.isAfter(DateTime.now()) ? 0 :
    widget.work.where((row) => row['employee_id'] == employee &&
      row['paid'] != 1 && row['state'] == 'Done' && row['assignment_conflict']!=1 &&
      (DateTime.tryParse(row['completed_date']?.toString()??'')?.isBefore(_monday.add(const Duration(days:7)))??false)).length;

  Future<void> _pickWeek() async {
    final day = await showDatePicker(
      context: context, initialDate: _week,
      firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (day != null && mounted) { setState(() => _week = day); }
  }

  Widget _weekSelector() {
    final from = _monday;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: 'Previous week',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.chevron_left, size: 20),
        onPressed: () => setState(() =>
          _week = _week.subtract(const Duration(days: 7)))),
      InkWell(
        onTap: _pickWeek,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_month_outlined, size: 20,
            color: BriskersColors.jobs),
          const SizedBox(width: 5),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Week of', style: TextStyle(
              fontSize: 10, color: Color(0xFF0C6159))),
            Text(_short.format(from), style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800,
              color: Color(0xFF075C56))),
          ]),
        ]),
      ),
      IconButton(
        tooltip: 'Next week', visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.chevron_right, size: 20),
        onPressed: () => setState(() =>
          _week = _week.add(const Duration(days: 7)))),
    ]);
  }

  Widget _metric(String label, String value, {Color? color}) =>
    Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, maxLines: 1, style: const TextStyle(
        fontSize: 10, color: Color(0xFF637181))),
      const SizedBox(height: 3),
      FittedBox(fit: BoxFit.scaleDown, child: Text(value,
        style: TextStyle(fontSize: 13,
          color: color ?? const Color(0xFF101828),
          fontWeight: FontWeight.w800))),
    ]));

  Widget _employeeCard(Map<String, dynamic> employee) {
    final id = employee['id'] as String;
    final summary = _summary(id);
    final previous = _previous(id);
    final rate = employee['rate'] as int?;
    final rateLabel = rate == null || rate <= 0 ? 'Pay details'
      : _money(rate) + '/hr';
    final name = EmployeeNicknameStore.displayLabel(employee,widget.employees);
    final icon = employeeRoleStyle(
      (employee['position'] ?? employee['position_name'] ?? employee['role'])?.toString(),
    ).icon;
    return Card(
      color: Colors.white,
      elevation: 0.8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 9, 9, 8),
        child: Column(children: [
          InkWell(
            onTap: () => widget.onOpenProfile(id, _week),
            child: Row(children: [
              Icon(icon, color: BriskersColors.jobs, size: 31),
              const SizedBox(width: 4),
              SizedBox(
                width: 66,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w800)),
                    Text(rateLabel, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10,
                        color: Color(0xFF64748B))),
                  ],
                ),
              ),
              Container(width: 1, height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                color: const Color(0xFFDCE4E8)),
              _metric('Hours', summary.hasRecords
                ? summary.hours.toStringAsFixed(1) : '—'),
              _metric('Gross', _money(summary.grossCents)),
              _metric('Paid', _money(summary.paidCents)),
              _metric('Balance', _money(summary.balanceCents),
                color: summary.balanceCents == null
                  ? null : summary.balanceCents! > 0
                    ? const Color(0xFFDA6118) : const Color(0xFF0D8063)),
              const Icon(Icons.chevron_right, size: 17),
            ]),
          ),
          const SizedBox(height: 7),
          InkWell(
            onTap: () => widget.onOpenProfile(id, _week),
            child: Container(
              margin: const EdgeInsets.only(left: 85),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1EC),
                borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(
                horizontal: 7, vertical: 5),
              child: Row(children: [
                const Icon(Icons.access_time_outlined, size: 15,
                  color: Color(0xFF83563C)),
                const SizedBox(width: 4),
                const Expanded(child: Text('Outstanding from previous weeks',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5))),
                Text(_money(previous), style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800,
                  color: Color(0xFFC15C2F))),
                const Icon(Icons.chevron_right, size: 15),
              ]),
            ),
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 85),
            child: SizedBox(width: double.infinity, height: 34,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF007E78),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6))),
                onPressed: () async {
                  await widget.onReviewWeek(id, _week);

                },
                icon: const Icon(Icons.assignment_outlined, size: 17),
                label: FittedBox(fit: BoxFit.scaleDown,
                  child: Text('Review Weekly Labor (' +
                    _taskCount(id).toString() + ' tasks)',
                    style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700))),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _footer() {
    final summaries = widget.employees.where((e) =>
      e['role'] != 'owner').map((employee) =>
      _summary(employee['id'] as String)).toList();
    double hours = 0;
    int gross = 0, paid = 0, balance = 0;
    var complete = true;
    for (final s in summaries) {
      hours += s.hours;
      if (s.grossCents == null) complete = false;
      gross += s.grossCents ?? 0;
      paid += s.paidCents;
      balance += s.balanceCents ?? 0;
    }
    Widget total(String title, String value, Color color) =>
      Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title, maxLines: 1, style: const TextStyle(
          fontSize: 10, color: Color(0xFF64748B))),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, child: Text(value,
          style: TextStyle(
            color: color, fontSize: 15, fontWeight: FontWeight.w800))),
      ]));
    return Container(
      key: const Key('payroll-overview-fixed-totals'),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF2F7F8),
        border: Border(top: BorderSide(color: Color(0xFFDDE6E8)))),
      child: Row(children: [
        total('Total Hours', complete ? hours.toStringAsFixed(1) : '—',
          const Color(0xFF18212C)),
        total('Total Gross', complete ? _money(gross) : '—',
          const Color(0xFF18212C)),
        total('Total Paid', _money(paid),
          const Color(0xFF18212C)),
        total('Total Balance', complete ? _money(balance) : '—',
          const Color(0xFFCE6321)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Payroll', style: TextStyle(
              fontSize: 23, fontWeight: FontWeight.w800)),
            const Text('Select a week to review and pay mechanic labor.',
              style: TextStyle(
                fontSize: 10, color: Color(0xFF64748B))),
          ],
        )),
        _weekSelector(),
      ]),
    ),
    Expanded(child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 6),
          children: widget.employees.where((e) =>
            e['role'] != 'owner').map(_employeeCard).toList(),
        )),
    _footer(),
  ]);
}
