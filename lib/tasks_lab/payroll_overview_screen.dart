// ignore_for_file: prefer_const_constructors
// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import 'payroll_week_projection.dart';

/// Owner-provided three-screen visual baseline: screen 1, Payroll Overview.
/// This widget only reads an isolated TEST ledger; it cannot post live payroll.
class LabPayrollOverviewScreen extends StatefulWidget {
  const LabPayrollOverviewScreen({
    super.key, required this.employees, required this.nicknames,
    required this.rates, required this.payments,
    required this.tasks, required this.allocationsByLine,
    required this.onOpenProfile, required this.onReviewWeek,
  });

  final List<Map<String, String>> employees;
  final Map<String, String> nicknames;
  final Map<String, int> rates;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> tasks;
  final Map<String, List<Map<String, dynamic>>> allocationsByLine;
  final Future<void> Function(String, DateTime) onOpenProfile;
  final Future<void> Function(String, DateTime) onReviewWeek;

  @override
  State<LabPayrollOverviewScreen> createState() =>
      _LabPayrollOverviewScreenState();
}

class _LabPayrollOverviewScreenState extends State<LabPayrollOverviewScreen> {
  DateTime _week = DateTime.now();
  List<Map<String, dynamic>> _drafts = const [];
  bool _loading = true;
  String? _error;

  static final _usd = NumberFormat.simpleCurrency(locale: 'en_US');
  static final _short = DateFormat('MMM d, yyyy');
  String _money(int? cents) =>
      cents == null ? '—' : _usd.format(cents / 100);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant LabPayrollOverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.payments, widget.payments) ||
        !identical(oldWidget.tasks, widget.tasks)) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      final drafts = await LabPayrollWeekSource.readDrafts();
      if (!mounted) { return; }
      setState(() { _drafts = drafts; _error = null; _loading = false; });
    } catch (error) {
      if (!mounted) { return; }
      setState(() {
        _error = 'Offline TEST payroll drafts unavailable: ' + error.toString();
        _loading = false;
      });
    }
  }

  LabPayrollWeek _summary(String employeeId) =>
    LabPayrollWeekSource.summarize(
      employeeId: employeeId, week: _week,
      hourlyCents: widget.rates[employeeId],
      drafts: _drafts, payments: widget.payments,
    );

  int? _previous(String id) => LabPayrollWeekSource.previousBalance(
    employeeId: id, selectedWeek: _week,
    rateCents: widget.rates[id], drafts: _drafts,
    payments: widget.payments,
  );

  int _taskCount(String employeeId) {
    if (LabPayrollWeekSource.start(_week).isAfter(DateTime.now())) return 0;
    var n = 0;
    for (final task in widget.tasks) {
      if (task['source_missing'] == 1) continue;
      final alloc = widget.allocationsByLine[
        task['line_id']?.toString() ?? ''] ?? const [];
      final assigned = alloc.isNotEmpty
        ? alloc.any((row) => row['employee_id'] == employeeId)
        : task['employee_id'] == employeeId;
      if (assigned) n++;
    }
    return n;
  }

  Future<void> _pickWeek() async {
    final day = await showDatePicker(
      context: context, initialDate: _week,
      firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (day != null && mounted) { setState(() => _week = day); }
  }

  Widget _weekSelector() {
    final from = LabPayrollWeekSource.start(_week);
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

  Widget _employeeCard(Map<String, String> employee) {
    final id = employee['id']!;
    final summary = _summary(id);
    final previous = _previous(id);
    final rate = widget.rates[id];
    final rateLabel = rate == null ? 'Rate unset'
      : _money(rate) + '/hr';
    final name = employee['role'] == 'secretary'
      ? 'Karol'
      : widget.nicknames[id] ?? employee['nickname'] ??
        employee['name'] ?? 'Employee';
    final role = employee['role'];
    final icon = role == 'secretary'
      ? Icons.headset_mic_outlined
      : role == 'owner' ? Icons.shield_outlined
      : Icons.engineering_outlined;
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
              _metric('Hours', summary.hasDraft
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
                  if (mounted) await _refresh();
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
      _summary(employee['id']!)).toList();
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
    const Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 5),
      child: Align(alignment: Alignment.centerRight,
        child: Text('OFFLINE TEST · No real payroll posting',
          style: TextStyle(fontSize: 10, color: Color(0xFF815C22)))),
    ),
    if (_error != null) Padding(
      padding: const EdgeInsets.all(10),
      child: Text(_error!, style: const TextStyle(color: Colors.red))),
    Expanded(child: _loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 6),
          children: widget.employees.where((e) =>
            e['role'] != 'owner').map(_employeeCard).toList(),
        )),
    _footer(),
  ]);
}
