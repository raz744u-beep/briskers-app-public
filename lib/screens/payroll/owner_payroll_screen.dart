import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/employee_role_style.dart';

import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/invoice_labor_work_summary.dart';
import '../../services/local_owner_authorization.dart';
import '../../services/local_payroll_repository.dart';
import '../../services/payroll_lan_enrollment.dart';
import '../../services/payroll_lan_identity.dart';
import '../../services/payroll_lan_workflow.dart';
import '../jobs/job_detail_screen.dart';
import '../jobs/job_document_screen.dart';
import 'payroll_history_panel.dart';
import 'payroll_lan_controls.dart';
import 'weekly_labor_review_screen.dart';

class OwnerPayrollScreen extends StatefulWidget {
  const OwnerPayrollScreen({
    super.key,
    required this.businessId,
    this.jobId,
    this.invoiceId,
    this.invoiceLines = const [],
    this.reportsOnly = false,
    this.employeeId,
    this.employeeName,
    this.employeeRole,
    this.employeeActive = true,
    this.openEmployeeDetails,
  });

  static const enabled = bool.fromEnvironment('BRISKERS_ENABLE_OWNER_PAYROLL');

  final bool reportsOnly;
  final String? employeeId;
  final String? employeeName;
  final String? employeeRole;
  final bool employeeActive;
  final VoidCallback? openEmployeeDetails;
  final String businessId;
  final String? jobId;
  final String? invoiceId;
  final List<Map<String, dynamic>> invoiceLines;

  @override
  State<OwnerPayrollScreen> createState() => _OwnerPayrollScreenState();
}

class _OwnerPayrollScreenState extends State<OwnerPayrollScreen> {
  LocalOwnerGrant? _grant;
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _work = [];
  List<Map<String, dynamic>> _history = [];
  String? _employee;
  DateTime _week = DateTime.now();
  int? _advanceBalance;
  String _payrollPeriod = 'This Week';
  DateTimeRange? _customPeriod;
  static final _currency = NumberFormat.simpleCurrency(locale: 'en_US');
  String _money(int cents) => _currency.format(cents / 100);
  String _moneyNullable(int? cents) => cents == null ? '—' : _money(cents);
  String? _error;
  bool _busy = false;
  Timer? _lockCheck;
  final _historyUnlocked = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _lockCheck = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_grant == null || _busy) return;
      try {
        _assertOwner();
      } on StateError {
        _historyUnlocked.value = false;
        setState(() {
          _grant = null;
          _employee = null;
          _employees = [];
          _work = [];
          _history = [];
          _advanceBalance = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _lockCheck?.cancel();
    _historyUnlocked.dispose();
    super.dispose();
  }

  bool get _jobMode => widget.jobId != null;
  late final _repository = LocalPayrollRepository(
        localDatabase,
        business: widget.businessId,
        owner: true,
        assertOwnerGrant: _assertOwner,
      );

  void _assertOwner() {
    final grant = _grant;
    if (grant == null) throw StateError('Unlock Owner payroll first.');
    grant.assertValid(widget.businessId, grant.actorId);
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool verifyPayment = false,
    bool rethrowError = false,
  }) async {
    if (_busy) {
      if (rethrowError) throw StateError('Payroll is busy. Try again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var needsUnlock = verifyPayment;
      try {
        _assertOwner();
      } on StateError {
        needsUnlock = true;
      }
      if (needsUnlock) {
        _grant = await DeviceOwnerAuthorization.instance.authority
            .authorizeLocal(widget.businessId);
      }
      if (!mounted) return;
      await action();
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      if (rethrowError) rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final repository = _repository;
    final job = widget.jobId;
    final employees = job == null
        ? await repository.employees()
        : await repository.assignedEmployees(job);
    final employee = widget.employeeId ?? _employee ?? (employees.firstOrNull?['id'] as String?);
    final work = await repository.work(employee: _jobMode ? null : employee, job: job);
    final history = employee == null || _jobMode
        ? <Map<String, dynamic>>[]
        : await repository.historyWithWork(employee);
    final advance = employee == null || _jobMode ? null : await repository.advance(employee);
    _assertOwner();
    if (!mounted) return;
    _historyUnlocked.value = true;
    setState(() {
      _employees = employees;
      _employee = employee;
      _work = work;
      _history = history;
      _advanceBalance = advance;
    });
  }

  String _date(DateTime value) => value.toIso8601String().substring(0, 10);
  Future<PayrollLanWorkflow> _workflow(String employee) async {
    final identity = await PayrollLanIdentity.load();
    final enrollment = PayrollLanEnrollment(identity);
    final peer = await enrollment.ownerPeer(widget.businessId, employee);
    if (peer == null) throw StateError('Pair this employee device first.');
    _assertOwner();
    return PayrollLanWorkflow(
      database: localDatabase, identity: identity, peer: peer,
      assertLink: _assertOwner, assertOwner: _assertOwner,
      assertWriter: () => enrollment.assertWriter(widget.businessId, _grant!),
    );
  }

  Future<void> _designate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Designate this Owner phone?'),
        content: const Text('Do this once per shop, on the phone that will '
            'record all payroll payments. Keep using the same phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Designate')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final enrollment = PayrollLanEnrollment(await PayrollLanIdentity.load());
      await enrollment.designate(widget.businessId, _grant!);
      if (!mounted) return;
      await showPayrollLanCode(context, 'Owner device ID', enrollment.identity.deviceId);
    }, verifyPayment: true);
  }

  Future<void> _managePeer({required bool pair}) async {
    final employee = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(pair ? 'Pair employee device' : 'Sync with employee'),
        children: [
          for (final row in _employees)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, row[_jobMode ? 'employee_id' : 'id']),
              child: Text((row['employee_name'] ?? row['name'] ?? row['id']).toString()),
            ),
        ],
      ),
    );
    if (employee == null || !mounted) return;
    await _run(() async {
      if (!pair) {
        final workflow = await _workflow(employee);
        if (mounted) await showPayrollLanSync(context, workflow);
        return;
      }
      final device = await payrollLanInput(context, 'Pair employee device', 'Mechanic device ID');
      if (device == null || !mounted) return;
      final enrollment = PayrollLanEnrollment(await PayrollLanIdentity.load());
      final code = await enrollment.invite(
        business: widget.businessId, employee: employee,
        mechanicDevice: device, grant: _grant!,
      );
      if (!mounted) return;
      await showPayrollLanCode(context, 'Private pairing code', code);
    }, verifyPayment: pair);
  }

  Future<void> _assign(Map<String, dynamic> line) async {
    final employee = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Assign invoice labor'),
        children: [
          for (final employee in _employees)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, employee),
              child: Text((employee['employee_name'] ?? employee['employee_id']).toString()),
            ),
        ],
      ),
    );
    if (employee == null || !mounted) return;
    final employeeId = employee['employee_id'] as String;
    final name = (employee['name'] ?? employee['employee_name'] ?? employeeId).toString();
    var cents = employee['rate'] as int?;
    if (cents == null || cents <= 0) {
      final input = await payrollLanInput(context, 'Set hourly labor rate', 'Dollars per hour');
      if (input == null || !mounted) return;
      final amount = double.tryParse(input);
      if (amount == null || !amount.isFinite || amount <= 0 || amount > 100000) {
        setState(() => _error = 'Enter a valid hourly labor rate.');
        return;
      }
      cents = (amount * 100).round();
    }
    final rate = cents;
    await _run(() async {
      final workflow = await _workflow(employeeId);
      await workflow.assign(
        job: widget.jobId!, invoice: widget.invoiceId!, line: line['id'] as String,
        description: (line['description'] ?? line['name'] ?? 'Invoice labor').toString(),
        employeeName: name, rate: rate,
      );
    });
  }

  Future<void> _recordWeekly(
    DateTime week, DateTime date, String method,
    List<Map<String, dynamic>> selected, int adjustment, int repayment,
    int net, String reason,
  ) async {
    final employee = _employee;
    if (employee == null || selected.isEmpty) {
      throw StateError('Select payable work for this employee.');
    }
    final random = Random.secure();
    final operation = List.generate(16, (_) => random.nextInt(256)
        .toRadixString(16).padLeft(2, '0')).join();
    await _run(() async {
      final workflow = await _workflow(employee);
      final enrollment = PayrollLanEnrollment(await PayrollLanIdentity.load());
      await enrollment.assertWriter(widget.businessId, _grant!);
      await workflow.repository.bindPaymentAuthority(
        writerDeviceId: enrollment.identity.deviceId,
        assertVerifiedPairing: _assertOwner,
      );
      await workflow.pay(
        operation: operation,
        week: _date(week),
        date: _date(date),
        method: method,
        selected: selected,
        reason: reason,
        net: net,
        adjustment: adjustment,
        repayment: repayment,
      );
    }, verifyPayment: true, rethrowError: true);
  }

  void _openRecordedWork(String id, {required bool invoice}) {
    try {
      _assertOwner();
    } on StateError {
      _run(() async {});
      return;
    }
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => invoice
          ? JobDocumentScreen(
              businessId: widget.businessId, documentId: id, isOwner: true,
              roleCode: 'owner',
            )
          : JobDetailScreen(
              businessId: widget.businessId, jobId: id, roleCode: 'owner',
            ),
    ));
  }

  Widget _reports() => Scaffold(
    appBar: AppBar(title: Text(widget.employeeName ?? 'Payroll reports')),
    body: Column(children: [
      if (_grant == null || _error != null)
        FilledButton(
          onPressed: _busy ? null : () => _run(() async {}),
          child: const Text('Unlock Owner payroll'),
        ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (_grant != null && widget.employeeId == null && _employees.isNotEmpty)
        DropdownButton<String>(
          value: _employee,
          items: [
            for (final row in _employees)
              DropdownMenuItem(value: row['id'] as String, child: Text(row['name'].toString())),
          ],
          onChanged: _busy ? null : (value) {
            setState(() {
              _employee = value;
              _history = [];
            });
            _run(() async {});
          },
        ),
      if (_grant != null)
        Expanded(child: PayrollHistoryPanel(
          key: ValueKey(_employee),
          payments: _history,
          unlocked: _historyUnlocked,
          onOpenJob: (id) => _openRecordedWork(id, invoice: false),
          onOpenInvoice: (id) => _openRecordedWork(id, invoice: true),
        )),
    ]),
  );

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
  Widget _panel(Widget child) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: child,
    ),
  );

  Widget _header() => Row(children: [
    CircleAvatar(
      radius: 25,
      backgroundColor: const Color(0xFFDDECFD),
      child: Icon(employeeRoleStyle(widget.employeeRole).icon, size: 25, color: BriskersColors.jobs),
    ),
    const SizedBox(width: 10),
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.employeeName ?? 'Employee', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        Text('${widget.employeeRole ?? 'Employee'} · ${widget.employeeActive ? 'Active' : 'Inactive'}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ],
    )),
    OutlinedButton.icon(
      onPressed: widget.openEmployeeDetails,
      icon: const Icon(Icons.person_outline, size: 17),
      label: const Text('Details'),
    ),
  ]);

  ({DateTime from, DateTime until}) _periodBounds() {
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    final monday = midnight.subtract(Duration(days: today.weekday - 1));
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

  ({double? hours, int? grossCents, int paidCents, int? balanceCents})
      _projectPeriod(DateTime from, DateTime until) {
    if (_grant == null) {
      return (hours: null, grossCents: null, paidCents: 0, balanceCents: null);
    }
    bool within(Object? raw) {
      final date = DateTime.tryParse(raw?.toString() ?? '');
      return date != null && !date.isBefore(from) && date.isBefore(until);
    }

    final earned = _work.where((task) =>
        task['state'] == 'Done' && task['paid'] != 1 &&
        within(task['completed_date']));
    final payments = _history.where((payment) => within(payment['week']));
    final unpaid = earned.fold<int>(0, (sum, task) => sum + (task['gross_cents'] as int));
    final paidGross = payments.fold<int>(0, (sum, row) => sum + (row['gross'] as int));
    final net = payments.fold<int>(0, (sum, row) => sum + (row['net'] as int));
    final unpaidMinutes = earned.fold<int>(0, (sum, task) => sum + (task['actual_minutes'] as int));
    final paidMinutes = payments.expand((payment) => payment['work'] as List<Map<String, dynamic>>)
        .fold<int>(0, (sum, task) => sum + (task['actual_minutes'] as int? ?? 0));
    return (
      hours: (unpaidMinutes + paidMinutes) / 60,
      grossCents: unpaid + paidGross,
      paidCents: net,
      balanceCents: unpaid,
    );
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)))),
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
              _financeMetric('Transferred', _money(current.paidCents)),
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
        // No large empty balance panel when nothing positive is owed.
        if ((overall.balanceCents ?? 0) > 0)
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
        _panel(ExpansionTile(
          title: const Text('Advances & Repayments'),
          subtitle: Text(_advanceBalance == null
              ? 'Unlock to view balance' : 'Remaining owed · ${_money(_advanceBalance!)}'),
          children: [
            ListTile(
              title: const Text('Outstanding balance'),
              trailing: Text(_moneyNullable(_advanceBalance)),
            ),
          ],
        )),
      ],
    );
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
          Text('Your own earnings, federal / self-employment / '
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

  Widget _profile() => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(title: const Text('Employee Profile')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: _header()),
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
        if (_grant == null || _error != null)
          FilledButton(
            onPressed: _busy ? null : () => _run(() async {}),
            child: const Text('Unlock Owner payroll'),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_grant != null)
          Expanded(child: TabBarView(children: [
            WeeklyLaborReview(
              employeeId: widget.employeeId!,
              employeeName: widget.employeeName ?? 'Employee',
              tasks: _work, week: _week, embedded: true,
              advanceBalance: () => _repository.advance(widget.employeeId!),
              recordPayment: _recordWeekly,
              onWeekChanged: (week) => _week = week,
              onCancel: () => Navigator.of(context).pop(),
            ),
            _payrollTab(),
            PayrollHistoryPanel(
              payments: _history,
              unlocked: _historyUnlocked,
              onOpenJob: (id) => _openRecordedWork(id, invoice: false),
              onOpenInvoice: (id) => _openRecordedWork(id, invoice: true),
            ),
            _taxesTab(),
          ])),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => widget.reportsOnly ? _reports() : widget.employeeId != null ? _profile() : Scaffold(
        appBar: AppBar(title: Text(widget.reportsOnly
            ? 'Payroll reports'
            : _jobMode ? 'Job labor tasks' : 'Owner payroll')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton(
              onPressed: _busy ? null : () => _run(() async {}),
              child: Text(_grant == null ? 'Unlock Owner payroll' : 'Refresh'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_grant != null && !widget.reportsOnly) ...[
              TextButton(onPressed: _busy ? null : _designate,
                child: const Text('Designate Owner payment device')),
              TextButton(onPressed: _busy || _employees.isEmpty ? null : () => _managePeer(pair: true),
                child: const Text('Pair employee device')),
              TextButton(onPressed: _busy || _employees.isEmpty ? null : () => _managePeer(pair: false),
                child: const Text('Sync payroll over shop Wi-Fi')),
            ],
            if (_grant != null && _jobMode) ...[
              for (final line in widget.invoiceLines.where(isInvoiceLaborLine))
                if (line['id'] is String)
                  ListTile(
                    title: Text((line['description'] ?? line['name'] ?? 'Invoice labor').toString()),
                    trailing: TextButton(
                      onPressed: _busy || _employees.isEmpty ? null : () => _assign(line),
                      child: const Text('Assign'),
                    ),
                  ),
              if (_employees.isEmpty) const Text('No active assignment is saved for this job.'),
              for (final row in _work)
                ListTile(
                  title: Text(row['description'].toString()),
                  subtitle: Text('${row['employee_name']} · ${row['state']} · ${row['actual_minutes']} min'),

                ),
            ],
            if (_grant != null && !_jobMode) ...[
              if (_employees.isEmpty) const Text('No employee work has been recorded yet.'),
              if (_employees.isNotEmpty)
                DropdownButton<String>(
                  value: _employee,
                  items: [
                    for (final employee in _employees)
                      DropdownMenuItem(value: employee['id'] as String, child: Text(employee['name'].toString())),
                  ],
                  onChanged: _busy ? null : (value) {
                    setState(() {
                      _employee = value;
                      _work = [];
                      _history = [];
                                });
                    _run(() async {});
                  },
                ),
              if (_employee != null)
                FilledButton.icon(
                  onPressed: _busy ? null : () {
                    final employee = _employee!;
                    Navigator.of(context).push<bool>(MaterialPageRoute(
                      builder: (_) => WeeklyLaborReview(
                        employeeId: employee,
                        employeeName: _employees.where((row) => row['id'] == employee)
                            .firstOrNull?['name']?.toString() ?? 'Weekly payroll',
                        tasks: _work,
                        week: DateTime.now(),
                        advanceBalance: () => _repository.advance(employee),
                        recordPayment: _recordWeekly,
                      ),
                    ));
                  },
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('Review Weekly Labor'),
                ),
            ],
          ],
        ),
      );
}
