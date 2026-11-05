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
import '../../services/payroll_period_totals.dart';
import '../../services/offline_job_admin_service.dart';
import '../../services/payroll_lan_enrollment.dart';
import '../../services/payroll_lan_identity.dart';
import '../../services/payroll_owner_lease.dart';
import '../../services/payroll_owner_ledger.dart';
import 'owner_payroll_connection.dart';
import '../../services/payroll_lan_workflow.dart';
import '../jobs/job_detail_screen.dart';
import '../settings/employee_edit_screen.dart';
import '../jobs/job_document_screen.dart';
import 'payroll_history_panel.dart';
import 'payroll_lan_controls.dart';
import 'weekly_labor_review_screen.dart';
import 'tasks_workspace.dart';
import 'payroll_overview.dart';

class OwnerPayrollScreen extends StatefulWidget {
  const OwnerPayrollScreen({
    super.key,
    required this.businessId,
    this.jobId,
    this.invoiceId,
    this.invoiceLines = const [],
    this.jobInvoiceLabor = const {},
    this.reportsOnly = false,
    this.employeeId,
    this.employeeName,
    this.employeeRole,
    this.employeePayType,
    this.employeeHourlyCents,
    this.employeeActive = true,
    this.openEmployeeDetails,
    this.globalTasks = false,
    this.initialWeek,
    this.initialTab = 0,
  });

  static const enabled = bool.fromEnvironment('BRISKERS_ENABLE_OWNER_PAYROLL');

  final bool reportsOnly;
  final String? employeeId;
  final String? employeeName;
  final String? employeeRole;
  final String? employeePayType;
  final int? employeeHourlyCents;
  final bool employeeActive;
  final VoidCallback? openEmployeeDetails;
  final bool globalTasks;
  final DateTime? initialWeek;
  final int initialTab;
  final String businessId;
  final String? jobId;
  final String? invoiceId;
  final List<Map<String, dynamic>> invoiceLines;
  final Map<String, List<Map<String, dynamic>>> jobInvoiceLabor;

  @override
  State<OwnerPayrollScreen> createState() => _OwnerPayrollScreenState();
}

class _OwnerPayrollScreenState extends State<OwnerPayrollScreen> {
  LocalOwnerGrant? _grant;
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _work = [];
  List<Map<String, dynamic>> _taskSources = [];
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _overviewPayments = [];
  List<Map<String, dynamic>> _pendingPayments = [];
  bool _refreshingOwnerState = false;
  String? _employee;
  DateTime _week = DateTime.now();
  int? _advanceBalance;
  List<Map<String, dynamic>> _repayments = [];
  List<Map<String, dynamic>> _generalTasks = [];
  bool _showGeneralTasks = false;
  bool _advanceExpanded = false;
  bool _editingOpening = false;
  int? _openingAdvance;
  final _opening = TextEditingController();
  final _weeklyBasePreview = TextEditingController(text: '0.00');
  final _hourlySupplementPreview = TextEditingController(text: '0.00');
  final _approvedSupplementHours = TextEditingController(text: '0.00');
  final _weeklyAdjustmentPreview = TextEditingController(text: '0.00');
  bool _laborAdditionalToBase = false;
  bool _weeklyDefaultsLoaded = false;
  bool _settlingWeekly = false;
  final _repayment = TextEditingController();
  final _repaymentNote = TextEditingController();
  DateTime _repaymentDate = DateTime.now();
  String _repaymentMethod = 'Cash';
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
    _week = widget.initialWeek ?? DateTime.now();
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
          _taskSources = [];
          _history = [];
          _overviewPayments = [];
          _pendingPayments = [];
          _advanceBalance = null;
          _repayments = [];
          _openingAdvance = null;
          _editingOpening = false;
          _weeklyDefaultsLoaded = false;
          _weeklyBasePreview.clear();
          _hourlySupplementPreview.clear();
          _approvedSupplementHours.clear();
          _weeklyAdjustmentPreview.clear();
          _laborAdditionalToBase = false;
          _generalTasks = [];
        });
      }
    });
  }

  @override
  void dispose() {
    _lockCheck?.cancel();
    _historyUnlocked.dispose();
    _opening.dispose();
    _weeklyBasePreview.dispose();
    _hourlySupplementPreview.dispose();
    _approvedSupplementHours.dispose();
    _weeklyAdjustmentPreview.dispose();
    _repayment.dispose();
    _repaymentNote.dispose();
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
    var actionCompleted = false;
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
      if (!mounted) {
        if (rethrowError) throw StateError('Payroll screen closed.');
        return;
      }
      await action();
      actionCompleted = true;
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      if (rethrowError && !actionCompleted) rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final repository = _repository;
    if (widget.employeeId != null && widget.employeeName != null &&
        widget.employeeHourlyCents != null) {
      await repository.saveEmployeeCompensation(
        employee: widget.employeeId!, name: widget.employeeName!,
        rate: widget.employeeHourlyCents!,
        weeklyBase: ['fixed_weekly', 'flexible_weekly'].contains(widget.employeePayType),
      );
    }
    if (!mounted) return;
    final ownerConnection = await OwnerPayrollConnections.open(context, widget.businessId, _grant!);
    if (!_refreshingOwnerState) {
      _refreshingOwnerState = true;
      unawaited(ownerConnection.refresh(_grant!).then((_) async {
        if (mounted) await _load();
      }).catchError((Object _) {}).whenComplete(() => _refreshingOwnerState = false));
    }
    final pendingPayments = await PayrollOwnerLedger(localDatabase, widget.businessId).pending();
    await repository.refreshInvoiceTasks();
    final sources = await repository.tasks();
    final job = widget.jobId;
    final persistedEmployees = job == null
        ? await repository.employees()
        : await repository.assignedEmployees(job);
    final roster = job == null
        ? await OfflineJobAdminService().cachedEmployees(widget.businessId)
        : <Map<String, dynamic>>[];
    final employees = {
      for (final row in roster) row['id']: row,
      for (final row in persistedEmployees)
        row['id'] ?? row['employee_id']: {...?roster.where((candidate) =>
          candidate['id'] == row['id']).firstOrNull, ...row},
    }.values.toList();
    final overview = !widget.globalTasks && !widget.reportsOnly &&
        widget.employeeId == null && !_jobMode;
    final employee = widget.globalTasks || overview ? null :
        widget.employeeId ?? _employee ?? (employees.firstOrNull?['id'] as String?);
    final work = await repository.work(employee: _jobMode ? null : employee, job: job);
    final history = employee == null || _jobMode
        ? <Map<String, dynamic>>[] : await repository.historyWithWork(employee);
    final allPayments = <Map<String, dynamic>>[];
    if (overview) {
      for (final row in employees) {
        final id = row['id'];
        if (id is String) allPayments.addAll(await repository.historyWithWork(id));
      }
    }
    final advance = employee == null || _jobMode ? null : await repository.advance(employee);
    final repayments = employee == null || widget.employeeId == null || widget.reportsOnly
        ? <Map<String, dynamic>>[] : await repository.repaymentHistory(employee);
    final opening = employee == null || widget.employeeId == null || widget.reportsOnly
        ? null : await repository.openingAdvance(employee);
    final weeklyDefaults = employee == null || widget.employeeId == null ||
        widget.reportsOnly || _weeklyDefaultsLoaded
        ? null : await repository.weeklyDefaults(employee);
    final generalTasks = widget.globalTasks ? await repository.shopTasks()
        : employee == null || widget.employeeId == null || widget.reportsOnly
            ? <Map<String, dynamic>>[] : await repository.shopTasks(employee);
    _assertOwner();
    if (!mounted) return;
    _historyUnlocked.value = true;
    setState(() {
      _employees = employees;
      _overviewPayments = allPayments;
      _pendingPayments = employee == null ? pendingPayments :
          pendingPayments.where((row) => row['employee_id'] == employee).toList();
      _employee = employee;
      _work = work;
      _taskSources = sources;
      _history = history;
      _advanceBalance = advance;
      _repayments = repayments;
      _openingAdvance = opening;
      if (!_editingOpening) _opening.text = opening == null ? '' : (opening / 100).toStringAsFixed(2);
      _generalTasks = generalTasks;
      if (!_weeklyDefaultsLoaded) {
        _weeklyDefaultsLoaded = true;
        String amount(String key) =>
            ((weeklyDefaults?[key] as int? ?? 0) / 100).toStringAsFixed(2);
        _weeklyBasePreview.text = amount('base_cents');
        _hourlySupplementPreview.text = amount('hourly_cents');
        _approvedSupplementHours.text = '0.00';
        _weeklyAdjustmentPreview.text = amount('adjustment_cents');
        _laborAdditionalToBase = weeklyDefaults?['add_labor'] == 1;
      }
    });
  }

  String _date(DateTime value) => value.toIso8601String().substring(0, 10);
  Future<PayrollLanWorkflow> _workflow(String employee, {PayrollOwnerProof? ownerProof}) async {
    final identity = await PayrollLanIdentity.load();
    final enrollment = PayrollLanEnrollment(identity);
    final peer = await enrollment.ownerPeer(widget.businessId, employee);
    if (peer == null) throw StateError('Pair this employee device first.');
    _assertOwner();
    final workflow = PayrollLanWorkflow(
      database: localDatabase, identity: identity, peer: peer,
      assertLink: _assertOwner, assertOwner: _assertOwner,
      assertWriter: () => enrollment.assertWriter(widget.businessId, _grant!),
      ownerProof: ownerProof,
    );
    await workflow.queueRecordedPayments();
    return workflow;
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

  Future<void> _assign(String invoiceId, Map<String, dynamic> line, {String? jobId}) async {
    final job = jobId ?? widget.jobId;
    if (job == null) return;
    var candidates = <Map<String, dynamic>>[];
    await _run(() async { candidates = await _repository.assignedEmployees(job); });
    if (!mounted || _error != null) return;
    if (candidates.isEmpty) {
      setState(() => _error = 'Assign mechanics to this Job first.');
      return;
    }
    final employee = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Assign invoice labor'),
        children: [
          for (final employee in candidates)
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
      final identity = await PayrollLanIdentity.load();
      final peer = await PayrollLanEnrollment(identity).ownerPeer(widget.businessId, employeeId);
      if (peer == null) {
        await _repository.registerAssignedLabor(
          jobId: job, invoiceId: invoiceId, lineId: line['id'] as String,
          employeeId: employeeId, employeeName: name, rateCents: rate,
        );
      } else {
        final workflow = await _workflow(employeeId);
        await workflow.assign(
          job: job, invoice: invoiceId, line: line['id'] as String,
          description: (line['description'] ?? line['name'] ?? 'Invoice labor').toString(),
          employeeName: name, rate: rate,
        );
      }
    });
  }

  Future<void> _recordTaskProgress(Map<String, dynamic> row) async {
    final next = row['state'] == 'Open' ? 'In Progress' : 'Done';
    if (row['state'] == 'Done' || (row['paid_minutes'] as int? ?? 0) > 0) return;
    var minutes = row['actual_minutes'] as int;
    if (next == 'Done') {
      final value = await payrollLanInput(context, 'Complete mechanic work', 'Actual hours worked');
      if (!mounted || value == null) return;
      final hours = double.tryParse(value);
      if (hours == null || !hours.isFinite || hours <= 0 || hours > 10000) {
        setState(() => _error = 'Enter valid actual hours.');
        return;
      }
      minutes = (hours * 60).round();
    }
    await _run(() => _repository.updateWork(
      row['id'] as String, next, (minutes * 100 + 30) ~/ 60, _date(DateTime.now()),
      expectedRevision: row['version'] as int,
    ));
  }

  Future<void> _editEstimated(Map<String, dynamic> row) async {
    final input = await payrollLanInput(
      context, 'Mechanic estimated hours', 'Estimated hours for this mechanic',
    );
    if (input == null || !mounted) return;
    final hours = double.tryParse(input);
    if (hours == null || !hours.isFinite || hours < 0 || hours > 10000) {
      setState(() => _error = 'Enter valid estimated hours.');
      return;
    }
    await _run(() => _repository.setEstimatedMinutes(
      row['task_id'] as String, row['employee_id'] as String, (hours * 60).round(),
    ));
  }

  Widget _taskCard(Map<String, dynamic> row) => ListTile(
    onLongPress: row['source_kind'] == 'invoice' && row['source_active'] != 0 &&
        row['invoice_id'] is String && row['source_line_id'] is String
      ? () => _assign(row['invoice_id'] as String,
          {'id': row['source_line_id'], 'description': row['description']},
          jobId: row['job_id'] as String) : null,
    title: Text(row['description'] as String),
    subtitle: Text('${row['employee_name']} · ${row['state']} · '
      '${row['actual_minutes']} actual min · ${row['estimated_minutes'] ?? 0} estimated min · '
      '${row['pay_status'] ?? (row['paid'] == 1 ? 'Paid' : 'Unpaid')}'
      '${row['source_active'] == 0 ? ' · Removed from invoice' : ''}'),
    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: 'Edit mechanic estimated hours',
        icon: const Icon(Icons.edit_outlined, size: 19),
        onPressed: _busy ? null : () => _editEstimated(row),
      ),
      if (row['state'] != 'Done' && (row['paid_minutes'] as int? ?? 0) == 0 &&
          (row['source_active'] != 0 || row['state'] != 'Open'))
        TextButton(
          onPressed: _busy ? null : () => _recordTaskProgress(row),
          child: Text(row['state'] == 'Open' ? 'Start' : 'Complete'),
        ),
    ]),
  );

  Future<void> _addRecheck() async {
    final job = widget.jobId;
    if (job == null) return;
    final employee = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Assign recheck'),
        children: [
          for (final employee in _employees)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, employee),
              child: Text((employee['employee_name'] ?? employee['name']).toString()),
            ),
        ],
      ),
    );
    if (!mounted || employee == null) return;
    final description = await payrollLanInput(context, 'Additional job work / Recheck', 'Task description');
    if (!mounted || description == null || description.isEmpty) return;
    final estimated = await payrollLanInput(context, 'Mechanic estimated hours', 'Estimated hours');
    if (!mounted || estimated == null) return;
    final hours = double.tryParse(estimated);
    if (hours == null || !hours.isFinite || hours < 0 || hours > 10000) return;
    final rate = employee['rate'] as int?;
    if (rate == null || rate <= 0) {
      setState(() => _error = 'Save this employee’s hourly compensation first.');
      return;
    }
    final operation = _operationId();
    await _run(() async {
      final id = employee['employee_id'] as String;
      final name = (employee['name'] ?? employee['employee_name']).toString();
      final identity = await PayrollLanIdentity.load();
      final peer = await PayrollLanEnrollment(identity).ownerPeer(widget.businessId, id);
      if (peer == null) {
        await _repository.createRecheck(
          operation: operation, job: job, description: description,
          employee: id, name: name, rate: rate, estimatedMinutes: (hours * 60).round(),
        );
      } else {
        final workflow = await _workflow(id);
        await workflow.assignRecheck(
          operation: operation, job: job, description: description, employeeName: name,
          rate: rate, estimatedMinutes: (hours * 60).round(),
        );
      }
    });
  }

  Future<void> _recordWeekly(
    DateTime week, DateTime date, String method,
    List<Map<String, dynamic>> selected, int adjustment, int repayment,
    int net, String reason, int base,
  ) async {
    final employee = _employee;
    if (employee == null || (selected.isEmpty && base <= 0)) {
      throw StateError('Select payable work for this employee.');
    }
    final pending = PayrollOwnerLedger(localDatabase, widget.businessId);
    final request = {'employee': employee, 'week': _date(week), 'date': _date(date),
      'method': method, 'selected': selected, 'adjustment': adjustment,
      'repayment': repayment, 'net': net, 'reason': reason, 'base': base};
    // Stable intent identity survives a lost UI/transport response and restart.
    final operation = await PayrollOwnerLedger.operationFor(request);
    var recordedNew = false;
    await _run(() async {
      await pending.intent(request);
      final ledger = await _localPaymentLedger(operation: operation);
      if (base > 0) {
        await ledger.enableWeeklyBase(employee, widget.employeeName ?? _employeeLabel(employee));
      }
      final identity = await PayrollLanIdentity.load();
      final peer = await PayrollLanEnrollment(identity).ownerPeer(widget.businessId, employee);
      if (peer == null) {
        recordedNew = await ledger.verify(
          operation: operation, employee: employee, week: _date(week), date: _date(date),
          method: method, selected: selected, base: base, hourlyAdjustment: adjustment,
          adjustmentReason: reason, repayment: repayment, confirmedNet: net,
          beforeCommit: () => pending.resolve(operation),
        );
      } else {
        final workflow = await _workflow(employee, ownerProof: ledger.ownerProof);
        recordedNew = await workflow.pay(operation: operation, week: _date(week), date: _date(date), method: method,
          selected: selected, reason: reason, net: net, base: base,
          adjustment: adjustment, repayment: repayment, onRecorded: () => pending.resolve(operation));
      }
    }, verifyPayment: true, rethrowError: true);
    if (!recordedNew) throw const PayrollAlreadyRecorded();
  }

  String _operationId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256)
        .toRadixString(16).padLeft(2, '0')).join();
  }

  Future<LocalPayrollRepository> _localPaymentLedger({String? operation}) async {
    _assertOwner();
    final connection = await OwnerPayrollConnections.open(context, widget.businessId, _grant!);
    final proof = await connection.acquire(_grant!, operation ?? _operationId());
    return LocalPayrollRepository(
      localDatabase, business: widget.businessId, owner: true,
      deviceId: connection.lease.identity.deviceId, assertOwnerGrant: _assertOwner,
      ownerProof: proof,
    );
  }

  Future<PayrollLanWorkflow> _paymentWorkflow(String employee) async {
    final ledger = await _localPaymentLedger();
    return _workflow(employee, ownerProof: ledger.ownerProof);
  }

  Future<void> _saveOpening() async {
    final employee = _employee;
    final amount = double.tryParse(_opening.text.trim());
    if (employee == null || amount == null || !amount.isFinite ||
        amount <= 0 || amount > 1000000) {
      setState(() => _error = 'Enter a positive opening amount.');
      return;
    }
    await _run(() async {
      final workflow = await _paymentWorkflow(employee);
      await workflow.repository.recordOpeningAdvance(employee, (amount * 100).round());
      if (mounted) setState(() => _editingOpening = false);
    }, verifyPayment: true);
  }

  int? get _repaymentCents {
    final value = double.tryParse(_repayment.text.trim());
    if (value == null || !value.isFinite || value <= 0 || value > 1000000) return null;
    final cents = (value * 100).round();
    return cents > 0 && cents <= (_advanceBalance ?? 0) ? cents : null;
  }

  Future<void> _saveRepayment() async {
    final amount = _repaymentCents;
    final employee = _employee;
    if (amount == null || employee == null) return;
    await _run(() async {
      final workflow = await _paymentWorkflow(employee);
      await workflow.repository.recordRepayment(
        employee: employee, operation: _operationId(), amount: amount,
        date: _date(_repaymentDate), method: _repaymentMethod,
        note: _repaymentNote.text.trim(),
      );
      if (mounted) {
        _repayment.clear();
        _repaymentNote.clear();
      }
    }, verifyPayment: true);
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
        Expanded(child: _reportsPanel()),
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

  PayrollPeriodTotals _projectPeriod(DateTime from, DateTime until) =>
      PayrollPeriodTotals.calculate(work: _work, payments: _history, from: from, until: until);

  void _selectAmount(TextEditingController controller) {
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
  }

  Future<void> _saveFlexiblePaySettings() async {
    final employee = _employee;
    final base = double.tryParse(_weeklyBasePreview.text.trim());
    final hourly = double.tryParse(_hourlySupplementPreview.text.trim());
    final adjustment = double.tryParse(_weeklyAdjustmentPreview.text.trim());
    if (employee == null || base == null || hourly == null || adjustment == null ||
        !base.isFinite || !hourly.isFinite || !adjustment.isFinite ||
        base < 0 || base > 1000000 || hourly < 0 || hourly > 100000 ||
        adjustment.abs() > 1000000) {
      setState(() => _error = 'Enter valid weekly amounts and rates.');
      return;
    }
    await _run(() async => (await _localPaymentLedger()).saveWeeklyDefaults(
      employee, (base * 100).round(), (hourly * 100).round(),
      (adjustment * 100).round(), _laborAdditionalToBase,
    ));
  }

  Future<void> _finalizeFlexibleWeekly() async {
    final employee = _employee;
    if (_settlingWeekly || employee == null) return;
    setState(() => _settlingWeekly = true);
    try {
      await _confirmFlexibleWeekly(employee);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _settlingWeekly = false);
    }
  }

  Future<void> _confirmFlexibleWeekly(String employee) async {
    final base = double.tryParse(_weeklyBasePreview.text.trim());
    final rate = double.tryParse(_hourlySupplementPreview.text.trim());
    final adjustment = double.tryParse(_weeklyAdjustmentPreview.text.trim());
    final hours = double.tryParse(_approvedSupplementHours.text.trim());
    if (base == null || rate == null || adjustment == null || hours == null ||
        ![base, rate, adjustment, hours].every((value) => value.isFinite) ||
        base <= 0 || rate < 0 || hours < 0 || hours > 168 ||
        base > 1000000 || rate > 100000 || adjustment.abs() > 1000000) {
      throw ArgumentError('Enter valid weekly amounts and approved hours.');
    }
    final additional = _laborAdditionalToBase;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => WeeklyLaborReview(
        employeeId: employee, employeeName: widget.employeeName ?? _employeeLabel(employee),
        tasks: _work, week: _week,
        weeklyBaseCents: (base * 100).round(),
        weeklyAdjustmentCents: (adjustment * 100).round(),
        settlementRateCents: additional ? (rate * 100).round() : 0,
        requiredSupplementMinutes: additional ? (hours * 60).round() : null,
        settlementReason: additional
            ? 'Owner-approved weekly base and supplemental labor at ${_currency.format(rate)} per hour.'
            : 'Labor included in the weekly base. Selected credits receive coverage without an added hourly component.',
        advanceBalance: () => _repository.advance(employee),
        recordPayment: _recordWeekly,
      ),
    ));
    if (mounted) await _run(() async {});
  }

  Widget _flexibleWeeklyPreview(double trackedHours) {
    double value(TextEditingController input) =>
      double.tryParse(input.text.trim()) ?? 0;
    final base = value(_weeklyBasePreview);
    final rate = value(_hourlySupplementPreview);
    final adjustment = value(_weeklyAdjustmentPreview);
    final approvedHours = double.tryParse(
      _approvedSupplementHours.text.trim());
    // Never automatically add historical or previously paid hours.
    // A preview is invalid until the Owner enters safe supplemental hours.
    final validHours = approvedHours != null &&
      approvedHours.isFinite && approvedHours >= 0 &&
      approvedHours <= 168;
    final validMoney = [base, rate, adjustment].every((n) => n.isFinite) &&
      base >= 0 && rate >= 0 &&
      base <= 1000000 && rate <= 100000 &&
      adjustment.abs() <= 1000000;
    final supplement = _laborAdditionalToBase && validHours
      ? approvedHours * rate : 0.0;
    final total = base + supplement + adjustment;
    final validPreview = validHours && validMoney &&
      total.isFinite && total >= 0;
    Widget field(String label, TextEditingController controller) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true, decimal: true),
        onTap: () => _selectAmount(controller),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label,
          prefixText: r'$ ', isDense: true,
          border: const OutlineInputBorder()),
      );
    return _panel(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Flexible weekly pay',
          style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        const Text('Owner-adjustable estimate only. No payment is created.',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        const SizedBox(height: 10),
        field('Weekly base', _weeklyBasePreview),
        const SizedBox(height: 8),
        field('Hourly supplement rate', _hourlySupplementPreview),
        const SizedBox(height: 8),
        TextField(
          controller: _approvedSupplementHours,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onTap: () => _selectAmount(_approvedSupplementHours),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Approved supplemental hours this week',
            isDense: true, border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Add tracked labor to base'),
          subtitle: Text(_laborAdditionalToBase
            ? '${validHours ? approvedHours.toStringAsFixed(2) : 'Invalid'} approved hours × rate'
            : 'Labor included in base · no double counting'),
          value: _laborAdditionalToBase,
          onChanged: (v) => setState(() => _laborAdditionalToBase = v),
        ),
        Text('Tracked task allocations (all weeks): '
          '${trackedHours.toStringAsFixed(2)} hrs · Reference only. '
          'Previously paid hours must not be paid again.',
          style: const TextStyle(fontSize: 11,
            color: Color(0xFF64748B))),
        const SizedBox(height: 8),
        field('Other weekly adjustment (+/-)', _weeklyAdjustmentPreview),
        const SizedBox(height: 10),
        Text(validPreview
            ? 'Preview gross: ${_currency.format(total)}'
            : 'Preview unavailable · check amounts and hours',
          style: const TextStyle(fontWeight: FontWeight.w800,
            fontSize: 16)),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy || !validPreview ? null : _saveFlexiblePaySettings,
          child: const Text('Save weekly defaults')),
        const Text('Approved hours are a temporary preview and are not '
          'saved as payable coverage. Review actual unpaid labor before '
          'verifying any payment.',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy || _settlingWeekly || !validPreview || base <= 0 || total <= 0
            ? null : _finalizeFlexibleWeekly,
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Verify Weekly Payment'),
        ),
      ],
    ));
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
                current.hasRecords ? current.hours.toStringAsFixed(1) : '—'),
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
                onPressed: () {
                  setState(() => _showGeneralTasks = false);
                  DefaultTabController.of(tabContext).animateTo(0);
                },
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
        if (['fixed_weekly', 'flexible_weekly'].contains(widget.employeePayType) ||
            _work.every((row) => (row['rate_cents'] as int) <= 0))
          _flexibleWeeklyPreview(_work.fold<double>(
            0, (sum, row) => sum + (row['actual_minutes'] as int) / 60,
          )),
        _advancePanel(),
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

  Widget _advancePanel() {

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
            '${_moneyNullable(_advanceBalance)}'),
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
              onTapAlwaysCalled: true,
              onTap: () => _opening.selection = TextSelection(
                baseOffset: 0, extentOffset: _opening.text.length,
              ),
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
                onPressed: _busy ? null : _saveOpening,
                icon: const Icon(Icons.save_outlined))
            else
              IconButton(
                tooltip: 'Edit opening balance',
                onPressed: _busy || _openingAdvance != null || _history.isNotEmpty ||
                    _repayments.isNotEmpty || (_advanceBalance ?? 0) != 0
                  ? null : () => setState(() => _editingOpening = true),
                icon: const Icon(Icons.edit_outlined)),
          ]),
          const SizedBox(height: 10),
          Text('Remaining balance: '
            '${_moneyNullable(_advanceBalance)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 14),
          const Text('Add Repayment', style: TextStyle(
            fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          TextField(
            controller: _repayment,
            onTapAlwaysCalled: true,
            onTap: () => _repayment.selection = TextSelection(
              baseOffset: 0, extentOffset: _repayment.text.length,
            ),
            onChanged: (_) => setState(() {}),
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
            label: Text('Date: ${DateFormat.yMMMd().format(_repaymentDate)}'),
          ),
          const SizedBox(height: 9),
          DropdownButtonFormField<String>(
            initialValue: _repaymentMethod,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Repayment method', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'Cash', child: Text('Cash')),
              DropdownMenuItem(value: 'Zelle', child: Text('Zelle')),
              DropdownMenuItem(value: 'Check', child: Text('Check')),
              DropdownMenuItem(value: 'ACH', child: Text('ACH')),
            ],
            onChanged: (value) => setState(() =>
              _repaymentMethod = value ?? 'Cash'),
          ),
          const SizedBox(height: 9),
          TextField(controller: _repaymentNote, decoration:
            const InputDecoration(labelText: 'Notes (optional)',
              border: OutlineInputBorder())),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: !_busy && _repaymentCents != null ? _saveRepayment : null,
            child: const Text('Save Repayment'),
          ),
          const SizedBox(height: 8),
          const Text('Payroll deductions are optional during Verify Payment. '
            'Record separate cash, Zelle, check or ACH repayments here.',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          const Divider(height: 25),
          const Text('Repayment History',
            style: TextStyle(fontWeight: FontWeight.w700)),
          if (_repayments.isEmpty)
            const Padding(padding: EdgeInsets.all(8),
              child: Text('No repayments recorded')),
          for (final item in _repayments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${_money(item['cents'] as int)} · '
                "${item['method']}"),
              subtitle: Text(item['date'] as String),
              trailing: Text(_money(item['remaining_after_cents'] as int)),
            ),
        ],
      ],
    ));
  }

  Future<void> _createEmployeeGeneralTask() async {
    final employee = widget.employeeId ?? await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Assign general task'),
        children: [
          for (final row in _employees)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, row['id']),
              child: Text((row['nickname'] ?? row['name'] ?? row['id']).toString()),
            ),
        ],
      ),
    );
    if (employee == null || !mounted) return;
    final description = TextEditingController();
    String category = 'General';
    DateTime? due;
    var saving = false;
    final created = await showModalBottomSheet<bool>(
      context:context,useSafeArea:true,isScrollControlled:true,
      showDragHandle:true,
      builder:(sheet)=>StatefulBuilder(builder:(sheet, update)=>Padding(
        padding:EdgeInsets.fromLTRB(16,10,16,
          MediaQuery.viewInsetsOf(sheet).bottom+20),
        child:SingleChildScrollView(child:Column(
          mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text('New General Task · ${widget.employeeName ?? _employeeLabel(employee)}',
            style:const TextStyle(fontSize:19,fontWeight:FontWeight.w800)),
          const SizedBox(height:12),
          TextField(controller:description,minLines:1,maxLines:3,
            decoration:const InputDecoration(labelText:'Task description',
              border:OutlineInputBorder())),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(
            initialValue:category,
            decoration:const InputDecoration(labelText:'Category',
              border:OutlineInputBorder()),
            items:[
              for(final value in ['General','Cleaning','Inventory',
                'Office','Maintenance','Yard','Errands'])
                DropdownMenuItem(value:value,child:Text(value)),
            ],
            onChanged:(v)=>update(()=>category=v??'General')),
          const SizedBox(height:12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined),
            label: Text(due == null ? 'Set due date' : DateFormat.yMMMd().format(due!)),
            onPressed: saving ? null : () async {
              final date = await showDatePicker(
                context: sheet, initialDate: due ?? DateTime.now(),
                firstDate: DateTime(2020), lastDate: DateTime(2100),
              );
              if (date != null && sheet.mounted) update(() => due = date);
            },
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: saving ? null : () async {
            if (description.text.trim().isEmpty) return;
            update(() => saving = true);
            try {
              await _repository.addShopTask(
                employee, description.text, category, due: due,
              );
              if (sheet.mounted) Navigator.pop(sheet,true);
            } catch(error) {
              if (sheet.mounted) {
                update(() => saving = false);
                ScaffoldMessenger.of(sheet).showSnackBar(SnackBar(content: Text('$error')));
              }
            }
          },child:const Text('Save General Task')),
        ])),
      )),
    );
    description.dispose();
    if (created == true && mounted) await _run(() async {});
  }

  Future<void> _updateEmployeeGeneralTask(int id, String status) =>
      _run(() => _repository.setShopTaskStatus(widget.employeeId!, id, status));

  Widget _tasksTab() => Column(children:[
    Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),
      child:Row(children:[
        for(final general in [false,true])
          Expanded(child:InkWell(
            onTap:()=>setState(()=>_showGeneralTasks=general),
            child:Container(
              padding:const EdgeInsets.symmetric(vertical:9),
              decoration:BoxDecoration(
                color:_showGeneralTasks==general
                  ? const Color(0xFF007E78) : const Color(0xFFF2F6F7),
                borderRadius:BorderRadius.circular(16)),
              child:Text(general?'General Tasks':'Service Tasks',
                textAlign:TextAlign.center,
                style:TextStyle(fontWeight:FontWeight.w800,
                  color:_showGeneralTasks==general ? Colors.white :
                    const Color(0xFF334155)))))),
      ]),
    ),
    Expanded(child:_showGeneralTasks
      ? Builder(builder:(context) {
        final rows = _generalTasks;
        return ListView(padding:const EdgeInsets.all(12),children:[
          Row(children:[
            Expanded(child:Text('Assigned General Tasks · ${rows.length}',
              style:const TextStyle(fontWeight:FontWeight.w700))),
            TextButton.icon(onPressed:_createEmployeeGeneralTask,
              icon:const Icon(Icons.add),label:const Text('New Task')),
          ]),
          if(rows.isEmpty) const ListTile(
            title:Text('No general tasks assigned')),
          for(final task in rows)
            Card(child:ListTile(
              title:Text(task['description']?.toString()??'',
                style:const TextStyle(fontWeight:FontWeight.w700)),
              subtitle: Text('${task['category'] ?? 'General'} · ${switch (task['status']) {
                'done' => 'Completed',
                'in_progress' => 'In Progress',
                _ => 'Planned',
              }}'),
              trailing:PopupMenuButton<String>(
                tooltip:'Update task progress',
                onSelected:(status)=>_updateEmployeeGeneralTask(
                  task['id'] as int,status),
                itemBuilder:(_)=>const [
                  PopupMenuItem(value:'planned',child:Text('Not Started')),
                  PopupMenuItem(value:'in_progress',child:Text('In Progress')),
                  PopupMenuItem(value:'done',child:Text('Done')),
                ]))),
        ]);
      })
      : WeeklyLaborReview(
        employeeId: widget.employeeId!,
        employeeName: widget.employeeName ?? 'Employee',
        tasks: _work, week: _week, embedded: true,
        advanceBalance: () => _repository.advance(widget.employeeId!),
        recordPayment: _recordWeekly,
        onWeekChanged: (week) => _week = week,
        onCancel: () => Navigator.of(context).pop(),
      )),
  ]);

  String _employeeLabel(String? employee) {
    final row = _employees.where((row) => row['id'] == employee).firstOrNull;
    return (row?['nickname'] ?? row?['name'] ?? employee ?? 'Unassigned').toString();
  }

  Widget _workspace() {
    final byTask = <String, List<Map<String, dynamic>>>{};
    for (final row in _work) {
      (byTask[row['task_id'] as String] ??= []).add(row);
    }
    final service = [
      for (final entry in byTask.entries)
        {...entry.value.first,
          'line_id': entry.key,
          'document_id': entry.value.first['invoice_id'],
          'source_description': entry.value.first['description'],
          'status': entry.value.every((row) => row['state'] == 'Done') ? 'done'
              : entry.value.any((row) => row['state'] != 'Open') ? 'in_progress'
              : 'planned',
        },
    ];
    for (final task in _taskSources) {
      if (byTask.containsKey(task['id']) || task['source_active'] == 0) continue;
      service.add({
        ...task, 'line_id': task['id'], 'document_id': task['invoice_id'],
        'source_description': task['description'], 'status': 'planned',
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: Column(children: [
        if (_grant == null || _error != null)
          FilledButton(
            onPressed: _busy ? null : () => _run(() async {}),
            child: const Text('Unlock Owner tasks'),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_grant != null)
          Expanded(child: TasksWorkspace(
            serviceTasks: service,
            generalTasks: _generalTasks,
            allocationsByLine: byTask,
            employeeName: _employeeLabel,
            employeeIds: [
              for (final row in _employees)
                if (row['id'] case final String id) id,
            ],
            serviceTaskCard: (row) => byTask.containsKey(row['line_id'])
                ? Column(children: [for (final allocation in byTask[row['line_id']]!) _taskCard(allocation)])
                : ListTile(
                    title: Text(row['description'] as String),
                    subtitle: const Text('Unassigned · Planned'),
                    trailing: const Icon(Icons.person_add_alt_1_outlined),
                    onTap: row['invoice_id'] is String && row['source_line_id'] is String
                      ? () => _assign(row['invoice_id'] as String,
                          {'id': row['source_line_id'], 'description': row['description']},
                          jobId: row['job_id'] as String) : null,
                  ),
            onAddGeneral: _createEmployeeGeneralTask,
            onGeneralStatus: (id, status) async {
              final row = _generalTasks.where((row) => row['id'] == id).firstOrNull;
              if (row == null) return;
              await _run(() => _repository.setShopTaskStatus(row['employee_id'] as String, id, status));
            },
            onOpenJob: (id) => _openRecordedWork(id, invoice: false),
            onEmployeeTap: (id) => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => OwnerPayrollScreen(
                businessId: widget.businessId, employeeId: id,
                employeeName: _employeeLabel(id),
              ),
            )),
          )),
      ]),
    );
  }

  Widget _profile() => DefaultTabController(
    length: 4,
    initialIndex: widget.initialTab,
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
            _tasksTab(),
            _payrollTab(),
            _reportsPanel(),
            _taxesTab(),
          ])),
      ]),
    ),
  );

  Widget _reportsPanel() => Column(children: [
    if (_pendingPayments.isNotEmpty)
      MaterialBanner(content: Text(
        "${_pendingPayments.length} payment request(s) pending — not recorded as paid. "
        "Reconnect over shop Wi-Fi, refresh and review unpaid work before retrying."),
        actions: [TextButton(onPressed: () => showOwnerPayrollConnection(context, widget.businessId),
          child: const Text("Connect"))]),
    Expanded(child: PayrollHistoryPanel(
              payments: _history,
              unlocked: _historyUnlocked,
              onOpenJob: (id) => _openRecordedWork(id, invoice: false),
              onOpenInvoice: (id) => _openRecordedWork(id, invoice: true),
            )),
  ]);

  Future<void> _openEmployeeProfile(String id, DateTime week, int tab) async {
    final row = _employees.where((row) => row['id'] == id).firstOrNull;
    if (row == null) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => OwnerPayrollScreen(
        businessId: widget.businessId, employeeId: id, employeeName: _employeeLabel(id),
        employeeRole: (row['position'] ?? row['position_name'])?.toString(),
        employeePayType: row['payment_type']?.toString(),
        initialWeek: week, initialTab: tab,
        openEmployeeDetails: () => Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => EmployeeEditScreen(
            businessId: widget.businessId, isOwner: true, employeeId: id,
            rosterName: row['name']?.toString(),
            rosterPosition: (row['position'] ?? row['position_name'])?.toString(),
          ),
        )),
      ),
    ));
    if (mounted) await _run(() async {});
  }

  Widget _overview() => Scaffold(
    appBar: AppBar(title: const Text('Payroll')),
    body: Column(children: [
      if (_grant == null || _error != null)
        FilledButton(
          onPressed: _busy ? null : () => _run(() async {}),
          child: const Text('Unlock Owner payroll'),
        ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (_grant != null)
        Expanded(child: PayrollOverview(
          employees: _employees, work: _work, payments: _overviewPayments,
          onOpenProfile: (id, week) => _openEmployeeProfile(id, week, 1),
          onReviewWeek: (id, week) => _openEmployeeProfile(id, week, 0),
        )),
    ]),
  );

  @override
  Widget build(BuildContext context) => widget.globalTasks ? _workspace() : widget.reportsOnly ? _reports() : widget.employeeId != null ? _profile() : !_jobMode ? _overview() : Scaffold(
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
              TextButton(onPressed: _busy || _employees.isEmpty ? null : () => _managePeer(pair: true),
                child: const Text('Pair employee device')),
              TextButton(onPressed: _busy || _employees.isEmpty ? null : () => _managePeer(pair: false),
                child: const Text('Sync payroll over shop Wi-Fi')),
            ],
            if (_grant != null && _jobMode) ...[
              const ListTile(title: Text('Invoice labor')),
              for (final invoice in <String, List<Map<String, dynamic>>>{
                if (widget.invoiceId != null) widget.invoiceId!: widget.invoiceLines,
                ...widget.jobInvoiceLabor,
              }.entries)
                for (final line in invoice.value.where(isInvoiceLaborLine))
                  if (line['id'] is String)
                    ListTile(
                      title: Text((line['description'] ?? line['name'] ?? 'Invoice labor').toString()),
                      trailing: TextButton(
                        onPressed: _busy || _employees.isEmpty
                            ? null : () => _assign(invoice.key, line),
                        child: const Text('Assign'),
                      ),
                    ),
              if (_employees.isEmpty) const Text('No active assignment is saved for this job.'),
              ListTile(
                title: const Text('Additional job work / Rechecks'),
                trailing: TextButton.icon(
                  onPressed: _busy || _employees.isEmpty ? null : _addRecheck,
                  icon: const Icon(Icons.add), label: const Text('Add Recheck'),
                ),
              ),
              for (final row in _work) _taskCard(row),
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
