import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/connection_mode.dart';
import '../../local/local_database_provider.dart';
import '../../services/briskers_api.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/invoice_labor_work_summary.dart';
import '../../services/local_owner_authorization.dart';
import '../../services/local_payroll_repository.dart';

class OwnerPayrollScreen extends StatefulWidget {
  const OwnerPayrollScreen({
    super.key,
    required this.businessId,
    this.jobId,
    this.invoiceId,
    this.invoiceLines = const [],
  });

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

  bool get _jobMode => widget.jobId != null;
  LocalPayrollRepository get _repository => LocalPayrollRepository(
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
    await _run(() async {
      final employeeId = employee['employee_id'] as String;
      var name = employee['name']?.toString();
      var cents = employee['rate'] as int?;
      if (!BriskersConnectionModeController.instance.forceOffline) {
        final profile = await const BriskersApi()
            .employeeSettingsDetail(widget.businessId, employeeId);
        if (profile['active'] == false ||
            profile['compensation_enabled'] == false ||
            profile['payment_type'] != 'hourly') {
          throw StateError('An active hourly employee is required.');
        }
        final rate = num.tryParse(profile['hourly_rate']?.toString() ?? '');
        name = profile['name']?.toString();
        cents = rate != null && rate.isFinite ? (rate * 100).round() : null;
      }
      if (name == null || cents == null || cents <= 0) {
        throw StateError('No verified hourly rate is saved on this device for this employee.');
      }
      await _repository.registerAssignedLabor(
        jobId: widget.jobId!,
        invoiceId: widget.invoiceId!,
        lineId: line['id'] as String,
        employeeId: employeeId,
        employeeName: name,
        rateCents: cents,
      );
    });
  }

  Future<void> _editWork(Map<String, dynamic> row) async {
    final input = await showDialog<int>(
      context: context,
      builder: (_) => const _WorkMinutesDialog(),
    );
    if (input == null || !mounted) return;
    await _run(() async {
      await _repository.updateWork(
        row['id'] as String,
        row['state'] == 'Open' ? 'In Progress' : 'Done',
        (input * 100 / 60).round(),
        _date(DateTime.now()),
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
      await _repository.verify(
        operation: operation,
        employee: employee,
        week: _date(monday),
        date: _date(date),
        method: method,
        selected: selected,
        base: 0,
        hourlyAdjustment: 0,
        adjustmentReason: reason,
        repayment: 0,
        confirmedNet: gross,
      );
      _selected.clear();
    }, verifyPayment: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_jobMode ? 'Job labor tasks' : 'Owner payroll')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton(
              onPressed: _busy ? null : () => _run(() async {}),
              child: Text(_grant == null ? 'Unlock Owner payroll' : 'Refresh'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
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
                  trailing: row['state'] == 'Done' ? null : TextButton(
                    onPressed: _busy ? null : () => _editWork(row),
                    child: Text(row['state'] == 'Open' ? 'Start' : 'Complete'),
                  ),
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
              const ListTile(title: Text('Payment history')),
              for (final row in _history)
                ListTile(
                  title: Text(_money(row['net'] as int)),
                  subtitle: Text('${row['verified_date']} · ${row['method']} · Recorded on this device'),
                ),
            ],
          ],
        ),
      );
}

class _WorkMinutesDialog extends StatefulWidget {
  const _WorkMinutesDialog();

  @override
  State<_WorkMinutesDialog> createState() => _WorkMinutesDialogState();
}

class _WorkMinutesDialogState extends State<_WorkMinutesDialog> {
  int? _minutes;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Record work time'),
        content: TextField(
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Actual minutes'),
          onChanged: (value) => setState(() => _minutes = int.tryParse(value)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: (_minutes ?? -1) < 0 ? null : () => Navigator.pop(context, _minutes),
            child: const Text('Save'),
          ),
        ],
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
