import 'package:flutter/material.dart';

import '../../services/local_employee_reports.dart';
import '../payroll/approved_tasks_ui.dart';

class PayrollReportNamesScreen extends StatefulWidget {
  const PayrollReportNamesScreen({
    super.key,
    required this.businessId,
    required this.repository,
    required this.data,
    required this.isOwner,
    this.sharedBottomNavigationBar,
  });

  final String businessId;
  final LocalEmployeeReports repository;
  final EmployeeReportData data;
  final bool isOwner;
  final Widget? sharedBottomNavigationBar;

  @override
  State<PayrollReportNamesScreen> createState() =>
      _PayrollReportNamesScreenState();
}

class _PayrollReportNamesScreenState extends State<PayrollReportNamesScreen> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  late final _saved = {
    for (final link in widget.data.payrollNames) link.name: link.employeeId,
  };
  String? _employee;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _edit(String name, String employee) {
    setState(() {
      _name.text = name;
      _employee = widget.data.employeeNames.containsKey(employee)
          ? employee
          : null;
      _error = null;
    });
  }

  Future<void> _change(String name, {String? employee}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (employee == null) {
        await widget.repository.removePayrollName(
          widget.businessId,
          isOwner: widget.isOwner,
          name: name,
        );
      } else {
        await widget.repository.savePayrollName(
          widget.businessId,
          isOwner: widget.isOwner,
          name: name,
          employeeId: employee,
        );
      }
      if (!mounted) return;
      String key(String value) =>
          value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      setState(() {
        _saved.removeWhere((saved, _) => key(saved) == key(name));
        if (employee != null) _saved[name] = employee;
        _name.clear();
        _employee = null;
        _form.currentState?.reset();
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not save the payroll name. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = widget.data.employeeNames.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return Scaffold(
      appBar: const ApprovedTasksHeader(title: 'Payroll Names'),
      bottomNavigationBar: widget.sharedBottomNavigationBar,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Link a name from Expenses → Payroll to an employee’s reports.',
            ),
            const SizedBox(height: 12),
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    enabled: !_saving,
                    maxLength: 100,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Name on the expense',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter the name from the expense.'
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_employee),
                    initialValue: _employee,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Employee'),
                    items: [
                      for (final employee in employees)
                        DropdownMenuItem(
                          value: employee.key,
                          child: Text(employee.value),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (employee) => _employee = employee,
                    validator: (value) =>
                        value == null ? 'Choose an employee.' : null,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving || employees.isEmpty
                        ? null
                        : () {
                            if (_form.currentState?.validate() == true) {
                              _change(_name.text.trim(), employee: _employee);
                            }
                          },
                    child: const Text('Link payroll name'),
                  ),
                  if (_error case final error?) Text(error),
                ],
              ),
            ),
            for (final link in _saved.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(link.key),
                subtitle: Text(
                  widget.data.employeeNames[link.value] ??
                      'Employee unavailable',
                ),
                onTap: _saving ? null : () => _edit(link.key, link.value),
                trailing: IconButton(
                  tooltip: 'Remove payroll name',
                  onPressed: _saving ? null : () => _change(link.key),
                  icon: const Icon(Icons.link_off),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
