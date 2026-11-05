import '../payroll/owner_payroll_screen.dart';
import '../payroll/payroll_lan_controls.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/employee_role_style.dart';
import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';
import '../../services/employee_nickname_store.dart';
import '../../services/payroll_lan_identity.dart';
import '../../services/offline_job_admin_service.dart';
import '../../core/connection_mode.dart';
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
  final _nicknameStore = EmployeeNicknameStore();
  final _offlineEmployees = OfflineJobAdminService();

  List<Map<String, dynamic>>? _employees;
  String? _error;
  bool _cachedEmployeesOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (BriskersConnectionModeController.instance.forceOffline) {
        throw StateError('Force Offline is enabled.');
      }
      final rows = await _api.employeesSettings(widget.businessId);
      final annotated = await _nicknameStore.decorate(widget.businessId, rows);
      if (!mounted) return;
      setState(() {
        _employees = annotated;
        _cachedEmployeesOnly = false;
        _error = null;
      });
    } catch (error) {
      // Keep known employees visible offline without fabricating pay details.
      final cached = await _offlineEmployees.cachedEmployees(widget.businessId);
      if (!mounted) return;
      setState(() {
        _employees = cached;
        _cachedEmployeesOnly = true;
        _error = cached.isEmpty ? error.toString()
            : 'Showing locally saved employee names and roles. '
              'Pay details require an authenticated refresh.';
      });
    }
  }

  String _pay(Map<String, dynamic> employee) {
    if (_cachedEmployeesOnly) return 'Pay unavailable offline';
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

  Future<void> _open([Map<String, dynamic>? employee, bool detailsOnly = false]) async {
    final employeeId = employee?['id']?.toString();
    final name = employee?['name']?.toString();
    final position = (employee?['position_name'] ?? employee?['position'])?.toString();
    if (!detailsOnly && widget.isOwner && OwnerPayrollScreen.enabled &&
        employeeId != null && employeeId.isNotEmpty) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => OwnerPayrollScreen(
          businessId: widget.businessId,
          employeeId: employeeId,
          employeeName: employee?['nickname']?.toString() ?? name,
          employeeRole: position,
          employeeActive: employee?['active'] != false,
          openEmployeeDetails: () => _open(employee, true),
        )),
      );
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeEditScreen(
          businessId: widget.businessId,
          employeeId: employeeId,
          rosterName: name,
          rosterPosition: position,
          isOwner: widget.isOwner,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _positions() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeePositionsScreen(
          businessId: widget.businessId,
        ),
      ),
    );
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
    if (_employees == null) return;

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
                      final name = EmployeeNicknameStore.displayName(employee);

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
                        subtitle: Text(
                          employee['nickname']?.toString().isNotEmpty == true
                              ? '${employee['name']} • $position'
                              : position,
                        ),
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
    if (action == 'edit') await _open(employee, true);
    if (action == 'delete') await _deleteEmployee(employee);
  }

  Future<void> _showManageMenu() async {
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

  Future<void> _showPayrollDeviceId() async {
    try {
      final identity = await PayrollLanIdentity.load();
      if (!mounted) return;
      await showPayrollLanCode(context, 'Public payroll device ID', identity.deviceId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load this phone’s payroll device ID.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
        actions: [
          if (widget.isOwner)
            IconButton(
              tooltip: 'Public payroll device ID',
              icon: const Icon(Icons.phonelink_lock),
              onPressed: _showPayrollDeviceId,
            ),
          if (OwnerPayrollScreen.enabled && widget.isOwner)
            IconButton(
              tooltip: 'Owner payroll',
              icon: const Icon(Icons.payments_outlined),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => OwnerPayrollScreen(businessId: widget.businessId),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showManageMenu,
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
                  if (_employees!.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No employees yet. Tap Manage to add one.',
                        ),
                      ),
                    )
                  else
                    ..._employees!.map((employee) {
                      final active = employee['active'] != false;
                      final position =
                          (employee['position'] ?? employee['position_name'])?.toString() ?? 'No position';
                      final ssnLast4 = employee['ssn_last4']?.toString();
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
                            EmployeeNicknameStore.displayName(employee),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: active ? null : Colors.grey,
                            ),
                          ),
                          subtitle: Text.rich(
                            TextSpan(
                              children: [
                                if (employee['nickname']?.toString().isNotEmpty == true)
                                  TextSpan(text: '${employee['name']} • '),
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
                                  text: ' • ${_pay(employee)}',
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
                          onTap: () => _open(employee),
                          onLongPress: () => _employeeActions(employee),
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
