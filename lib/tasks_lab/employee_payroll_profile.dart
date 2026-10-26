import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../local/local_database_provider.dart';
import 'employee_advance_ledger.dart';
import 'weekly_labor_review_screen.dart';

/// A standalone, OFFLINE profile for the separate Tasks TEST Android package.
/// This surface does not call an API, issue 1099s, or post shop payroll.
class EmployeePayrollProfileLab extends StatefulWidget {
  const EmployeePayrollProfileLab({
    super.key,
    required this.employeeId,
    required this.name,
    required this.role,
    required this.tasks,
    required this.allocationsByLine,
    required this.payments,
    required this.rateCents,
  });

  final String employeeId;
  final String name;
  final String role;
  final List<Map<String, dynamic>> tasks;
  final Map<String, List<Map<String, dynamic>>> allocationsByLine;
  final List<Map<String, dynamic>> payments;
  final int? rateCents;

  @override
  State<EmployeePayrollProfileLab> createState() =>
      _EmployeePayrollProfileLabState();
}

class _EmployeePayrollProfileLabState extends State<EmployeePayrollProfileLab> {
  static const _shop = 'briskers-tasks-test-only';
  final _ledger = LabAdvanceLedger(localDatabase);
  final _opening = TextEditingController();
  final _repayment = TextEditingController();
  final _note = TextEditingController();
  DateTime _week = DateTime.now();
  DateTime _repaymentDate = DateTime.now();
  String _repaymentMethod = 'Payroll deduction';
  String _reportRange = 'Year to Date';
  DateTimeRange? _customRange;
  bool _advanceExpanded = false;
  bool _editingOpening = false;
  bool _saving = false;
  LabAdvanceSnapshot? _advance;

  static final _currency = NumberFormat.simpleCurrency(locale: 'en_US');
  String _money(int cents) => _currency.format(cents / 100);
  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  static DateTime _start(DateTime date) =>
      _day(date).subtract(Duration(days: date.weekday - 1));
  static DateTime _end(DateTime date) =>
      _start(date).add(const Duration(days: 7));
  static final _date = DateFormat('MMM d, yyyy');

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  Future<void> _loadLedger() async {
    try {
      final latest = await _ledger.read(_shop, widget.employeeId);
      if (!mounted) return;
      setState(() {
        _advance = latest;
        if (!_editingOpening) {
          _opening.text = (latest.openingCents / 100).toStringAsFixed(2);
        }
      });
    } catch (error) {
      _snack('Could not read test ledger: $error');
    }
  }

  @override
  void dispose() {
    _opening.dispose();
    _repayment.dispose();
    _note.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  int? _cents(String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null || !value.isFinite || value < 0 || value > 1000000) {
      return null;
    }
    return (value * 100).round();
  }

  Future<void> _saveOpening() async {
    final cents = _cents(_opening.text);
    if (cents == null) {
      _snack('Enter a valid opening balance');
      return;
    }
    setState(() => _saving = true);
    try {
      await _ledger.setOpening(
        businessId: _shop,
        employeeId: widget.employeeId,
        openingCents: cents,
      );
      if (!mounted) return;
      setState(() => _editingOpening = false);
      await _loadLedger();
      _snack('TEST opening balance saved on this device');
    } catch (error) {
      _snack('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveRepayment() async {
    final cents = _cents(_repayment.text);
    if (cents == null || cents == 0) {
      _snack('Enter a positive repayment');
      return;
    }
    setState(() => _saving = true);
    try {
      await _ledger.repay(
        businessId: _shop,
        employeeId: widget.employeeId,
        cents: cents,
        method: _repaymentMethod,
        date: _repaymentDate,
        note: _note.text,
      );
      _repayment.clear();
      _note.clear();
      await _loadLedger();
      _snack('TEST repayment saved; no real payroll has changed');
    } catch (error) {
      _snack('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  IconData get _positionIcon {
    switch (widget.role) {
      case 'owner': return Icons.shield_outlined;
      case 'secretary': return Icons.headset_mic_outlined;
      default: return Icons.build_outlined;
    }
  }

  Map<String, dynamic>? _assignmentFor(
    Map<String, dynamic> task,
  ) {
    final line = task['line_id']?.toString() ?? '';
    final allocations = widget.allocationsByLine[line] ?? const [];
    if (allocations.isNotEmpty) {
      for (final allocation in allocations) {
        if (allocation['employee_id']?.toString() == widget.employeeId) {
          return allocation;
        }
      }
      return null;
    }
    return task['employee_id']?.toString() == widget.employeeId
        ? task : null;
  }

  double _hours(Map<String, dynamic> task) {
    final assignment = _assignmentFor(task);
    if (assignment == null) return 0;
    final raw = assignment['hours'] ?? assignment['payroll_hours'];
    final hours = raw is num ? raw.toDouble() :
        double.tryParse(raw?.toString() ?? '') ?? 0;
    return hours.isFinite && hours >= 0 ? hours : 0;
  }

  List<Map<String, dynamic>> get _employeeTasks =>
      widget.tasks.where((task) =>
          _assignmentFor(task) != null &&
          task['source_missing'] != 1).toList();

  List<Map<String, dynamic>> get _weekDone {
    final begin = _start(_week);
    final end = _end(_week);
    return _employeeTasks.where((task) {
      if (task['status'] != 'done') return false;
      final timestamp = task['completed_at'];
      if (timestamp is! int || timestamp <= 0) return false;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return !date.isBefore(begin) && date.isBefore(end);
    }).toList();
  }



  Widget _panel(Widget child) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: child,
    ),
  );

  void _showDetails() {
    Navigator.push<void>(context, MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Employee Details')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ListTile(leading: Icon(_positionIcon, size: 35),
            title: Text(widget.name), subtitle: Text(widget.role)),
          const Divider(),
          ListTile(title: const Text('Hourly rate (TEST)'),
            trailing: Text(widget.rateCents == null
                ? 'Not set' : '${_money(widget.rateCents!)}/hr')),
          const ListTile(title: Text('Phone, email and address'),
            subtitle: Text('Not copied into this isolated test app')),
          const ListTile(title: Text('SSN and W-9'),
            subtitle: Text('Protected information is not available in TEST')),
          const ListTile(title: Text('Default payment method'),
            subtitle: Text('To be linked after the payment-method contract')),
          const ListTile(title: Text('Position icon'),
            subtitle: Text('Role-based icon; individual selection is planned')),
        ]),
      ),
    ));
  }

  Widget _header() => Row(children: [
    CircleAvatar(
      radius: 25,
      backgroundColor: const Color(0xFFDDECFD),
      child: Icon(_positionIcon, size: 25, color: BriskersColors.jobs),
    ),
    const SizedBox(width: 10),
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        Text(widget.role == 'mechanic' ? 'Mechanic · Active'
          : widget.role + ' · Active',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ],
    )),
    OutlinedButton.icon(
      onPressed: _showDetails,
      icon: const Icon(Icons.person_outline, size: 17),
      label: const Text('Details'),
    ),
  ]);

  Future<void> _pickWeek() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _week,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Choose any date in the payroll week',
    );
    if (chosen != null && mounted) {
      setState(() { _week = chosen; });
    }
  }

  Widget _weekPicker() {
    final start = _start(_week);
    final end = _end(_week).subtract(const Duration(days: 1));
    final current = _start(DateTime.now()) == start;
    return Row(children: [
      IconButton(
        onPressed: () => setState(() {
          _week = _week.subtract(const Duration(days: 7));
         
        }),
        icon: const Icon(Icons.chevron_left)),
      Expanded(child: InkWell(
        onTap: _pickWeek,
        child: Column(children: [
          Text('${DateFormat('MMM d').format(start)} – '
            '${DateFormat('MMM d, yyyy').format(end)}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(current ? 'Current week' : start.isAfter(DateTime.now())
            ? 'Future week' : 'Selected past week',
            style: const TextStyle(color: Color(0xFF64748B),
              fontSize: 12)),
        ]),
      )),
      IconButton(
        onPressed: () => setState(() {
          _week = _week.add(const Duration(days: 7));
         
        }),
        icon: const Icon(Icons.chevron_right)),
      IconButton(
        tooltip: 'Return to current week',
        onPressed: () => setState(() {
          _week = DateTime.now();
         
        }),
        icon: const Icon(Icons.today_outlined)),
    ]);
  }

  Widget _tasksTab() {
    final tasks = _employeeTasks;
    final active = tasks.where((t) => t['status'] != 'done').toList();
    final finished = tasks.where((t) => t['status'] == 'done').toList();
    Widget workGroup(String title, List<Map<String, dynamic>> rows) => _panel(
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800)),
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('None in this test fixture')),
        for (final t in rows)
          Column(children: [
            const Divider(height: 14),
            Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((t['custom_description'] ??
                    t['source_description'] ?? 'Task').toString(),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
                  Text('J-24 · ' + t['status'].toString(),
                    style: const TextStyle(fontSize: 11.5,
                      color: Color(0xFF64748B))),
                ],
              )),
              const SizedBox(width: 8),
              Text(_hours(t).toStringAsFixed(1) + ' hrs',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ]),
      ]),
    );
    return ListView(padding: const EdgeInsets.all(12), children: [
      _panel(Row(children: [
        const Icon(Icons.work_outline, color: BriskersColors.jobs),
        const SizedBox(width: 10),
        Expanded(child: Text('Assigned Jobs & Tasks · ' +
          tasks.length.toString(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
      ])),
      workGroup('J-24 · Active tasks', active),
      if (finished.isNotEmpty) workGroup('Completed work', finished),
      const Padding(padding: EdgeInsets.all(8), child: Text(
        'TEST fixture only. Actual job grouping and employee-first '
        'task creation are not connected to the shop database.',
        style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
      ),
    ]);
  }

  Future<void> _openWeeklyLabor() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => WeeklyLaborReviewLab(
        employeeId: widget.employeeId,
        employeeName: widget.name,
        tasks: _employeeTasks,
        hoursOf: _hours,
        rateCents: widget.rateCents,
        week: _week,
      )),
    );
    if (saved == true) _snack(
      'Offline TEST weekly labor draft saved. No payroll posted.');
  }

  Widget _payrollTab() {
    final isCurrent = _start(_week) == _start(DateTime.now());
    final isFuture = _start(_week).isAfter(DateTime.now());
    final earnedHours = _weekDone.fold<double>(0,
      (sum, task) => sum + _hours(task));
    final earnedCents = widget.rateCents == null
      ? null : (earnedHours * widget.rateCents!).round();

    return ListView(padding: const EdgeInsets.all(12), children: [
      _panel(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Weekly Payroll', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          _weekPicker(),
          const Divider(height: 22),
          Text(isCurrent ? 'Recorded earned through today (TEST)'
            : isFuture ? 'Future week · earned amount'
            : 'Recorded earnings for selected past week (TEST)',
            style: const TextStyle(fontSize: 12,
              color: Color(0xFF64748B))),
          const SizedBox(height: 5),
          Text(isFuture ? _money(0)
            : earnedCents == null ? 'Rate not set' : _money(earnedCents),
            style: const TextStyle(
              color: BriskersColors.jobs,
              fontSize: 25, fontWeight: FontWeight.w800)),
          if (!isFuture)
            Text(earnedHours.toStringAsFixed(1) +
              ' completed mechanic hrs · dated TEST work only',
              style: const TextStyle(fontSize: 12,
                color: Color(0xFF64748B))),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openWeeklyLabor,
            icon: const Icon(Icons.checklist),
            label: const Text('Review Weekly Labor'),
          ),
          const SizedBox(height: 7),
          const Text('Review opens job/task checkboxes, Select All, '
            'editable hours, suggested amount and fixed Cancel/Save footer. '
            'Open jobs can be selected in the current-week TEST draft.',
            style: TextStyle(fontSize: 11,
              color: Color(0xFF64748B))),
        ],
      )),
      // Do not manufacture an owed payroll balance from unfinished tasks.
      // An empty/unverified Outstanding Payroll Balance is hidden.
      _advancePanel(),
    ]);
  }

  Widget _advancePanel() {
    final snapshot = _advance;
    return _panel(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.handshake_outlined,
            color: BriskersColors.jobs),
          title: const Text('Advances & Repayments',
            style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Balance: '
            '${snapshot == null ? 'Loading' : _money(snapshot.remainingCents)}'),
          trailing: Icon(_advanceExpanded
            ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
          onTap: () => setState(() =>
            _advanceExpanded = !_advanceExpanded),
        ),
        if (_advanceExpanded) ...[
          const Divider(),
          Row(children: [
            Expanded(child: TextField(
              controller: _opening,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              readOnly: !_editingOpening,
              decoration: const InputDecoration(
                labelText: 'Original amount owed',
                prefixText: r'$ ', border: OutlineInputBorder()),
            )),
            const SizedBox(width: 8),
            if (_editingOpening)
              IconButton(
                tooltip: 'Save opening balance',
                onPressed: _saving ? null : _saveOpening,
                icon: const Icon(Icons.save_outlined))
            else
              IconButton(
                tooltip: 'Edit opening balance',
                onPressed: snapshot?.repayments.isNotEmpty == true
                  ? null : () => setState(() => _editingOpening = true),
                icon: const Icon(Icons.edit_outlined)),
          ]),
          const SizedBox(height: 10),
          Text('Remaining balance: '
            '${_money(snapshot?.remainingCents ?? 0)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 14),
          const Text('Add Repayment', style: TextStyle(
            fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          TextField(
            controller: _repayment,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount', prefixText: r'$ ',
              border: OutlineInputBorder()),
          ),
          const SizedBox(height: 9),
          OutlinedButton.icon(
            onPressed: () async {
              final date = await showDatePicker(
                context: context, initialDate: _repaymentDate,
                firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (date != null && mounted) {
                setState(() => _repaymentDate = date);
              }
            },
            icon: const Icon(Icons.calendar_month),
            label: Text('Date: ${_date.format(_repaymentDate)}'),
          ),
          const SizedBox(height: 9),
          DropdownButtonFormField<String>(
            initialValue: _repaymentMethod,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Repayment method', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'Payroll deduction',
                child: Text('Payroll deduction')),
              DropdownMenuItem(value: 'Cash', child: Text('Cash')),
              DropdownMenuItem(value: 'Zelle', child: Text('Zelle')),
              DropdownMenuItem(value: 'Check', child: Text('Check')),
              DropdownMenuItem(value: 'ACH', child: Text('ACH')),
            ],
            onChanged: (value) => setState(() =>
              _repaymentMethod = value ?? 'Payroll deduction'),
          ),
          const SizedBox(height: 9),
          TextField(controller: _note, decoration:
            const InputDecoration(labelText: 'Notes (optional)',
              border: OutlineInputBorder())),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _saving ? null : _saveRepayment,
            child: const Text('Save Repayment (TEST)'),
          ),
          const SizedBox(height: 8),
          const Text('Method is recorded; selecting payroll deduction '
            'does not post or reduce real payroll in this TEST build.',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          const Divider(height: 25),
          const Text('Repayment History',
            style: TextStyle(fontWeight: FontWeight.w700)),
          if (snapshot?.repayments.isEmpty ?? true)
            const Padding(padding: EdgeInsets.all(8),
              child: Text('No repayments recorded')),
          for (final item in snapshot?.repayments ?? const <Map<String, dynamic>>[])
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${_money(item['cents'] as int)} · '
                "${item['method']}"),
              subtitle: Text(_date.format(
                DateTime.fromMillisecondsSinceEpoch(item['paid_at'] as int))),
              trailing: Text(_money(item['remaining_after_cents'] as int)),
            ),
        ],
      ],
    ));
  }

  List<Map<String, dynamic>> get _history {
    final today = _day(DateTime.now());
    DateTime start;
    DateTime end = today.add(const Duration(days: 1));
    switch (_reportRange) {
      case 'This Month':
        start = DateTime(today.year, today.month);
        break;
      case 'Last Month':
        start = DateTime(today.year, today.month - 1);
        end = DateTime(today.year, today.month);
        break;
      case 'Last 3 Months':
        start = DateTime(today.year, today.month - 2);
        break;
      case 'Last 6 Months':
        start = DateTime(today.year, today.month - 5);
        break;
      case 'All':
        start = DateTime(2000);
        break;
      case 'Custom':
        start = _customRange?.start ?? DateTime(today.year);
        end = _customRange == null
          ? end : _customRange!.end.add(const Duration(days: 1));
        break;
      default:
        start = DateTime(today.year);
    }
    return widget.payments.where((p) {
      if (p['employee_id'] != widget.employeeId || p['kind'] != 'pay') {
        return false;
      }
      final raw = p['paid_at'];
      if (raw is! int) return false;
      final date = DateTime.fromMillisecondsSinceEpoch(raw);
      return !date.isBefore(start) && date.isBefore(end);
    }).toList();
  }

  Widget _reportsTab() {
    final history = _history;
    final sum = history.fold<int>(0,
      (n, row) => n + (row['cents'] as int));
    return Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _panel(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Payment History', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 9),
              DropdownButtonFormField<String>(
                key: ValueKey(_reportRange),
                initialValue: _reportRange,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Date range', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'This Month',
                    child: Text('This Month')),
                  DropdownMenuItem(value: 'Last Month',
                    child: Text('Last Month')),
                  DropdownMenuItem(value: 'Last 3 Months',
                    child: Text('Last 3 Months')),
                  DropdownMenuItem(value: 'Last 6 Months',
                    child: Text('Last 6 Months')),
                  DropdownMenuItem(value: 'Year to Date',
                    child: Text('Year to Date')),
                  DropdownMenuItem(value: 'All',
                    child: Text('All Time')),
                  DropdownMenuItem(value: 'Custom',
                    child: Text('Custom dates')),
                ],
                onChanged: (value) async {
                  if (value == 'Custom') {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDateRange: _customRange,
                    );
                    if (!mounted || range == null) return;
                    setState(() {
                      _reportRange = 'Custom';
                      _customRange = range;
                    });
                  } else {
                    setState(() => _reportRange = value ?? 'Year to Date');
                  }
                },
              ),
              const SizedBox(height: 12),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('No TEST payments in this period.'),
                ),
              for (final entry in history)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_money(entry['cents'] as int),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(entry['method'].toString() + ' · ' +
                    _date.format(DateTime.fromMillisecondsSinceEpoch(
                      entry['paid_at'] as int))),
                ),
            ],
          )),
          _panel(const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.bar_chart_outlined),
            title: Text('Work & Earnings Reports'),
            subtitle: Text(
              'Hours and productivity summaries require the '
              'verified Tasks-to-Payroll ledger.'),
          )),
        ],
      )),
      // Totals stay visible when payment history scrolls.
      Container(
        key: const Key('reports-fixed-payment-total'),
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFD6E0E8)))),
        child: Row(children: [
          Expanded(child: Text(
            'Total paid · ' + _reportRange,
            style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(_money(sum), style: const TextStyle(
            fontSize: 19, fontWeight: FontWeight.w800,
            color: BriskersColors.jobs)),
        ]),
      ),
    ]);
  }

  Widget _taxesTab() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _panel(const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Taxes & 1099', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w800)),
          SizedBox(height: 10),
          Text('Planned: your own earnings, federal / self-employment / '
            'Louisiana estimated taxes, suggested reserve and 1099-NEC.'),
          SizedBox(height: 10),
          Text('Tax calculations and 1099s are intentionally disabled '
            'until actual posted pay, classification, W-9 permissions '
            'and tax-year rules are verified.',
            style: TextStyle(color: Color(0xFF64748B))),
        ],
      )),
    ],
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(title: const Text('Employee Profile')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: _header()),
        const Material(
          color: Colors.white,
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: EdgeInsets.symmetric(horizontal: 20),
            tabs: [
              Tab(text: 'Tasks'),
              Tab(text: 'Payroll'),
              Tab(text: 'Reports'),
              Tab(text: 'Taxes'),
            ],
          ),
        ),
        Expanded(child: TabBarView(children: [
          _tasksTab(), _payrollTab(), _reportsTab(), _taxesTab(),
        ])),
      ]),
    ),
  );
}
