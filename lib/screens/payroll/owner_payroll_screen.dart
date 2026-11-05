import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/invoice_labor_work_summary.dart';
import '../../services/local_owner_authorization.dart';
import '../../services/local_payroll_repository.dart';
import '../../services/payroll_lan_enrollment.dart';
import '../../services/payroll_lan_identity.dart';
import '../../services/payroll_lan_workflow.dart';
import 'payroll_lan_controls.dart';

class OwnerPayrollScreen extends StatefulWidget {
  const OwnerPayrollScreen({
    super.key,
    required this.businessId,
    this.jobId,
    this.invoiceId,
    this.invoiceLines = const [],
    this.reportsOnly = false,
  });

  static const enabled = bool.fromEnvironment('BRISKERS_ENABLE_OWNER_PAYROLL');

  final bool reportsOnly;
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
  final _selected = <String>{};
  String? _employee;
  String? _error;
  bool _busy = false;
  Timer? _lockCheck;

  @override
  void initState() {
    super.initState();
    _lockCheck = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_grant == null || _busy) return;
      try {
        _assertOwner();
      } on StateError {
        setState(() {
          _grant = null;
          _employee = null;
          _employees = [];
          _work = [];
          _history = [];
          _selected.clear();
        });
      }
    });
  }

  @override
  void dispose() {
    _lockCheck?.cancel();
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
  }) async {
    if (_busy) return;
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
    final employee = _employee ?? (employees.firstOrNull?['id'] as String?);
    final work = await repository.work(employee: _jobMode ? null : employee, job: job);
    final history = employee == null || _jobMode
        ? <Map<String, dynamic>>[]
        : await repository.history(employee);
    _assertOwner();
    if (!mounted) return;
    setState(() {
      _employees = employees;
      _employee = employee;
      _work = work;
      _history = history;
      _selected.retainAll(_payable.map((row) => row['id'] as String));
    });
  }

  String _date(DateTime value) => value.toIso8601String().substring(0, 10);
  String _money(int value) => '\$${(value / 100).toStringAsFixed(2)}';

  Iterable<Map<String, dynamic>> get _payable =>
      _work.where((row) => row['state'] == 'Done' && row['paid'] == 0);

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

  Future<void> _pay() async {
    final employee = _employee;
    final selected = _payable.where((row) => _selected.contains(row['id'])).toList();
    if (employee == null || selected.isEmpty) return;
    final gross = selected.fold<int>(0, (sum, row) => sum + (row['gross_cents'] as int));
    final result = await showDialog<(DateTime, String, String)>(
      context: context,
      builder: (_) => _PaymentDialog(amount: _money(gross)),
    );
    if (result == null || !mounted) return;
    final (date, method, reason) = result;
    final random = Random.secure();
    final operation = List.generate(16, (_) => random.nextInt(256)
        .toRadixString(16).padLeft(2, '0')).join();
    final monday = DateTime(date.year, date.month, date.day - date.weekday + 1);
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
        week: _date(monday),
        date: _date(date),
        method: method,
        selected: selected,
        reason: reason,
        net: gross,
      );
      _selected.clear();
    }, verifyPayment: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                      _selected.clear();
                    });
                    _run(() async {});
                  },
                ),
              Text('Earned: ${_money(_work.where((row) => row['state'] == 'Done').fold<int>(0, (sum, row) => sum + (row['gross_cents'] as int)))}'),
              Text('Unpaid: ${_money(_payable.fold<int>(0, (sum, row) => sum + (row['gross_cents'] as int)))}'),
              Text('Previously paid: ${_money(_history.fold<int>(0, (sum, row) => sum + (row['net'] as int)))}'),
              if (!widget.reportsOnly) ...[
              for (final row in _payable)
                CheckboxListTile(
                  title: Text(row['description'].toString()),
                  subtitle: Text('${row['completed_date']} · ${_money(row['gross_cents'] as int)}'),
                  value: _selected.contains(row['id']),
                  onChanged: _busy ? null : (checked) => setState(() {
                    if (checked == true) {
                      _selected.add(row['id'] as String);
                    } else {
                      _selected.remove(row['id']);
                    }
                  }),
                ),
              FilledButton(
                onPressed: _busy || _selected.isEmpty ? null : _pay,
                child: const Text('Verify Payment'),
              ),
              ],
              const ListTile(title: Text('Payment history')),
              for (final row in _history)
                ListTile(
                  title: Text(_money(row['net'] as int)),
                  subtitle: Text('${row['verified_date']} · ${row['method']} · '
                      '${row['reconciliation_state'] == 'reconciled' ? 'Reconciled' : 'Recorded on this device'}'),
                ),
            ],
          ],
        ),
      );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.amount});

  final String amount;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  DateTime _date = DateTime.now();
  String _method = 'Cash';
  String _reason = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Record completed payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${widget.amount} will be recorded on this device. No money is sent.'),
              TextButton(
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (value != null && mounted) setState(() => _date = value);
                },
                child: Text(MaterialLocalizations.of(context).formatMediumDate(_date)),
              ),
              DropdownButton<String>(
                value: _method,
                items: [
                  for (final method in ['Cash', 'Zelle', 'Check', 'Card', 'Other'])
                    DropdownMenuItem(value: method, child: Text(method)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _method = value);
                },
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Reason for work outside this week'),
                onChanged: (value) => _reason = value.trim(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (_date, _method, _reason)),
            child: const Text('Confirm recorded payment'),
          ),
        ],
      );
}
