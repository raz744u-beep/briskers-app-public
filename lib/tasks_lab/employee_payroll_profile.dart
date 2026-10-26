// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../local/local_database_provider.dart';
import 'employee_advance_ledger.dart';
import 'payroll_week_projection.dart';
import 'payroll_period_projection.dart';
import 'package:drift/drift.dart' show Variable;
import 'payroll_history_panel.dart';
import '../services/local_job_tasks_lab_store.dart';
import 'weekly_labor_review_screen.dart';

/// A standalone, OFFLINE profile for the separate Tasks TEST Android package.
/// This surface does not call an API, issue 1099s, or post shop payroll.
class EmployeePayrollProfileLab extends StatefulWidget {
  const EmployeePayrollProfileLab({
    super.key,
    required this.employeeId,
    required this.name,
    required this.nickname,
    required this.role,
    required this.tasks,
    required this.allocationsByLine,
    required this.payments,
    required this.rateCents,
    this.initialTab = 0,
    this.initialWeek,
  });

  final String employeeId;
  final String name;
  final String nickname;
  final String role;
  final List<Map<String, dynamic>> tasks;
  final Map<String, List<Map<String, dynamic>>> allocationsByLine;
  final List<Map<String, dynamic>> payments;
  final int? rateCents;
  final int initialTab;
  final DateTime? initialWeek;

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
  List<Map<String, dynamic>> _drafts = const [];
  List<Map<String, dynamic>> _payments = const [];
  List<Map<String, dynamic>> _taskPayments = const [];
  String _payrollPeriod = 'This Week';
  DateTimeRange? _customPeriod;
  DateTime _repaymentDate = DateTime.now();
  String _repaymentMethod = 'Payroll deduction';
  bool _advanceExpanded = false;
  bool _editingOpening = false;
  bool _saving = false;
  LabAdvanceSnapshot? _advance;

  static final _currency = NumberFormat.simpleCurrency(locale: 'en_US');
  String _money(int cents) => _currency.format(cents / 100);
  static final _date = DateFormat('MMM d, yyyy');

  @override
  void initState() {
    super.initState();
    _week = widget.initialWeek ?? DateTime.now();
    _payments = widget.payments;
    _loadLedger();
    _refreshPayrollData();
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

  Future<void> _refreshPayrollData() async {
    try {
      final drafts = await LabPayrollWeekSource.readDrafts();
      final payments = await LocalJobTasksLabStore(localDatabase)
          .payrollTestPayments(LabPayrollWeekSource.businessId);
      await localDatabase.customStatement('''
        CREATE TABLE IF NOT EXISTS lab_payroll_task_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
          document_id TEXT NOT NULL, line_id TEXT NOT NULL,
          week_key TEXT NOT NULL, description TEXT NOT NULL,
          hours REAL NOT NULL, cents INTEGER NOT NULL,
          method TEXT NOT NULL, note TEXT NOT NULL DEFAULT '',
          paid_at INTEGER NOT NULL
        )
      ''');
      final linked = await localDatabase.customSelect(
        'SELECT employee_id, week_key, hours, cents, paid_at '
        'FROM lab_payroll_task_payments '
        'WHERE business_id=? AND employee_id=?',
        variables: [
          const Variable<String>(LabPayrollWeekSource.businessId),
          Variable<String>(widget.employeeId),
        ],
      ).get();
      if (!mounted) { return; }
      setState(() { _drafts = drafts; _payments = payments;
        _taskPayments = linked.map((r) => Map<String, dynamic>.from(r.data)).toList(); });
    } catch (error) {
      _snack('Unable to load TEST payroll summary: ' + error.toString());
    }
  }

  Widget _financeMetric(String label, String value, {Color? color}) =>
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
          fontSize: 10.5, color: Color(0xFF64748B))),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, child: Text(value,
          style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800,
            color: color ?? const Color(0xFF17212B)))),
      ],
    ));

  // ignore: unused_element
  Future<void> _recordTestPayment() async {
    final amount = TextEditingController();
    final note = TextEditingController();
    var method = 'zelle';
    var paymentDate = DateTime.now();
    final chosen = await showDialog<bool>(
      context: context,
      builder: (outer) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Add Payment · TEST'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Offline test payment only. '
                'No Briskers shop money is posted.',
                style: TextStyle(fontSize: 12,
                  color: Color(0xFF80541A))),
              const SizedBox(height: 9),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
                decoration: const InputDecoration(
                  prefixText: r'$ ', labelText: 'Amount paid',
                  border: OutlineInputBorder())),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(
                  labelText: 'Payment method',
                  border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'check', child: Text('Check')),
                  DropdownMenuItem(value: 'zelle', child: Text('Zelle')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                  DropdownMenuItem(value: 'ach', child: Text('ACH')),
                ],
                onChanged: (value) {
                  if (value != null) update(() => method = value);
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_date.format(paymentDate)),
                onPressed: () async {
                  final value = await showDatePicker(
                    context: dialog,
                    initialDate: paymentDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                  if (value != null) update(() => paymentDate = value);
                },
              ),
              TextField(controller: note,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)')),
            ],
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final dollars = double.tryParse(amount.text.trim());
                if (dollars == null || !dollars.isFinite ||
                    dollars <= 0 || dollars > 1000000) { return; }
                Navigator.pop(dialog, true);
              },
              child: const Text('Save TEST Payment')),
          ],
        ),
      ),
    );
    if (chosen == true) {
      final dollars = double.tryParse(amount.text.trim())!;
      try {
        await LocalJobTasksLabStore(localDatabase).recordLabPayrollPayment(
          businessId: LabPayrollWeekSource.businessId,
          employeeId: widget.employeeId,
          cents: (dollars * 100).round(),
          kind: 'pay',
          method: method.toLowerCase(),
          note: note.text, paidAt: paymentDate,
        );
        await _refreshPayrollData();
      } catch (error) {
        _snack('TEST payment not saved: ' + error.toString());
      }
    }
    amount.dispose();
    note.dispose();
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
        Text(widget.nickname, maxLines: 1, overflow: TextOverflow.ellipsis,
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

  Widget _tasksTab() => WeeklyLaborReviewLab(
    employeeId: widget.employeeId,
    employeeName: widget.nickname,
    tasks: _employeeTasks,
    hoursOf: _hours,
    rateCents: widget.rateCents,
    week: _week,
    embedded: true,
    onCancel: () => Navigator.of(context).pop(),
    onWeekChanged: (date) => _week = date,
    onPaymentSaved: _refreshPayrollData,
  );

  ({DateTime from, DateTime until}) _periodBounds() {
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    final monday = LabPayrollPeriodProjection.weekMonday(today);
    final tomorrow = midnight.add(const Duration(days: 1));
    switch (_payrollPeriod) {
      case 'This Week':
        return (from:monday,until:monday.add(const Duration(days: 7)));
      case 'Last Week':
        return (from:monday.subtract(const Duration(days: 7)),until:monday);
      case 'Last 30 Days':
        return (from:midnight.subtract(const Duration(days: 29)),until:tomorrow);
      case 'Last 3 Months':
        return (from:DateTime(today.year,today.month-2),until:tomorrow);
      case 'Last 6 Months':
        return (from:DateTime(today.year,today.month-5),until:tomorrow);
      case 'Year to Date':
        return (from:DateTime(today.year),until:tomorrow);
      case 'All Time':
        return (from:DateTime(2000),until:DateTime(2100));
      case 'Custom':
        if (_customPeriod != null) {
          return (from:DateTime(_customPeriod!.start.year,
            _customPeriod!.start.month,_customPeriod!.start.day),
            until:DateTime(_customPeriod!.end.year,
              _customPeriod!.end.month,_customPeriod!.end.day)
              .add(const Duration(days: 1)));
        }
        return (from:monday,until:monday.add(const Duration(days: 7)));
      default:
        return (from:monday,until:monday.add(const Duration(days: 7)));
    }
  }

  LabPayrollPeriodProjection _projectPeriod(DateTime from, DateTime until) =>
    LabPayrollPeriodProjection.calculate(
      employeeId: widget.employeeId,
      from:from, until:until,
      hourlyRateCents:widget.rateCents,
      drafts:_drafts, payments:_payments,
      taskPayments:_taskPayments,
    );

  Future<void> _setPayrollPeriod(String? next) async {
    if (next == null) return;
    if (next == 'Custom') {
      final chosen = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDateRange: _customPeriod,
      );
      if (chosen != null && mounted) {
        setState(() { _customPeriod = chosen; _payrollPeriod = next; });
      }
      return;
    }
    setState(() => _payrollPeriod = next);
  }

  Widget _payrollTab() {
    final period = _periodBounds();
    final current = _projectPeriod(period.from, period.until);
    final overall = _projectPeriod(DateTime(2000), DateTime(2100));
    final previous = overall.balanceCents == null || current.balanceCents == null
      ? null : (overall.balanceCents! - current.balanceCents!)
        .clamp(0, 1000000000).toInt();
    final outsideLabel = _payrollPeriod == 'This Week'
      ? 'Previous weeks' : 'Outside period';
    const options = [
      'This Week', 'Last Week', 'Last 30 Days', 'Last 3 Months',
      'Last 6 Months', 'Year to Date', 'All Time', 'Custom',
    ];
    return ListView(
      padding: const EdgeInsets.all(11),
      children: [
        _panel(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Expanded(child: Text('Payroll summary',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              SizedBox(width: 166, child: DropdownButtonFormField<String>(
                key: ValueKey('employee-payroll-period-dropdown-$_payrollPeriod'),
                initialValue: _payrollPeriod,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8,
                    vertical: 9),
                  border: OutlineInputBorder()),
                items: options.map((label) => DropdownMenuItem(
                  value: label, child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: _setPayrollPeriod,
              )),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _financeMetric('Hours',
                current.hours?.toStringAsFixed(1) ?? '—'),
              _financeMetric('Gross', _moneyNullable(current.grossCents)),
              _financeMetric('Paid', _money(current.paidCents)),
              _financeMetric('Balance', _moneyNullable(current.balanceCents),
                color: const Color(0xFFCC6222)),
            ]),
            const SizedBox(height: 12),
            Builder(builder: (tabContext) => SizedBox(
              height: 41,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF007E78)),
                onPressed: () =>
                  DefaultTabController.of(tabContext).animateTo(0),
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('Review Weekly Labor'),
              ),
            )),
          ],
        )),
        _panel(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Outstanding balance (all weeks)',
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 9),
            Row(children: [
              _financeMetric(outsideLabel,
                previous == null ? '—' : _money(previous),
                color: const Color(0xFFCC6222)),
              const SizedBox(width: 8),
              _financeMetric('Selected period',
                current.balanceCents == null
                  ? '—' : _money(current.balanceCents!),
                color: const Color(0xFFCC6222)),
            ]),
            const Divider(height: 20),
            const Text('Total amount owed',
              style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700)),
            Text(overall.balanceCents == null
                ? '—' : _money(overall.balanceCents!),
              style: const TextStyle(
                fontSize: 25, fontWeight: FontWeight.w800,
                color: Color(0xFFC76023))),
          ],
        )),
        _advancePanel(),
        const Padding(
          padding: EdgeInsets.all(7),
          child: Text('OFFLINE TEST: amounts are projections from '
            'saved weekly records and dated test payments; '
            'they do not verify production payroll posting.',
            style: TextStyle(fontSize: 11,
              color: Color(0xFF64748B))),
        ),
      ],
    );
  }

  String _moneyNullable(int? cents) =>
    cents == null ? '—' : _money(cents);

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

  Widget _reportsTab() => Builder(
    builder: (inner) => LabPayrollHistoryPanel(
      employeeId: widget.employeeId,
      rateCents: widget.rateCents,
      drafts: _drafts,
      payments: _payments,
      onWeekTap: (date) {
        setState(() => _week = date);
        DefaultTabController.of(inner).animateTo(1);
      },
    ),
  );

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
    initialIndex: widget.initialTab,
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
