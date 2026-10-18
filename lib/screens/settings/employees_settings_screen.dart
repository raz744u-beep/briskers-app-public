import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/connection_mode.dart';
import '../../services/employee_roster_cache.dart';

import '../../core/employee_role_style.dart';
import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';
import 'employee_edit_screen.dart';
import 'employee_positions_screen.dart';

class EmployeesSettingsScreen extends StatefulWidget {
  const EmployeesSettingsScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
  });

  final String businessId;
  final bool isOwner;

  @override
  State<EmployeesSettingsScreen> createState() =>
      _EmployeesSettingsScreenState();
}

class _EmployeesSettingsScreenState
    extends State<EmployeesSettingsScreen> {
  static const _api = BriskersApi();
  final EmployeeRosterCache _roster = EmployeeRosterCache();

  List<Map<String, dynamic>>? _employees;
  bool _showingSaved = false;
  bool _offlineUnavailable = false;
  bool _savedActiveOnly = false;
  DateTime? _savedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fullCached = await _roster.cachedSettings(widget.businessId);
    final cached = fullCached ??
        await _roster.cachedAssignable(widget.businessId);
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        // This is deliberately a safe roster, not compensation/settings data.
        _employees = cached.rows;
        _showingSaved = true;
        _savedActiveOnly = fullCached == null;
        _savedAt = cached.refreshedAt;
        _offlineUnavailable = false;
        _error = null;
      });
    }
    if (BriskersConnectionModeController.instance.forceOffline) {
      setState(() {
        _employees ??= const [];
        _showingSaved = cached != null;
        _savedActiveOnly = fullCached == null;
        _offlineUnavailable = cached == null;
        _error = null;
      });
      return;
    }
    try {
      final rows = await _roster.refreshSettings(widget.businessId);
      if (!mounted) return;
      setState(() {
        _employees = rows;
        _showingSaved = false;
        _savedActiveOnly = false;
        _offlineUnavailable = false;
        _savedAt = DateTime.now();
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _employees ??= const [];
        _showingSaved = cached != null;
        _savedActiveOnly = fullCached == null;
        _offlineUnavailable = cached == null;
        _error = 'Could not refresh employees. '
            'Connect and pull down to try again.';
      });
    }
  }

  String _pay(Map<String, dynamic> employee) {
    if (employee['compensation_enabled'] == false) {
      return 'Pay not tracked';
    }

    final type = employee['payment_type']?.toString();
    final raw = type == 'fixed_weekly'
        ? employee['weekly_rate']
        : employee['hourly_rate'];
    final rate = num.tryParse(raw?.toString() ?? '');
    if (rate == null) return 'Pay not set';

    final money = NumberFormat.currency(symbol: '\$').format(rate);
    return type == 'fixed_weekly'
        ? '$money / week'
        : '$money / hr';
  }

  Future<void> _open([Map<String, dynamic>? employee]) async {
    if (_showingSaved ||
        BriskersConnectionModeController.instance.forceOffline) {
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeEditScreen(
          businessId: widget.businessId,
          employeeId: employee?['id']?.toString(),
          isOwner: widget.isOwner,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _positions() async {
    if (_showingSaved ||
        BriskersConnectionModeController.instance.forceOffline) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeePositionsScreen(
          businessId: widget.businessId,
        ),
      ),
    );
    // Position changes can alter the assignment list even if employees
    // themselves did not change.
    await _roster.invalidate(widget.businessId);
    await _load();
  }

  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    final name = employee['name']?.toString() ?? 'this employee';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete employee?'),
        content: Text(
          'Delete $name? This cannot be undone. Employees with job or appointment history cannot be deleted and should be marked inactive instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _api.deleteEmployee(
        widget.businessId,
        employee['id'].toString(),
      );
      // An old cache must not leave this deleted employee assignable.
      await _roster.invalidate(widget.businessId);
      await _load();
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Employee could not be deleted'),
          content: Text(error.toString()),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _manageEmployees() async {
    if (_employees == null || _showingSaved ||
        BriskersConnectionModeController.instance.forceOffline) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.72;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Manage employees',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x175E35B1),
                    child: Icon(Icons.person_add_alt_1,
                      color: BriskersColors.settings),
                  ),
                  title: const Text('Add employee'),
                  subtitle: const Text('Create a new employee record'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _open();
                  },
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _employees!.map((employee) {
                      final active = employee['active'] != false;
                      final position =
                          (employee['position'] ?? employee['position_name'])?.toString() ?? 'No position';
                      final roleStyle = employeeRoleStyle(position);
                      final name = employee['name']?.toString() ?? '';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: active
                              ? roleStyle.color.withValues(alpha: 0.14)
                              : Colors.grey.withValues(alpha: 0.14),
                          child: Icon(
                            active
                                ? roleStyle.icon
                                : Icons.person_off_outlined,
                            color: active ? roleStyle.color : Colors.grey,
                          ),
                        ),
                        title: Text(name),
                        subtitle: Text(position),
                        trailing: Wrap(
                          spacing: 0,
                          children: [
                            IconButton(
                              tooltip: 'Edit employee',
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                _open(employee);
                              },
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Delete employee',
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                _deleteEmployee(employee);
                              },
                              icon: Icon(
                                Icons.delete_outline,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _employeeActions(Map<String, dynamic> employee) async {
    if (_showingSaved ||
        BriskersConnectionModeController.instance.forceOffline) {
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  employee['name']?.toString() ?? 'Employee',
                  style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                color: BriskersColors.settings),
              title: const Text('Edit employee'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            if (widget.isOwner)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete employee',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await _open(employee);
    if (action == 'delete') await _deleteEmployee(employee);
  }

  Future<void> _showManageMenu() async {
    if (_showingSaved ||
        BriskersConnectionModeController.instance.forceOffline) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Employee actions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x175E35B1),
                    child: Icon(Icons.groups_2_outlined,
                      color: BriskersColors.settings),
                  ),
                  title: const Text(
                    'Manage employees',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Add, edit, or delete employees'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _manageEmployees();
                  },
                ),
              ),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x175E35B1),
                    child: Icon(Icons.badge_outlined,
                      color: BriskersColors.settings),
                  ),
                  title: const Text(
                    'Manage positions',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Add, edit, deactivate, or delete roles'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _positions();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _offlineUnavailable || _showingSaved ||
                BriskersConnectionModeController.instance.forceOffline
            ? null : _showManageMenu,
        backgroundColor: BriskersColors.settings,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.groups_2_outlined),
        label: const Text('Manage'),
      ),
      body: _employees == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_showingSaved)
                    Card(child: ListTile(
                      leading: const Icon(Icons.wifi_off_outlined),
                      title: Text(_savedActiveOnly
                          ? 'Saved active roster only (read-only)'
                          : 'Saved employee roster (read-only)'),
                      subtitle: Text('Last updated: ${_savedAt == null ? 'Unknown' : DateFormat.yMd().add_jm().format(_savedAt!)}. '
                          '${_savedActiveOnly ? 'Inactive employees are not in this saved list. ' : ''}'
                          'Employee pay, SSN and contact details are available online. '
                          'Changes require a connection.'),
                    )),
                  if (_offlineUnavailable)
                    const Card(child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Employee list not available offline yet'),
                      subtitle: Text('Connect once and refresh Employees to save '
                          'a minimal roster for offline viewing and Job assignment.'),
                    )),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_employees!.isEmpty && !_offlineUnavailable)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _showingSaved
                            ? (_savedActiveOnly
                                ? 'No active employees in the saved roster. '
                                  'Connect to see all employees.'
                                : 'The saved roster is empty. Connect to refresh.')
                            : 'No employees yet. Tap Manage to add one.',
                        ),
                      ),
                    )
                  else
                    ..._employees!.map((employee) {
                      final active = employee['active'] != false;
                      final position =
                          employee['position']?.toString() ?? 'No position';
                      final ssnLast4 = _showingSaved
                          ? null : employee['ssn_last4']?.toString();
                      final roleStyle = employeeRoleStyle(position);

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: active
                                ? roleStyle.color.withValues(alpha: 0.14)
                                : Colors.grey.withValues(alpha: 0.14),
                            child: Icon(
                              active
                                  ? roleStyle.icon
                                  : Icons.person_off_outlined,
                              color: active ? roleStyle.color : Colors.grey,
                            ),
                          ),
                          title: Text(
                            employee['name']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: active ? null : Colors.grey,
                            ),
                          ),
                          subtitle: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: position,
                                  style: TextStyle(
                                    color: active
                                        ? roleStyle.color
                                        : Colors.grey,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text: _showingSaved ? ' • Offline roster' : ' • ${_pay(employee)}',
                                ),
                                if (ssnLast4 != null && ssnLast4.isNotEmpty)
                                  TextSpan(
                                    text: ' • SSN ***-**-$ssnLast4',
                                  ),
                                if (!active)
                                  const TextSpan(text: ' • Inactive'),
                              ],
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right,
                            color: BriskersColors.settings),
                          onTap: _showingSaved ? null : () => _open(employee),
                          onLongPress: _showingSaved
                              ? null : () => _employeeActions(employee),
                        ),
                      );
                    }),
                  const SizedBox(height: 90),
                ],
              ),
            ),
    );
  }
}
