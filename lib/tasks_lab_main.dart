import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  int page = 2;
  int? expandedMenu;
  int selectedVehicle = 0;
  bool loading = true;
  String? error;

  static const navLabels = ['Home', 'Customers', 'Jobs', 'More'];
  static const navIcons = [
    Icons.home_outlined, Icons.people_outline, Icons.build_outlined,
    Icons.more_horiz,
  ];

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
    if (!mounted) return;
    setState(() {
      tasks = rows;
      nicknames = aliases;
      fullNames = names;
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
    });
  }

  void _toggleMenu(int navIndex) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      expandedMenu = expandedMenu == navIndex ? null : navIndex;
    });
  }

  bool _isNavSelected(int index) {
    if (index == 2) return page == 2 || page == 3 || page == 4;
    if (index == 3) return page == 5 || page == 6;
    return page == index;
  }

  // Keep the familiar phone-width bottom bar. Long-press Jobs or More
  // to unfold the related destination icons vertically above that icon.
  Widget _bottomNav() => SafeArea(
    top: false,
    child: Container(
      height: 68,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF2FA),
        border: Border(top: BorderSide(color: Color(0xFFD0DEEB))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < navLabels.length; i++)
            Expanded(
              child: InkWell(
                onTap: () {
                  if (i == 3) {
                    _toggleMenu(i);
                  } else {
                    _navigate(i);
                  }
                },
                onLongPress: (i == 2 || i == 3)
                  ? () => _toggleMenu(i)
                  : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      navIcons[i],
                      size: 26,
                      color: _isNavSelected(i)
                        ? const Color(0xFF1263B3)
                        : const Color(0xFF64748B),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      navLabels[i],
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: _isNavSelected(i)
                          ? FontWeight.w800 : FontWeight.w500,
                        color: _isNavSelected(i)
                          ? const Color(0xFF1263B3)
                          : const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
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
          if (index == 3) ...[
            _menuEntry(Icons.account_balance_wallet_outlined, 'Payroll', 5),
            const Divider(height: 1),
            _menuEntry(Icons.settings_outlined, 'Settings', 6),
          ],
        ],
      ),
    ),
  );

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

  Widget _taskCard(Map<String, dynamic> task, {bool history = false}) {
    final done = task['status'] == 'done';
    final stamp = task['completed_at'];
    final finished = stamp is int
      ? DateFormat('MMM d, h:mm a').format(
          DateTime.fromMillisecondsSinceEpoch(stamp)) : '';
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
            Text("${_employeeName(task['employee_id']?.toString())} · ${task['payroll_hours']?.toString() ?? '—'} hrs"),
            if (history)
              Text(finished.isEmpty ? 'Completion not recorded' : finished)
            else _statusChip(task['status']?.toString() ?? 'planned'),
          ],
        ),
        trailing: const Icon(Icons.edit_outlined, size: 19),
        onTap: () => _editTask(task),
      ),
    );
  }

  Future<void> _editTask(Map<String, dynamic> task) async {
    var mechanic = task['employee_id']?.toString() ?? '';
    var status = task['status']?.toString() ?? 'planned';
    final description = TextEditingController(text: _description(task));
    final hours = TextEditingController(
      text: task['payroll_hours']?.toString() ?? '',
    );
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
                DropdownButtonFormField<String>(
                  initialValue: mechanic,
                  decoration: const InputDecoration(
                    labelText: 'Assigned mechanic',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '', child: Text('Unassigned')),
                    for (final employee in BriskersLabFixture.employees)
                      if (employee['role'] != 'secretary') DropdownMenuItem(
                        value: employee['id']!,
                        child: Text(_employeeName(employee['id'])),
                      ),
                  ],
                  onChanged: (v) {
                    setModalState(() => mechanic = v ?? '');
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hours,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Mechanic hours', border: OutlineInputBorder()),
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
                    final raw = hours.text.trim();
                    final value = raw.isEmpty
                      ? null : double.tryParse(raw);
                    if (raw.isNotEmpty && value == null) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(content: Text('Enter valid hours')));
                      return;
                    }
                    try {
                      await store.editTask(
                        businessId: BriskersLabFixture.businessId,
                        jobId: BriskersLabFixture.jobId,
                        documentId: BriskersLabFixture.invoiceId,
                        lineId: task['line_id'].toString(),
                        description: description.text,
                        editDescription: true,
                        employeeId: mechanic, editEmployee: true,
                        hours: value, editHours: true,
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
    hours.dispose();
    if (updated == true) {
      await _refresh();
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

  Widget _customerPage() => ListView(
    children: [
      _sectionHeader('Customers', subtitle: 'Local test data only'),
      Card(
        margin: const EdgeInsets.all(12),
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: const Text(BriskersLabFixture.customerName,
            style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('2 vehicles'),
          onTap: () => _navigate(2),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
      for (var i = 0; i < BriskersLabFixture.vehicles.length; i++)
        ListTile(
          leading: const Icon(Icons.directions_car_outlined),
          title: Text("${BriskersLabFixture.vehicles[i]['year']} ${BriskersLabFixture.vehicles[i]['make']} ${BriskersLabFixture.vehicles[i]['model']}"),
          subtitle: Text(i == 0 ? 'Job J-24 · Invoice #6342'
            : 'No current job in test copy'),
          onTap: () => setState(() {
            selectedVehicle = i; page = 2;
          }),
        ),
    ],
  );

  Widget _jobPage() {
    final vehicle = BriskersLabFixture.vehicles[selectedVehicle];
    return ListView(
      children: [
        _sectionHeader('Job details',
          subtitle: BriskersLabFixture.customerName),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${vehicle['year']} ${vehicle['make']} ${vehicle['model']}",
                  style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(selectedVehicle == 0
                  ? 'J-24 · Oil leaks, maintenance'
                  : 'No current job · Ready for test entry'),
                const SizedBox(height: 8),
                if (selectedVehicle == 0)
                  const Text('Invoice #6342 · 4 labor tasks'),
              ],
            ),
          ),
        ),
        if (selectedVehicle == 0) ...[
          _sectionHeader('Tasks',
            subtitle: 'Automatically copied from invoice labor'),
          ...tasks.where((t) => t['source_missing'] != 1)
            .map(_taskCard),
          Padding(
            padding: const EdgeInsets.all(10),
            child: FilledButton.icon(
              onPressed: () => _navigate(4),
              icon: const Icon(Icons.history),
              label: const Text('View Work Log'),
            ),
          ),
        ] else const Padding(
          padding: EdgeInsets.all(16),
          child: Text('This second vehicle is available for navigation '
            'testing. No real service record was copied for it.'),
        ),
      ],
    );
  }

  Widget _taskList({bool history = false}) {
    final visible = tasks.where((t) =>
      history ? t['status'] == 'done' : t['source_missing'] != 1).toList();
    return ListView(
      children: [
        _sectionHeader(history ? 'Work Log' : 'Job tasks',
          subtitle: history
            ? 'Completed tasks automatically appear here'
            : 'Invoice #6342 · Assign Kam and Chris by task'),
        if (visible.isEmpty)
          const ListTile(title: Text('No entries yet')),
        ...visible.map((t) => _taskCard(t, history: history)),
      ],
    );
  }

  Widget _payrollPage() {
    final byEmployee = <String, double>{};
    for (final task in tasks) {
      if (task['status'] != 'done') continue;
      final employee = task['employee_id']?.toString() ?? '';
      if (employee.isEmpty) continue;
      final hours = (task['payroll_hours'] as num?)?.toDouble() ?? 0;
      byEmployee[employee] = (byEmployee[employee] ?? 0) + hours;
    }
    return ListView(
      children: [
        _sectionHeader('Payroll preview',
          subtitle: 'Completed assigned hours · No real payments'),
        for (final employee in BriskersLabFixture.employees)
          if (employee['role'] != 'secretary') Card(
            margin: const EdgeInsets.fromLTRB(10, 3, 10, 5),
            child: ListTile(
              title: Text(_employeeName(employee['id'])),
              trailing: Text(
                "${(byEmployee[employee['id']] ?? 0).toStringAsFixed(1)} hrs"),
            ),
          ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('This is only a demonstration of task hours. '
            'No compensation rates or payroll transactions are connected.'),
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

  Widget _overviewPage() => ListView(
    children: [
      _sectionHeader('Briskers Tasks TEST',
        subtitle: 'Standalone offline workshop prototype'),
      const ListTile(
        leading: Icon(Icons.person_outline),
        title: Text('Richard Goff'),
        subtitle: Text('2 cars · 1 copied example invoice'),
      ),
      ListTile(
        leading: const Icon(Icons.list_alt_outlined),
        title: Text('${tasks.length} labor tasks'),
        onTap: () => _navigate(3),
      ),
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('Work Log'),
        onTap: () => _navigate(4),
      ),
    ],
  );

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
      default: return _settingsPage();
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
    appBar: AppBar(
      backgroundColor: const Color(0xFFE1F0F2),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Briskers', style: TextStyle(
            color: Color(0xFF1767B3), fontWeight: FontWeight.w900)),
          Text('TASKS TEST · OFFLINE', style: TextStyle(
            fontSize: 11, color: Color(0xFF007F79))),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Employee names',
          onPressed: _editEmployeeNames,
          icon: const Icon(Icons.badge_outlined)),
        IconButton(
          tooltip: 'Refresh local test data',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh)),
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
            left: expandedMenu == 2
              ? (MediaQuery.sizeOf(context).width * 0.625 - 90)
                  .clamp(8.0, MediaQuery.sizeOf(context).width - 188)
                  .toDouble()
              : null,
            right: expandedMenu == 3 ? 8 : null,
            child: _verticalMenu(expandedMenu!),
          ),
        ],
      ],
    ),
    bottomNavigationBar: _bottomNav(),
  ),
  );
}
