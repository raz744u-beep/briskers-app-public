import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'core/briskers_colors.dart';
import 'widgets/briskers_module_dock.dart';

import 'local/local_database_provider.dart';
import 'services/local_job_tasks_lab_store.dart';
import 'tasks_lab/fixture.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BriskersTasksLabApp());
}

class BriskersTasksLabApp extends StatelessWidget {
  const BriskersTasksLabApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Briskers Tasks TEST',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF007F79)),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    ),
    home: const TasksLabHome(),
  );
}

class TasksLabHome extends StatefulWidget {
  const TasksLabHome({super.key});

  @override
  State<TasksLabHome> createState() => _TasksLabHomeState();
}

class _TasksLabHomeState extends State<TasksLabHome> {
  final LocalJobTasksLabStore store = LocalJobTasksLabStore(localDatabase);
  List<Map<String, dynamic>> tasks = const [];
  Map<String, String> nicknames = const {};
  Map<String, String> fullNames = const {};
  String? leadMechanicId;
  String jobStatusCode = 'open';
  List<Map<String, dynamic>> earlierWorkLog = const [];
  Map<String, List<Map<String, dynamic>>> allocationsByLine = {};
  Map<String, double> earnedPayrollPreviewHours = {};
  Map<String, int> testHourlyRates = {};
  List<Map<String, dynamic>> testPayrollPayments = const [];
  int page = 0;
  int? expandedMenu;
  double menuAnchorX = 180;
  int selectedVehicle = 0;
  bool jobDetailsOpen = false;
  bool loading = true;
  String? error;

  static const _dockPages = [0, 1, 2, 7, 8, 9, 10, 11];

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await store.reconcileDocument(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        documentId: BriskersLabFixture.invoiceId,
        laborLines: LocalJobTasksLabStore.laborLines(
          BriskersLabFixture.invoice,
        ),
      );
      final previous = await store.nicknames(BriskersLabFixture.businessId);
      for (final employee in BriskersLabFixture.employees) {
        final id = employee['id']!;
        if (!previous.containsKey(id)) {
          await store.saveNickname(
            BriskersLabFixture.businessId, id, employee['nickname']!,
          );
        }
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Local test setup failed: $e';
        });
      }
    }
  }

  Future<void> _refresh() async {
    final rows = await store.list(
      BriskersLabFixture.businessId, BriskersLabFixture.jobId,
    );
    final aliases = await store.nicknames(BriskersLabFixture.businessId);
    final names = await store.fullNames(BriskersLabFixture.businessId);
    final allocations = await Future.wait(rows.map((task) => store.allocations(
      businessId: BriskersLabFixture.businessId,
      jobId: BriskersLabFixture.jobId,
      documentId: task['document_id'].toString(),
      lineId: task['line_id'].toString())));
    final rates = await store.payrollRates(BriskersLabFixture.businessId);
    final payments = await store.payrollTestPayments(BriskersLabFixture.businessId);
    final earnedHours = await store.earnedHoursPreview(
      BriskersLabFixture.businessId, BriskersLabFixture.jobId);
    final currentJobStatus = await store.jobStatus(
      BriskersLabFixture.businessId, BriskersLabFixture.jobId);
    final archived = await store.priorCompletions(
      BriskersLabFixture.businessId, BriskersLabFixture.jobId);
    final lead = await store.leadMechanic(
      BriskersLabFixture.businessId, BriskersLabFixture.jobId);
    if (!mounted) return;
    setState(() {
      tasks = rows;
      nicknames = aliases;
      fullNames = names;
      leadMechanicId = lead;
      jobStatusCode = currentJobStatus;
      earlierWorkLog = archived;
      earnedPayrollPreviewHours = earnedHours;
      testHourlyRates = rates;
      testPayrollPayments = payments;
      allocationsByLine = {for (var i = 0; i < rows.length; i++)
        rows[i]['line_id'].toString(): allocations[i]};
      loading = false;
    });
  }

  String _employeeName(String? id) {
    if (id == null || id.isEmpty) return 'Unassigned';
    for (final employee in BriskersLabFixture.employees) {
      if (employee['id'] == id) {
        return LocalJobTasksLabStore.displayName(
          fullNames[id] ?? employee['name']!, nicknames[id],
        );
      }
    }
    return 'Unknown mechanic';
  }

  String _description(Map<String, dynamic> row) =>
    (row['custom_description'] ?? row['source_description'] ?? 'Labor')
      .toString();

  Widget _sectionHeader(String title, {String? subtitle}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(
          fontSize: 22, fontWeight: FontWeight.w800,
        )),
        if (subtitle != null) Text(subtitle,
          style: const TextStyle(color: Color(0xFF64748B))),
      ],
    ),
  );

  void _navigate(int next) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      page = next;
      expandedMenu = null;
      if (next == 2) jobDetailsOpen = false;
    });
  }

  void _openVehicleJob(int vehicleIndex) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      selectedVehicle = vehicleIndex;
      jobDetailsOpen = true;
      page = 2;
      expandedMenu = null;
    });
  }

  void _toggleMenu(int navIndex, Offset globalPosition) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      expandedMenu = expandedMenu == navIndex ? null : navIndex;
      menuAnchorX = globalPosition.dx;
    });
  }

  int get _selectedDock {
    if (page == 3 || page == 4) return 2;
    if (page == 5 || page == 6) return 7;
    final idx = _dockPages.indexOf(page);
    return idx < 0 ? 0 : idx;
  }

  // Reuse the actual dock from the Briskers shop application.
  // Lab-only long presses reveal Tasks/Work Log and Payroll/Settings upward.
  Widget _bottomNav() => BriskersModuleDock(
    selectedIndex: _selectedDock,
    destinations: const [
      BriskersDockDestination(
        label: 'Home', icon: Icons.home_outlined,
        color: BriskersColors.today),
      BriskersDockDestination(
        label: 'Customers', icon: Icons.people_outline,
        color: BriskersColors.customers),
      BriskersDockDestination(
        label: 'Jobs', icon: Icons.build_outlined,
        color: BriskersColors.jobs),
      BriskersDockDestination(
        label: 'Estimates', icon: Icons.description_outlined,
        color: BriskersColors.estimates),
      BriskersDockDestination(
        label: 'Invoices', icon: Icons.receipt_long_outlined,
        color: BriskersColors.invoices),
      BriskersDockDestination(
        label: 'Schedule', icon: Icons.calendar_month_outlined,
        color: BriskersColors.schedule),
      BriskersDockDestination(
        label: 'Expenses', icon: Icons.account_balance_wallet_outlined,
        color: BriskersColors.expenses),
      BriskersDockDestination(
        label: 'More', icon: Icons.more_horiz,
        color: BriskersColors.more),
    ],
    onSelected: (index) => _navigate(_dockPages[index]),
    onLongPressed: (index, globalPosition) {
      if (index == 2 || index == 7) {
        _toggleMenu(index, globalPosition);
      }
    },
  );

  Widget _menuEntry(IconData icon, String label, int destination) =>
    InkWell(
      onTap: () => _navigate(destination),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 23, color: const Color(0xFF1767B3)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
              )),
            ),
          ],
        ),
      ),
    );

  Widget _verticalMenu(int index) => Material(
    elevation: 10,
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: 180,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (index == 2) ...[
            _menuEntry(Icons.rule_outlined, 'Tasks', 3),
            const Divider(height: 1),
            _menuEntry(Icons.history, 'Work Log', 4),
          ],
          if (index == 7) ...[
            _menuEntry(Icons.account_balance_wallet_outlined, 'Payroll', 5),
            const Divider(height: 1),
            _menuEntry(Icons.settings_outlined, 'Settings', 6),
          ],
        ],
      ),
    ),
  );

  String _laborAssignment(Map<String, dynamic> task) {
    final allocations = allocationsByLine[task['line_id'].toString()] ?? [];
    if (allocations.isNotEmpty) {
      return allocations.map((a) => "${_employeeName(a['employee_id'].toString())}: ${a['hours']} hrs").join(' · ');
    }
    return "${_employeeName(task['employee_id']?.toString())} · ${task['payroll_hours'] ?? '—'} hrs";
  }

  Future<void> _editInvoiceLabor(Map<String, dynamic> task) async {
    final existing = allocationsByLine[task['line_id'].toString()] ?? [];
    final notOnInvoice = task['document_id'] ==
      LocalJobTasksLabStore.recheckDocumentId;
    String first = existing.isNotEmpty ? existing.first['employee_id'].toString()
      : task['employee_id']?.toString() ?? '';
    String second = existing.length > 1 ? existing[1]['employee_id'].toString() : '';
    final hoursA = TextEditingController(text: existing.isNotEmpty
      ? existing.first['hours'].toString() : task['payroll_hours']?.toString() ?? '');
    final hoursB = TextEditingController(text: existing.length > 1
      ? existing[1]['hours'].toString() : '');
    final saved = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, update) {
        Widget choose(String label, String value, ValueChanged<String> set) =>
          DropdownButtonFormField<String>(
            initialValue: value,
            decoration: InputDecoration(labelText: label,
              border: const OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: '', child: Text('Unassigned')),
              for (final e in BriskersLabFixture.employees)
                if (e['role'] == 'mechanic' || e['role'] == 'owner')
                  DropdownMenuItem(value: e['id']!,
                    child: Text(_employeeName(e['id']))),
            ],
            onChanged: (v) => update(() => set(v ?? '')),
          );
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16,
            MediaQuery.viewInsetsOf(sheet).bottom + 16),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(notOnInvoice ? 'Assign recheck labor' : 'Assign invoice labor',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(_description(task)),
              const SizedBox(height: 8),
              Text('${notOnInvoice ? 'Recheck work' : 'Invoice labor'}: '
                '${task['source_invoice_hours'] ?? '—'} hrs. '
                'Combined mechanic hours may be less, but not more.',
                style: const TextStyle(
                  fontSize: 12.5, color: Color(0xFF64748B))),
              Text(notOnInvoice ? 'Not on Invoice · No customer charge.'
                : 'Invoice totals do not change.',
                style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 12),
              choose('Mechanic 1', first, (v) => first = v),
              const SizedBox(height: 8),
              TextField(controller: hoursA,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Hours 1',
                  border: OutlineInputBorder())),
              const SizedBox(height: 12),
              choose('Mechanic 2 (optional)', second, (v) => second = v),
              const SizedBox(height: 8),
              TextField(controller: hoursB,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Hours 2',
                  border: OutlineInputBorder())),
              const SizedBox(height: 12),
              FilledButton(onPressed: () async {
                final a = double.tryParse(hoursA.text);
                final b = double.tryParse(hoursB.text);
                if ((first.isNotEmpty && (a == null || !a.isFinite || a <= 0)) ||
                    (second.isNotEmpty && (b == null || !b.isFinite || b <= 0)) ||
                    (first.isEmpty && second.isNotEmpty) ||
                    (first.isNotEmpty && first == second)) {
                  ScaffoldMessenger.of(sheet).showSnackBar(const SnackBar(
                    content: Text('Choose distinct mechanics and positive hours')));
                  return;
                }
                final billed = (task['source_invoice_hours'] as num?)?.toDouble();
                final allocated =
                    (first.isNotEmpty ? a! : 0.0) +
                    (second.isNotEmpty ? b! : 0.0);
                if (billed == null || allocated > billed + 0.000001) {
                  ScaffoldMessenger.of(sheet).showSnackBar(SnackBar(
                    content: Text(billed == null
                      ? 'Invoice labor hours unavailable; refresh invoice'
                      : 'Assigned hours cannot exceed $billed invoice hours'),
                  ));
                  return;
                }
                try {
                  await store.saveAllocations(
                    businessId: BriskersLabFixture.businessId,
                    jobId: BriskersLabFixture.jobId,
                    documentId: task['document_id'].toString(),
                    lineId: task['line_id'].toString(),
                    hoursByEmployee: {
                      if (first.isNotEmpty) first: a!,
                      if (second.isNotEmpty) second: b!,
                    },
                  );
                  if (sheet.mounted) Navigator.pop(sheet, true);
                } catch (e) {
                  if (sheet.mounted) {
                    ScaffoldMessenger.of(sheet).showSnackBar(
                      SnackBar(content: Text('Save failed: $e')));
                  }
                }
              }, child: const Text('Save labor assignments')),
            ],
          ))); 
      }),
    );
    hoursA.dispose();
    hoursB.dispose();
    if (saved == true) await _refresh();
  }

  Widget _statusChip(String value) {
    final done = value == 'done';
    final label = done ? 'Done'
      : value == 'in_progress' ? 'In progress' : 'Planned';
    return Text(label, style: TextStyle(
      fontSize: 12, fontWeight: FontWeight.w700,
      color: done ? const Color(0xFF168058)
        : const Color(0xFF3570B6),
    ));
  }

  // Tasks remain editable here; Work Log uses a distinct read-only view.
  Widget _taskCard(Map<String, dynamic> task) {
    final done = task['status'] == 'done';
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 3, 10, 5),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        leading: Icon(
          done ? Icons.check_circle : Icons.build_circle_outlined,
          color: done ? const Color(0xFF169D70)
            : const Color(0xFF417CC5),
        ),
        title: Text(_description(task),
          style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task['document_id'] ==
                LocalJobTasksLabStore.recheckDocumentId)
              const Text('Recheck · Not on Invoice',
                style: TextStyle(fontSize: 11,
                  color: BriskersColors.jobs)),
            Text(_laborAssignment(task)),
            _statusChip(task['status']?.toString() ?? 'planned'),
          ],
        ),
        trailing: const Icon(Icons.edit_outlined, size: 19),
        onTap: () => _editTask(task),
      ),
    );
  }

  Future<void> _editTask(Map<String, dynamic> task) async {
    var status = task['status']?.toString() ?? 'planned';
    final description = TextEditingController(text: _description(task));
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Edit task', style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(controller: description, minLines: 2, maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Work performed description',
                    border: OutlineInputBorder())),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext, false);
                    _editInvoiceLabor(task);
                  },
                  icon: const Icon(Icons.people_outline),
                  label: const Text('Assign / split labor mechanics'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(
                    labelText: 'Task status', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                      value: 'planned', child: Text('Planned')),
                    DropdownMenuItem(
                      value: 'in_progress', child: Text('In progress')),
                    DropdownMenuItem(
                      value: 'done', child: Text('Done')),
                  ],
                  onChanged: (v) {
                    setModalState(() => status = v ?? 'planned');
                  },
                ),
                const SizedBox(height: 14),
                FilledButton(
                  child: const Text('Save task'),
                  onPressed: () async {
                    try {
                      await store.editTask(
                        businessId: BriskersLabFixture.businessId,
                        jobId: BriskersLabFixture.jobId,
                        documentId: task['document_id'].toString(),
                        lineId: task['line_id'].toString(),
                        description: description.text,
                        editDescription: true,
                        status: status,
                      );
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext, true);
                      }
                    } catch (e) {
                      if (sheetContext.mounted) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(content: Text(e.toString())));
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    description.dispose();
    if (updated == true) {
      await _refresh();
      if (status == 'done') await _offerCompleteJobIfReady();
    }
  }

  Future<void> _editEmployeeNames() async {
    final fullControllers = {
      for (final e in BriskersLabFixture.employees)
        e['id']!: TextEditingController(
          text: fullNames[e['id']] ?? e['name']!),
    };
    final displayControllers = {
      for (final e in BriskersLabFixture.employees)
        e['id']!: TextEditingController(
          text: nicknames[e['id']] ?? e['nickname']!),
    };
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Employee names'),
        content: SizedBox(
          width: 380,
          height: 430,
          child: ListView(
            children: [
              const Text('Test-only: edit full and preferred display names. '
                'Employee IDs and job records do not change.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 12),
              for (final employee in BriskersLabFixture.employees) ...[
                Text(employee['role'] == 'secretary'
                  ? 'Secretary' : employee['name']!,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: fullControllers[employee['id']],
                  decoration: const InputDecoration(
                    labelText: 'Full name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: displayControllers[employee['id']],
                  decoration: const InputDecoration(
                    labelText: 'Preferred display name',
                    border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              for (final employee in BriskersLabFixture.employees) {
                final id = employee['id']!;
                if (fullControllers[id]!.text.trim().isEmpty ||
                    displayControllers[id]!.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialog).showSnackBar(
                    const SnackBar(content:
                      Text('Full name and display name are required')));
                  return;
                }
              }
              try {
                for (final employee in BriskersLabFixture.employees) {
                  final id = employee['id']!;
                  await store.saveEmployeeProfile(
                    businessId: BriskersLabFixture.businessId,
                    employeeId: id,
                    fullName: fullControllers[id]!.text,
                    displayName: displayControllers[id]!.text,
                  );
                }
                if (dialog.mounted) Navigator.pop(dialog);
              } catch (e) {
                if (dialog.mounted) {
                  ScaffoldMessenger.of(dialog).showSnackBar(
                    SnackBar(content: Text('Could not save names: $e')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    for (final controller in [
      ...fullControllers.values, ...displayControllers.values,
    ]) {
      controller.dispose();
    }
    await _refresh();
  }

  Future<void> _assignLeadMechanic() async {
    String selected = leadMechanicId ?? '';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Assign main job mechanic', style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Unassigned labor tasks automatically inherit the lead. '
                'Manual task overrides and split allocations stay unchanged.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(
                  labelText: 'Lead mechanic',
                  border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(
                    value: '', child: Text('Unassigned')),
                  for (final employee in BriskersLabFixture.employees)
                    if (employee['role'] == 'mechanic' ||
                        employee['role'] == 'owner')
                      DropdownMenuItem(
                        value: employee['id']!,
                        child: Text(_employeeName(employee['id'])),
                      ),
                ],
                onChanged: (id) => setSheetState(
                  () => selected = id ?? ''),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () async {
                  try {
                    await store.saveLeadMechanic(
                      BriskersLabFixture.businessId,
                      BriskersLabFixture.jobId, selected);
                    if (sheet.mounted) Navigator.pop(sheet, true);
                  } catch (e) {
                    if (sheet.mounted) {
                      ScaffoldMessenger.of(sheet).showSnackBar(
                        SnackBar(content: Text('Could not assign job: $e')));
                    }
                  }
                },
                child: const Text('Save main job assignment'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) await _refresh();
  }

  Widget _customerPage() => ListView(
    padding: const EdgeInsets.only(bottom: 28),
    children: [
      _sectionHeader('Customers', subtitle: '1 test customer · Local only'),
      Card(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0x203B82F6),
            child: Icon(Icons.person_outline, color: BriskersColors.customers)),
          title: const Text(BriskersLabFixture.customerName,
            style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('2 vehicles'),
          onTap: () => _openVehicleJob(0),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
      for (var i = 0; i < BriskersLabFixture.vehicles.length; i++)
        Card(
          margin: const EdgeInsets.fromLTRB(10, 5, 10, 0),
          child: ListTile(
            leading: const Icon(Icons.directions_car_outlined,
              color: BriskersColors.vehicles),
            title: Text("${BriskersLabFixture.vehicles[i]['year']} ${BriskersLabFixture.vehicles[i]['make']} ${BriskersLabFixture.vehicles[i]['model']}",
              style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(i == 0
              ? 'Job J-24 · Invoice #6342'
              : 'No job in the isolated test copy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openVehicleJob(i),
          ),
        ),
    ],
  );

  static const _jobStatusChoices = <(String, String, IconData, Color)>[
    ('open', 'Open', Icons.work_outline, Color(0xFF546E7A)),
    ('in_progress', 'In Progress', Icons.build_circle_outlined,
      BriskersColors.jobs),
    ('pending_approval', 'Pending Approval', Icons.approval_outlined,
      Color(0xFFE59A00)),
    ('waiting_parts', 'Waiting Parts', Icons.local_shipping_outlined,
      Color(0xFFEF6C00)),
    ('needs_recheck', 'Needs Recheck', Icons.troubleshoot_outlined,
      Color(0xFFC62828)),
    ('completed', 'Completed', Icons.task_alt, Color(0xFF2E7D32)),
    ('cancelled', 'Cancelled', Icons.cancel_outlined, Color(0xFF757575)),
  ];

  (String, String, IconData, Color) get _currentJobStatusInfo =>
    _jobStatusChoices.firstWhere(
      (item) => item.$1 == jobStatusCode,
      orElse: () => _jobStatusChoices.first,
    );

  Widget _jobStatusControl() {
    final current = _currentJobStatusInfo;
    return PopupMenuButton<String>(
      tooltip: 'Change job status',
      onSelected: _changeJobStatus,
      itemBuilder: (context) => [
        for (final option in _jobStatusChoices)
          PopupMenuItem<String>(
            value: option.$1,
            child: Row(children: [
              Icon(option.$3, color: option.$4, size: 20),
              const SizedBox(width: 8),
              Text(option.$2),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: current.$4.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: current.$4.withValues(alpha: 0.55)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(current.$3, color: current.$4, size: 17),
          const SizedBox(width: 4),
          Text(current.$2, style: TextStyle(
            color: current.$4, fontSize: 11,
            fontWeight: FontWeight.w800)),
          Icon(Icons.arrow_drop_down, color: current.$4, size: 18),
        ]),
      ),
    );
  }

  List<Map<String, String>> _activeTaskIdentities(
      List<Map<String, dynamic>> active) => [
    for (final task in active)
      {
        'document_id': task['document_id'].toString(),
        'line_id': task['line_id'].toString(),
      },
  ];

  Future<void> _changeJobStatus(String next) async {
    if (next == jobStatusCode) return;
    final active = tasks.where((t) => t['source_missing'] != 1).toList();
    if (next == 'completed') {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Complete job J-24?'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 390),
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Confirm all required tasks are complete. '
                  'Unfinished tasks will be marked Done individually.'),
                const SizedBox(height: 10),
                for (final task in active)
                  ListTile(
                    dense: true, contentPadding: EdgeInsets.zero,
                    leading: Icon(task['status'] == 'done'
                        ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 20, color: BriskersColors.jobs),
                    title: Text(_description(task)),
                    subtitle: Text('${_laborAssignment(task)} · '
                      '${task['status'] == 'done'
                        ? 'Already Done' : 'Will mark Done'}'),
                  ),
                const SizedBox(height: 8),
                const Text('The job status and task statuses update '
                  'together. Invoice payment and payroll remain unchanged.',
                  style: TextStyle(fontSize: 12,
                    color: Color(0xFF64748B))),
              ],
            )),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Complete Job')),
          ],
        ),
      );
      if (result != true) return;
    }
    try {
      await store.changeJobStatus(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        statusCode: next,
        confirmedTasks: next == 'completed'
          ? _activeTaskIdentities(active) : null,
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next == 'completed'
            ? 'Job and all tasks marked Completed'
            : 'Job status updated to ${_currentJobStatusInfo.$2}'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update job status: $error')));
      }
    }
  }

  Future<void> _offerCompleteJobIfReady() async {
    final active = tasks.where((task) => task['source_missing'] != 1).toList();
    if (!mounted || jobStatusCode == 'completed' || active.isEmpty ||
        !active.every((task) => task['status'] == 'done')) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('All tasks are Done'),
        content: const Text('Would you like to mark the entire job Completed '
          'or keep the job open for now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep Open')),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Complete Job')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await store.changeJobStatus(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        statusCode: 'completed',
        confirmedTasks: _activeTaskIdentities(active),
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not complete job: $error')));
      }
    }
  }

  Future<void> _confirmCompleteAllTasks() async {
    final active = tasks.where((task) =>
        task['source_missing'] != 1).toList();
    final unfinished = active.where((task) =>
        task['status'] != 'done').length;
    if (active.isEmpty || unfinished == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Mark all job tasks Done?'),
        content: SizedBox(
          width: 380,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Job J-24 · $unfinished unfinished of '
                    '${active.length} tasks. Confirm the work is complete.'),
                  const SizedBox(height: 10),
                  for (final task in active)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        task['status'] == 'done'
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                        size: 22,
                        color: BriskersColors.jobs,
                      ),
                      title: Text(_description(task),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${_laborAssignment(task)} · '
                        '${task['status'] == 'done'
                            ? 'Already Done' : 'Will mark Done'}',
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text('Each unfinished task will be completed '
                    'individually in the Work Log. Payroll Preview updates '
                    'automatically. The job and invoice remain open.',
                    style: TextStyle(fontSize: 12,
                      color: Color(0xFF64748B))),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialog, true),
            icon: const Icon(Icons.done_all),
            label: Text('Mark $unfinished Done'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final count = await store.completeConfirmedJobTasks(
        businessId: BriskersLabFixture.businessId,
        jobId: BriskersLabFixture.jobId,
        confirmedTasks: [
          for (final task in active)
            {
              'document_id': task['document_id'].toString(),
              'line_id': task['line_id'].toString(),
            },
        ],
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count tasks marked Done')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not complete tasks: $error')),
        );
      }
    }
    await _offerCompleteJobIfReady();
  }

  Widget _jobsListPage() => ListView(
    children: [
      _sectionHeader('Jobs', subtitle: '1 example job · Offline TEST'),
      Card(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: BriskersColors.jobs.withValues(alpha: 0.06),
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0x2000897B),
            child: Icon(Icons.build_outlined, color: BriskersColors.jobs)),
          title: const Text('J-24 · Richard Goff',
            style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text(
            'Oil leaks, maintenance\n2012 Hyundai Equus · 4 labor tasks'),
          isThreeLine: true,
          trailing: _jobStatusControl(),
          onTap: () => _openVehicleJob(0),
        ),
      ),
    ],
  );

  Widget _jobInfoRow(IconData icon, String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: BriskersColors.jobs.withValues(alpha: 0.12),
          child: Icon(icon, color: BriskersColors.jobs, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
              color: Color(0xFF667085), fontSize: 12.8)),
            Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        )),
      ],
    ),
  );

  Widget _jobCategoryTile(
    String label, IconData icon, Color color, VoidCallback onTap,
    {int count = 0}
  ) => SizedBox(
    height: 85,
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(3, 7, 3, 5),
          child: Column(
            children: [
              Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                backgroundColor: Colors.red,
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: color.withValues(alpha: 0.13),
                  child: Icon(icon, color: color, size: 19),
                ),
              ),
              const SizedBox(height: 5),
              Expanded(child: Center(
                child: Text(label, maxLines: 3,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.2, fontWeight: FontWeight.w800,
                    height: 1.12)),
              )),
            ],
          ),
        ),
      ),
    ),
  );

  void _labNotice(String title) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              const Text('This section has no data in the isolated test copy. '
                'The regular Briskers app and its live records are unchanged.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jobPage() {
    if (!jobDetailsOpen) return _jobsListPage();
    final vehicle = BriskersLabFixture.vehicles[selectedVehicle];
    final firstVehicle = selectedVehicle == 0;
    final activeTasks = tasks.where((t) => t['source_missing'] != 1).length;
    final completed = tasks.where((t) =>
        t['source_missing'] != 1 && t['status'] == 'done').length;
    Widget tile(
      String label, IconData icon, Color color, VoidCallback onTap,
      {int count = 0}
    ) => Expanded(child: _jobCategoryTile(
      label, icon, color, onTap, count: count));
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 38),
      children: [
        Row(children: [
          IconButton(
            onPressed: () => _navigate(2),
            icon: const Icon(Icons.arrow_back)),
          Text(firstVehicle ? 'Job J-24' : 'Vehicle details',
            style: const TextStyle(
              fontSize: 21, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (firstVehicle) _jobStatusControl(),
        ]),
        Container(
          padding: const EdgeInsets.fromLTRB(13, 5, 13, 8),
          decoration: BoxDecoration(
            color: BriskersColors.jobs.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: BriskersColors.jobs.withValues(alpha: 0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _jobInfoRow(Icons.person_outline, 'Customer',
                BriskersLabFixture.customerName),
              const Divider(height: 1),
              _jobInfoRow(Icons.directions_car_outlined, 'Vehicle',
                "${vehicle['year']} ${vehicle['make']} ${vehicle['model']}"),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(5, 11, 5, 5),
                child: Text(firstVehicle
                  ? 'Oil leaks, maintenance'
                  : 'No current job in test copy',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15.5)),
              ),
              if (firstVehicle) const Padding(
                padding: EdgeInsets.only(left: 5, bottom: 4),
                child: Text('Invoice #6342 · Tasks TEST · Offline only',
                  style: TextStyle(fontSize: 12,
                    color: Color(0xFF667085))),
              ),
              if (firstVehicle) ...[
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 3),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x2000897B),
                    child: Icon(Icons.engineering_outlined,
                      color: BriskersColors.jobs)),
                  title: const Text('Main job mechanic',
                    style: TextStyle(fontSize: 12.8)),
                  subtitle: Text(_employeeName(leadMechanicId),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _assignLeadMechanic,
                ),
              ],

            ],
          ),
        ),
        const SizedBox(height: 14),
        if (firstVehicle) ...[
          Row(children: [
            tile('Pre-inspection', Icons.search, const Color(0xFF6B4BC3),
              () => _labNotice('Pre-inspection')),
            const SizedBox(width: 8),
            tile('Customer Complaint', Icons.description_outlined,
              BriskersColors.customers,
              () => _labNotice('Customer Complaint')),
            const SizedBox(width: 8),
            tile('Findings', Icons.car_repair_outlined, Colors.deepOrange,
              () => _labNotice('Findings')),
            const SizedBox(width: 8),
            tile('Estimates', Icons.request_quote_outlined,
              BriskersColors.estimates, () => _navigate(7)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            tile('Invoices', Icons.receipt_long_outlined,
              BriskersColors.invoices, () => _navigate(8), count: 1),
            const SizedBox(width: 8),
            tile('Work Performed', Icons.build_outlined,
              const Color(0xFF15988F), () => _navigate(4),
              count: completed),
            const SizedBox(width: 8),
            tile('Job Expenses', Icons.payments_outlined,
              BriskersColors.expenses, () => _labNotice('Job Expenses')),
            const SizedBox(width: 8),
            tile('Profitability', Icons.analytics_outlined,
              BriskersColors.reports, () => _labNotice('Job Profitability')),
          ]),
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x2000897B),
                    child: Icon(Icons.rule_outlined,
                      color: BriskersColors.jobs)),
                  title: const Text('Tasks (TEST)',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('$activeTasks labor tasks · $completed done'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _navigate(3),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history_outlined,
                    color: BriskersColors.today),
                  title: const Text('Work Log',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Completed work by mechanic'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _navigate(4),
                ),
              ],
            ),
          ),
        ] else const Padding(
          padding: EdgeInsets.all(14),
          child: Text('The second car is shown for customer/navigation '
            'testing only; no service records were copied.'),
        ),
      ],
    );
  }

  // A chronological, read-only ledger, separate from the editable Tasks
  // page. Prior completion cycles are shown alongside current Done tasks.
  Widget _workLogPage() {
    final records = <({
      int completedAt,
      String description,
      String assignment,
      bool earlier,
    })>[
      for (final task in tasks)
        if (task['source_missing'] != 1 && task['status'] == 'done')
          (
            completedAt: task['completed_at'] is int
              ? task['completed_at'] as int : 0,
            description: _description(task),
            assignment: _laborAssignment(task),
            earlier: false,
          ),
      for (final entry in earlierWorkLog)
        (
          completedAt: entry['completed_at'] is int
            ? entry['completed_at'] as int : 0,
          description: entry['description']?.toString() ?? 'Work completed',
          assignment: _displayArchivedAssignment(
            entry['assignment_summary']?.toString() ?? 'Unassigned'),
          earlier: true,
        ),
    ];
    records.sort((a, b) {
      final difference = b.completedAt.compareTo(a.completedAt);
      return difference != 0
        ? difference : a.description.compareTo(b.description);
    });

    final entries = <Widget>[];
    String? lastDay;
    for (final item in records) {
      final date = item.completedAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(item.completedAt)
        : null;
      final dayKey = date == null
        ? 'unknown' : DateFormat('yyyy-MM-dd').format(date);
      if (dayKey != lastDay) {
        lastDay = dayKey;
        entries.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 5),
          child: Text(
            date == null
              ? 'Date not recorded'
              : DateFormat('EEE, MMM d, yyyy').format(date),
            style: const TextStyle(fontSize: 13,
              color: Color(0xFF64748B), fontWeight: FontWeight.w800),
          ),
        ));
      }
      entries.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFE1E7EB), width: 0.7))),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 68,
                  child: Text(
                    date == null ? '—' : DateFormat('h:mm a').format(date),
                    style: const TextStyle(fontSize: 11.5,
                      color: Color(0xFF64748B)),
                  ),
                ),
                const Icon(Icons.check_circle,
                  color: Color(0xFF169D70), size: 19),
                const SizedBox(width: 9),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.description, maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.8,
                        fontWeight: FontWeight.w700, height: 1.2)),
                    const SizedBox(height: 2),
                    Text(item.assignment, maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF526273), height: 1.2)),
                    if (item.earlier)
                      const Text('Previous completion',
                        style: TextStyle(fontSize: 10.5,
                          color: Color(0xFF64748B))),
                  ],
                )),
              ],
            ),
          ),
        ),
      ));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
      children: [
        _sectionHeader('Work Log',
          subtitle: 'Completion history · Read-only'),
        if (records.isEmpty)
          const ListTile(title: Text('No completed work yet')),
        ...entries,
      ],
    );
  }

  String _displayArchivedAssignment(String raw) {
    var description = raw;
    for (final employee in BriskersLabFixture.employees) {
      final id = employee['id'];
      if (id != null) {
        description = description.replaceAll(
          id, _employeeName(id),
        );
      }
    }
    return description;
  }

  Future<void> _addRecheckWork() async {
    final description = TextEditingController();
    final hours = TextEditingController();
    String assignee = leadMechanicId ?? '';
    final added = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      showDragHandle: true, useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16,
            MediaQuery.viewInsetsOf(sheet).bottom + 20),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add recheck work',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              const Text('Not on Invoice · Extra labor for a recheck. '
                'Does not change customer charges.',
                style: TextStyle(color: Color(0xFF64748B))),
              const SizedBox(height: 12),
              TextField(controller: description, minLines: 2, maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Additional work description',
                  border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: hours,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Additional payroll hours',
                  border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: assignee,
                decoration: const InputDecoration(
                  labelText: 'Assigned mechanic',
                  border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(
                    value: '', child: Text('Unassigned')),
                  for (final employee in BriskersLabFixture.employees)
                    if (employee['role'] == 'mechanic' ||
                        employee['role'] == 'owner')
                      DropdownMenuItem(
                        value: employee['id']!,
                        child: Text(_employeeName(employee['id'])),
                      ),
                ],
                onChanged: (v) => update(() => assignee = v ?? ''),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  final qty = double.tryParse(hours.text.trim());
                  if (description.text.trim().isEmpty ||
                      qty == null || !qty.isFinite || qty <= 0) {
                    ScaffoldMessenger.of(sheet).showSnackBar(
                      const SnackBar(content: Text(
                        'Enter a description and positive hours')));
                    return;
                  }
                  try {
                    await store.addRecheckTask(
                      businessId: BriskersLabFixture.businessId,
                      jobId: BriskersLabFixture.jobId,
                      description: description.text,
                      hours: qty, employeeId: assignee);
                    if (sheet.mounted) Navigator.pop(sheet, true);
                  } catch (error) {
                    if (sheet.mounted) {
                      ScaffoldMessenger.of(sheet).showSnackBar(
                        SnackBar(content: Text('$error')));
                    }
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add recheck task'),
              ),
            ],
          )),
        ),
      ),
    );
    description.dispose();
    hours.dispose();
    if (added == true) await _refresh();
  }

  Widget _taskList({bool history = false}) {
    if (history) return _workLogPage();
    final visible = tasks.where(
      (task) => task['source_missing'] != 1).toList();
    return ListView(
      children: [
        _sectionHeader('Job tasks',
          subtitle: 'Invoice #6342 · Assign Kam and Chris by task'),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(children: [
            const Text('Job status', style: TextStyle(
              fontWeight: FontWeight.w700)),
            const Spacer(),
            _jobStatusControl(),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: OutlinedButton.icon(
            onPressed: jobStatusCode == 'completed'
              ? null : _addRecheckWork,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add Task · Not on Invoice'),
          ),
        ),
        if (visible.any((task) => task['status'] != 'done'))
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: OutlinedButton.icon(
              onPressed: _confirmCompleteAllTasks,
              icon: const Icon(Icons.done_all),
              label: const Text('Mark all tasks Done'),
            ),
          ),
        if (visible.isEmpty)
          const ListTile(title: Text('No tasks yet')),
        ...visible.map(_taskCard),
      ],
    );
  }

  Widget _payrollPage() {
    // Earned hours are retained across recheck without duplicating the
    // same invoice labor task's original credit. No payments are posted.
    final byEmployee = earnedPayrollPreviewHours;
    return ListView(
      children: [
        _sectionHeader('Payroll preview',
          subtitle: 'Earned hours retained after recheck · No real payments'),
        for (final employee in BriskersLabFixture.employees)
          if (employee['role'] != 'secretary') Card(
            margin: const EdgeInsets.fromLTRB(10, 3, 10, 5),
            child: ListTile(
              title: Text(_employeeName(employee['id'])),
              trailing: Text(
                "${(byEmployee[employee['id']] ?? 0).toStringAsFixed(1)} hrs",
                style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800,
                  color: BriskersColors.jobs),
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('This is an earned-hours preview, not a payment. '
            'Original completed hours remain after reopening; '
            'completing the same task again does not earn a second allocation. '
            'New recheck labor requires a separate task. '
            'No compensation rates or transactions are connected.'),
        ),
      ],
    );
  }

  Widget _settingsPage() => ListView(
    children: [
      _sectionHeader('Test Settings'),
      ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: const Text('Edit employee names'),
        subtitle: const Text('Full names and preferred display names'),
        onTap: _editEmployeeNames,
      ),
      const ListTile(
        leading: Icon(Icons.shield_outlined),
        title: Text('Production disconnected'),
        subtitle: Text('Separate Android application and local data. '
          'No live server access, payments or synchronization.'),
      ),
    ],
  );

  Widget _homeTile(
    String title, String summary, IconData icon, Color color, VoidCallback go,
  ) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: go,
    child: Container(
      height: 75,
      padding: const EdgeInsets.fromLTRB(12, 7, 9, 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800)),
          const Spacer(),
          Row(children: [
            Icon(icon, color: color, size: 27),
            const SizedBox(width: 7),
            Expanded(child: Text(summary,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12,
                color: Color(0xFF667085), fontWeight: FontWeight.w700))),
            Icon(Icons.chevron_right, color: color, size: 21),
          ]),
        ],
      ),
    ),
  );

  Widget _overviewPage() {
    Widget tileRow(Widget first, Widget second) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(child: first), const SizedBox(width: 10),
        Expanded(child: second),
      ]),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 35),
      children: [
        Row(children: [
          Image.asset('assets/briskers_header_logo.png',
            width: 162, height: 50, fit: BoxFit.contain,
            errorBuilder: (_, error, trace) => const Text('Briskers',
              style: TextStyle(fontSize: 27,
                color: Color(0xFF1767B3), fontWeight: FontWeight.w900))),
          const Spacer(),
          const Icon(Icons.shield_outlined, color: BriskersColors.jobs),
        ]),
        const SizedBox(height: 6),
        const Text('Briskers Tasks TEST',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        Text(DateFormat('EEEE, MMM d, yyyy').format(DateTime.now()),
          style: const TextStyle(color: Color(0xFF667085))),
        const SizedBox(height: 8),
        const Text('Standalone offline copy · Real shop data is not connected',
          style: TextStyle(fontSize: 12,
            color: BriskersColors.jobs, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        tileRow(
          _homeTile('Customers', '1 Test customer',
            Icons.people_outline, BriskersColors.customers,
            () => _navigate(1)),
          _homeTile('Appointments', 'No test appointments',
            Icons.calendar_month_outlined, BriskersColors.appointments,
            () => _navigate(9)),
        ),
        tileRow(
          _homeTile('Estimates', 'No test estimates',
            Icons.request_quote_outlined, BriskersColors.estimates,
            () => _navigate(7)),
          _homeTile('Invoices', '1 Example invoice',
            Icons.receipt_long_outlined, BriskersColors.invoices,
            () => _navigate(8)),
        ),
        tileRow(
          _homeTile('Jobs', '1 Example job',
            Icons.build_outlined, BriskersColors.jobs,
            () => _navigate(2)),
          _homeTile('Expenses', 'No financial data',
            Icons.payments_outlined, BriskersColors.expenses,
            () => _navigate(10)),
        ),
        const SizedBox(height: 17),
        const Text('New functions being tested',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        tileRow(
          _homeTile('Tasks', '${tasks.length} Labor tasks',
            Icons.rule_outlined, BriskersColors.jobs,
            () => _navigate(3)),
          _homeTile('Work Log', 'Completed task history',
            Icons.history_outlined, BriskersColors.today,
            () => _navigate(4)),
        ),
        tileRow(
          _homeTile('Payroll', 'Hours preview only',
            Icons.account_balance_wallet_outlined, BriskersColors.invoices,
            () => _navigate(5)),
          _homeTile('Employees', 'Edit all names',
            Icons.badge_outlined, BriskersColors.settings,
            _editEmployeeNames),
        ),
      ],
    );
  }

  Widget _readOnlyModule(
    String title, String description, IconData icon, Color color,
  ) => ListView(
    children: [
      _sectionHeader(title, subtitle: 'Isolated offline test'),
      Card(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: color.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            Icon(icon, size: 38, color: color),
            const SizedBox(height: 12),
            Text(description, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('No live records, financial values, or '
              'production synchronization are available.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF667085))),
          ]),
        ),
      ),
    ],
  );

  Widget _testInvoicePage() => ListView(
    children: [
      _sectionHeader('Invoices',
        subtitle: 'Read-only sanitized source for Tasks'),
      Card(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(children: [
          const ListTile(
            leading: Icon(Icons.receipt_long_outlined,
              color: BriskersColors.invoices),
            title: Text('Invoice #6342',
              style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Richard Goff · 2012 Hyundai Equus'),
          ),
          const Divider(height: 1),
          for (final task in tasks.where((t) =>
              t['source_missing'] != 1 &&
              t['document_id'] == BriskersLabFixture.invoiceId))
            ListTile(
              dense: true,
              title: Text(task['source_description']?.toString() ?? 'Labor'),
              subtitle: Text(_laborAssignment(task)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editInvoiceLabor(task),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Financial totals are intentionally not copied. '
              'Edit test tasks from Jobs → Tasks.',
              style: TextStyle(fontSize: 12,
                color: Color(0xFF667085))),
          ),
        ]),
      ),
    ],
  );

  Widget _morePage() => ListView(children: [
    _sectionHeader('More', subtitle: 'Tasks TEST features'),
    ListTile(
      leading: const Icon(Icons.account_balance_wallet_outlined,
        color: BriskersColors.invoices),
      title: const Text('Payroll preview'),
      onTap: () => _navigate(5),
      trailing: const Icon(Icons.chevron_right),
    ),
    ListTile(
      leading: const Icon(Icons.badge_outlined,
        color: BriskersColors.customers),
      title: const Text('Employees and display names'),
      onTap: _editEmployeeNames,
      trailing: const Icon(Icons.chevron_right),
    ),
    ListTile(
      leading: const Icon(Icons.settings_outlined,
        color: BriskersColors.settings),
      title: const Text('Settings'),
      onTap: () => _navigate(6),
      trailing: const Icon(Icons.chevron_right),
    ),
  ]);

  Widget _body() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(12), child: Text(error!));
    }
    switch (page) {
      case 0: return _overviewPage();
      case 1: return _customerPage();
      case 2: return _jobPage();
      case 3: return _taskList();
      case 4: return _taskList(history: true);
      case 5: return _payrollPage();
      case 6: return _settingsPage();
      case 7: return _readOnlyModule('Estimates',
        'There are no estimates in this sanitized test copy.',
        Icons.request_quote_outlined, BriskersColors.estimates);
      case 8: return _testInvoicePage();
      case 9: return _readOnlyModule('Schedule',
        'Appointments were not included in this test copy.',
        Icons.calendar_month_outlined, BriskersColors.appointments);
      case 10: return _readOnlyModule('Expenses',
        'No expenses or payments have been copied.',
        Icons.payments_outlined, BriskersColors.expenses);
      default: return _morePage();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: expandedMenu == null,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && expandedMenu != null) {
        setState(() => expandedMenu = null);
      }
    },
    child: Scaffold(
    appBar: page == 0 ? null : AppBar(
      backgroundColor: BriskersColors.jobs.withValues(alpha: 0.08),
      toolbarHeight: 78,
      titleSpacing: 10,
      title: Row(children: [
        Image.asset('assets/briskers_header_logo.png',
          height: 44, width: 148, fit: BoxFit.contain,
          errorBuilder: (_, error, trace) => const Text('Briskers',
            style: TextStyle(
              color: Color(0xFF1767B3), fontWeight: FontWeight.w900))),
        const Spacer(),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('TASKS TEST', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800,
              color: BriskersColors.jobs)),
            Text('OFFLINE · ISOLATED', style: TextStyle(
              fontSize: 10, color: Color(0xFF667085))),
          ],
        ),
      ]),
      actions: [
        IconButton(
          tooltip: 'Employee names',
          onPressed: _editEmployeeNames,
          icon: const Icon(Icons.badge_outlined)),
      ],
    ),
    body: Stack(
      children: [
        Positioned.fill(child: _body()),
        if (expandedMenu != null) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => expandedMenu = null),
              child: const ColoredBox(color: Color(0x0A000000)),
            ),
          ),
          Positioned(
            bottom: 10,
            left: (menuAnchorX - 90)
              .clamp(8.0, MediaQuery.sizeOf(context).width - 188)
              .toDouble(),
            child: _verticalMenu(expandedMenu!),
          ),
        ],
      ],
    ),
    bottomNavigationBar: _bottomNav(),
  ),
  );
}
