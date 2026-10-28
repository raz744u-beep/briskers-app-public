// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'core/briskers_colors.dart';
import 'widgets/briskers_module_dock.dart';

import 'local/local_database_provider.dart';
import 'services/local_job_tasks_lab_store.dart';
import 'tasks_lab/fixture.dart';
import 'tasks_lab/employee_payroll_profile.dart';
import 'tasks_lab/tasks_workspace.dart';
import 'tasks_lab/payroll_overview_screen.dart';

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
      colorScheme: ColorScheme.fromSeed(seedColor: BriskersColors.jobs),
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
  List<Map<String, dynamic>> shopTasks = const [];
  Map<String, String> nicknames = const {};
  Map<String, String> fullNames = const {};
  String? leadMechanicId;
  String jobStatusCode = 'open';
  List<Map<String, dynamic>> completedWorkRows = const [];
  final Set<String> expandedTaskKeys = <String>{};
  Map<String, List<Map<String, dynamic>>> allocationsByLine = {};
  Map<String, String> mechanicProgressByKey = const {};
  final Set<String> _changingMechanicProgress = <String>{};

  Map<String, double> earnedPayrollPreviewHours = {};
  Map<String, int> testHourlyRates = {};
  List<Map<String, dynamic>> testPayrollPayments = const [];
  List<Map<String, dynamic>> earnedCorrections = const [];
  int invoiceTestTab = 0;
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
    final shopRows = await store.shopTasks(BriskersLabFixture.businessId);
    final aliases = await store.nicknames(BriskersLabFixture.businessId);
    final names = await store.fullNames(BriskersLabFixture.businessId);
    final allocations = await Future.wait(rows.map((task) => store.allocations(
      businessId: BriskersLabFixture.businessId,
      jobId: BriskersLabFixture.jobId,
      documentId: task['document_id'].toString(),
      lineId: task['line_id'].toString())));
    final rates = await store.payrollRates(BriskersLabFixture.businessId);
    final payments = await store.payrollTestPayments(BriskersLabFixture.businessId);
    final corrections = await store.earnedHourCorrections(
      BriskersLabFixture.businessId, BriskersLabFixture.jobId);
    final earnedHours = await store.earnedHoursPreview(
      BriskersLabFixture.businessId, BriskersLabFixture.jobId);
    final mechanicProgressRows = await store.mechanicProgressForJob(
      BriskersLabFixture.businessId, BriskersLabFixture.jobId);
    final currentJobStatus = await store.jobStatus(
      BriskersLabFixture.businessId, BriskersLabFixture.jobId);
    final completedRecords = await store.completedWork(
      BriskersLabFixture.businessId, BriskersLabFixture.jobId);
    final lead = await store.leadMechanic(
      BriskersLabFixture.businessId, BriskersLabFixture.jobId);
    if (!mounted) return;
    setState(() {
      tasks = rows;
      shopTasks = shopRows;
      nicknames = aliases;
      fullNames = names;
      leadMechanicId = lead;
      jobStatusCode = currentJobStatus;
      completedWorkRows = completedRecords;
      earnedPayrollPreviewHours = earnedHours;
      testHourlyRates = rates;
      mechanicProgressByKey = {
        for (final p in mechanicProgressRows)
          _mechanicTaskKey(p,p['employee_id'].toString()):
            p['status'].toString(),
      };
      testPayrollPayments = payments;
      earnedCorrections = corrections;
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
    if (page == 3 || page == 4 || page == 12) return 2;
    if (page == 5 || page == 6) return 7;
    final idx = _dockPages.indexOf(page);
    return idx < 0 ? 0 : idx;
  }

  // Reuse the actual dock from the Briskers shop application.
  // Lab-only long presses reveal combined Tasks/history and Payroll/Settings upward.
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
            _menuEntry(Icons.rule_outlined, 'Job J-24 tasks', 3),
            _menuEntry(Icons.cleaning_services_outlined, 'General Tasks', 4),
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

  String _identity(Map<String, dynamic> row) {
    final doc = row['document_id']?.toString() ?? '';
    final line = row['line_id']?.toString() ?? '';
    return '${doc.length}:$doc$line';
  }

  String _mechanicTaskKey(Map<String,dynamic> task,String mechanicId) =>
    '${_identity(task)}::$mechanicId';

  List<String> _mechanicsOnTask(Map<String,dynamic> task) {
    final assigned=allocationsByLine[task['line_id']?.toString()??'']
      ?? const <Map<String,dynamic>>[];
    if(assigned.isNotEmpty) {
      return assigned.map((a)=>a['employee_id']?.toString()??'')
        .where((id)=>id.isNotEmpty).toSet().toList();
    }
    final lead=task['employee_id']?.toString()??'';
    return lead.isEmpty?const []:[lead];
  }

  String _mechanicTaskStatus(Map<String,dynamic> task,String employeeId) {
    if (_firstCompletion(task)!=null || task['status']=='done') return 'done';
    final recorded=mechanicProgressByKey[_mechanicTaskKey(task,employeeId)];
    if(recorded!=null) return recorded;
    // Before the first per-mechanic action, preserve an older TEST app's
    // already-started task. Once tracked, any missing mechanic is Not Started.
    if(task['status']=='in_progress' &&
        !_mechanicsOnTask(task).any((id)=>
          mechanicProgressByKey.containsKey(_mechanicTaskKey(task,id)))) {
      return 'in_progress';
    }
    return 'planned';
  }

  Future<void> _changeMechanicProgress(
      Map<String,dynamic> task,String employeeId,String progress) async {
    final key=_mechanicTaskKey(task,employeeId);
    if(_changingMechanicProgress.contains(key))return;
    if(progress=='done') {
      final mechanics=_mechanicsOnTask(task);
      final lastMechanic=mechanics.isNotEmpty && mechanics.every((id)=>
        id==employeeId || _mechanicTaskStatus(task,id)=='done');
      if(lastMechanic) {
        // Freezing first completion protects earned hours. Require explicit
        // confirmation before the LAST mechanic makes the whole task Done.
        final confirmed=await showDialog<bool>(
          context:context,
          builder:(dialog)=>AlertDialog(
            title:const Text('Finish entire task?'),
            content:Text('${_employeeName(employeeId)} is the final '
              'mechanic. Marking Done will finish this service task and '
              'preserve its labor hours. Continue?'),
            actions:[
              TextButton(onPressed:()=>Navigator.pop(dialog,false),
                child:const Text('Cancel')),
              FilledButton(onPressed:()=>Navigator.pop(dialog,true),
                child:const Text('Finish Task')),
            ],
          ),
        );
        if(confirmed!=true||!mounted)return;
      }
    }
    setState(()=>_changingMechanicProgress.add(key));
    try {
      await store.setMechanicTaskProgress(
        businessId:BriskersLabFixture.businessId,
        jobId:BriskersLabFixture.jobId,
        documentId:task['document_id'].toString(),
        lineId:task['line_id'].toString(),
        employeeId:employeeId,status:progress);
      await _refresh();
    } catch(error) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text('Task progress not saved: $error')));
      }
    } finally {
      if(mounted) setState(()=>_changingMechanicProgress.remove(key));
    }
  }

  Future<void> _undoMechanicDone(
      Map<String,dynamic> task,String employeeId) async {
    final name=_employeeName(employeeId);
    final confirmed = await showDialog<bool>(
      context:context,
      builder:(dialog)=>AlertDialog(
        title:const Text('Undo Done?'),
        content:Text(
          'Correct an accidental Done for $name? '
          'Their previous task progress will be restored. '
          'No payroll payments or hours will change.'),
        actions:[
          TextButton(
            onPressed:()=>Navigator.pop(dialog,false),
            child:const Text('Cancel')),
          FilledButton(
            onPressed:()=>Navigator.pop(dialog,true),
            child:const Text('Undo Done')),
        ],
      ),
    );
    if(confirmed!=true || !mounted)return;
    final key=_mechanicTaskKey(task,employeeId);
    if(_changingMechanicProgress.contains(key))return;
    setState(()=>_changingMechanicProgress.add(key));
    try {
      await store.undoAccidentalMechanicDone(
        businessId:BriskersLabFixture.businessId,
        jobId:BriskersLabFixture.jobId,
        documentId:task['document_id'].toString(),
        lineId:task['line_id'].toString(),
        employeeId:employeeId);
      await _refresh();
    } catch(error) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text('Unable to undo: $error')));
      }
    } finally {
      if(mounted)setState(()=>_changingMechanicProgress.remove(key));
    }
  }

  // The controls belong visually to this task, never the card below it.
  // Only render the panel after expansion: collapsed task cards stay compact.
  Widget _mechanicProgressControls(Map<String,dynamic> task,
      {required bool completeTask}) {
    final mechanics=_mechanicsOnTask(task);
    if(mechanics.isEmpty) {
      return Container(
        key: ValueKey('service-task-mechanics-${_identity(task)}'),
        margin:const EdgeInsets.only(top:10),
        padding:const EdgeInsets.all(10),
        decoration:BoxDecoration(
          color:const Color(0xFFF0F6FA),
          borderRadius:BorderRadius.circular(12)),
        child:TextButton.icon(
          onPressed:()=>_editInvoiceLabor(task),
          icon:const Icon(Icons.person_add_alt,size:17),
          label:const Text('Assign mechanic to start work')));
    }
    final allocations=allocationsByLine[task['line_id']?.toString()??'']
      ?? const <Map<String,dynamic>>[];
    return Container(
      key: ValueKey('service-task-mechanics-${_identity(task)}'),
      margin:const EdgeInsets.only(top:12,bottom:4),
      padding:const EdgeInsets.fromLTRB(10,7,10,8),
      decoration:BoxDecoration(
        color:const Color(0xFFF0F6FA),
        borderRadius:BorderRadius.circular(12),
        border:Border.all(color:const Color(0xFFDCE7ED))),
      child:Column(children:[
        for(var index=0;index<mechanics.length;index++) ...[
          if(index>0) const Divider(height:16,color:Color(0xFFD0DCE4)),
          Builder(builder:(context){
            final mechanicId=mechanics[index];
            final current=_mechanicTaskStatus(task,mechanicId);
            final allocated=allocations.where((a)=>
              a['employee_id']?.toString()==mechanicId).toList();
            final hours=allocated.isEmpty
              ? (task['payroll_hours'] as num?)?.toDouble()
              : (allocated.first['hours'] as num?)?.toDouble();
            return Row(children:[
              Icon(current=='done'?Icons.check_circle:
                current=='in_progress'?Icons.timelapse:Icons.circle_outlined,
                size:19,color:current=='done'?const Color(0xFF159B6A):
                  const Color(0xFF667C8B)),
              const SizedBox(width:8),
              Expanded(child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  Text(_employeeName(mechanicId),
                    overflow:TextOverflow.ellipsis,
                    style:const TextStyle(fontSize:13.5,
                      fontWeight:FontWeight.w700)),
                  if(hours!=null)
                    Text('${hours.toStringAsFixed(1)} hrs · '
                      '${current=='done'?'Done':
                        current=='in_progress'?'In Progress':'Not Started'}',
                      style:const TextStyle(fontSize:11,
                        color:Color(0xFF64748B))),
                ])),
              if(completeTask)
                const Row(mainAxisSize:MainAxisSize.min,children:[
                  Icon(Icons.check_circle,color:Color(0xFF159B6A),size:16),
                  SizedBox(width:3),
                  Text('Done',style:TextStyle(color:Color(0xFF159B6A),
                    fontWeight:FontWeight.w700,fontSize:12)),
                ])
              else if(current=='done')
                TextButton.icon(
                  onPressed:_changingMechanicProgress.contains(
                    _mechanicTaskKey(task,mechanicId))?null:
                    ()=>_undoMechanicDone(task,mechanicId),
                  style:TextButton.styleFrom(
                    visualDensity:VisualDensity.compact,
                    padding:const EdgeInsets.symmetric(horizontal:4)),
                  icon:const Icon(Icons.undo,size:17),
                  label:const Text('Undo Done',style:TextStyle(fontSize:12)))
              else ...[
                if(current=='planned')
                  TextButton.icon(
                    onPressed:_changingMechanicProgress.contains(
                      _mechanicTaskKey(task,mechanicId))?null:
                      ()=>_changeMechanicProgress(task,mechanicId,'in_progress'),
                    style:TextButton.styleFrom(
                      visualDensity:VisualDensity.compact,
                      padding:const EdgeInsets.symmetric(horizontal:4)),
                    icon:const Icon(Icons.play_arrow,size:17),
                    label:const Text('Start',style:TextStyle(fontSize:12))),
                TextButton.icon(
                  onPressed:_changingMechanicProgress.contains(
                    _mechanicTaskKey(task,mechanicId))?null:
                    ()=>_changeMechanicProgress(task,mechanicId,'done'),
                  style:TextButton.styleFrom(
                    visualDensity:VisualDensity.compact,
                    padding:const EdgeInsets.symmetric(horizontal:4)),
                  icon:const Icon(Icons.check,size:17),
                  label:const Text('Done',style:TextStyle(fontSize:12))),
              ],
            ]);
          }),
        ],
      ]),
    );
  }

  Map<String, dynamic>? _firstCompletion(Map<String, dynamic> task) {
    final id = _identity(task);
    for (final record in completedWorkRows) {
      if (_identity(record) == id) return record;
    }
    return null;
  }

  String _completedAssignment(Map<String, dynamic> record) {
    final frozen = (record['payroll_allocations'] as List?)
      ?.whereType<Map<String, dynamic>>().toList() ?? [];
    if (frozen.isNotEmpty) {
      return frozen.map((row) {
        final hours = (row['hours'] as num?)?.toDouble() ?? 0;
        return '${_employeeName(row['employee_id']?.toString())} '
          '${hours.toStringAsFixed(1)} hrs';
      }).join(' · ');
    }
    final mechanic = _employeeName(record['completed_by']?.toString());
    return '$mechanic · Unpaid (0 hrs)';
  }

  String _laborAssignment(Map<String, dynamic> task) {
    final allocations = allocationsByLine[task['line_id'].toString()] ?? [];
    if (allocations.isNotEmpty) {
      return allocations.map((a) => "${_employeeName(a['employee_id'].toString())}: ${a['hours']} hrs").join(' · ');
    }
    final hours = (task['payroll_hours'] as num?)?.toDouble();
    if (hours == 0) {
      return "${_employeeName(task['employee_id']?.toString())} · Unpaid";
    }
    return "${_employeeName(task['employee_id']?.toString())} · ${task['payroll_hours'] ?? '—'} hrs";
  }

  Future<void> _editInvoiceLabor(Map<String, dynamic> task) async {
    if (_firstCompletion(task) != null) return;
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
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(_description(task)),
              const SizedBox(height: 8),
              Text('${notOnInvoice ? 'Original recheck' : 'Invoice book time'}: '
                '${task['source_invoice_hours'] ?? '—'} hrs. '
                'Payroll hours can be adjusted independently.',
                style: const TextStyle(
                  fontSize: 12.5, color: Color(0xFF64748B))),
              Text(notOnInvoice ? 'Not on Invoice · No customer charge.'
                : 'Invoice totals do not change.',
                style: const TextStyle(fontSize: 12.5)),
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

  List<Map<String, dynamic>> _taskCorrections(
      Map<String, dynamic> task) => earnedCorrections.where((row) =>
        row['document_id'] == task['document_id'] &&
        row['line_id'] == task['line_id']).toList();

  Future<void> _ownerCorrectEarnedHours(Map<String, dynamic> task) async {
    final completed = _firstCompletion(task);
    if (completed == null) return;
    String employeeId = '';
    final allocations = (completed['payroll_allocations'] as List?)
      ?.whereType<Map<String, dynamic>>().toList() ?? [];
    if (allocations.isNotEmpty) {
      employeeId = allocations.first['employee_id']?.toString() ?? '';
    } else {
      employeeId = completed['completed_by']?.toString() ?? '';
    }
    if (!BriskersLabFixture.employees.any((e) =>
        e['id'] == employeeId && e['role'] != 'secretary')) {
      employeeId = '';
    }
    final delta = TextEditingController();
    final reason = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      showDragHandle: true, useSafeArea: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, update) =>
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16,
            MediaQuery.viewInsetsOf(sheet).bottom + 22),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Owner correction · TEST',
                style: TextStyle(fontSize: 20,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Original completion and paid transactions remain '
                'unchanged. Add a reasoned hour adjustment to earnings.',
                style: TextStyle(fontSize: 12.5,
                  color: Color(0xFF64748B))),
              const SizedBox(height: 10),
              Text(completed['description']?.toString() ?? 'Completed labor'),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: employeeId,
                decoration: const InputDecoration(
                  labelText: 'Mechanic to adjust',
                  border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: '',
                    child: Text('Select mechanic')),
                  for (final employee in BriskersLabFixture.employees)
                    if (employee['role'] != 'secretary')
                      DropdownMenuItem(
                        value: employee['id']!,
                        child: Text(_employeeName(employee['id']))),
                ],
                onChanged: (value) =>
                  update(() => employeeId = value ?? ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: delta,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true, decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Adjustment in hours (+ or −)',
                  helperText: 'Example: +1.0 for an extra hour; '
                    '-0.5 to correct over-credit',
                  border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                minLines: 2, maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason (required)',
                  border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  final change = double.tryParse(delta.text.trim());
                  if (employeeId.isEmpty || change == null ||
                      !change.isFinite || change == 0 ||
                      reason.text.trim().length < 6) {
                    ScaffoldMessenger.of(sheet).showSnackBar(
                      const SnackBar(content: Text(
                        'Choose a mechanic, nonzero hours, and a reason')));
                    return;
                  }
                  try {
                    await store.recordOwnerEarnedHoursCorrection(
                      businessId: BriskersLabFixture.businessId,
                      jobId: BriskersLabFixture.jobId,
                      documentId: task['document_id'].toString(),
                      lineId: task['line_id'].toString(),
                      employeeId: employeeId,
                      deltaHours: change, reason: reason.text);
                    if (sheet.mounted) Navigator.pop(sheet, true);
                  } catch (error) {
                    if (sheet.mounted) {
                      ScaffoldMessenger.of(sheet)
                        .showSnackBar(SnackBar(content: Text('$error')));
                    }
                  }
                },
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('Record Owner Correction'),
              ),
            ],
          )),
        ),
      ),
    );
    delta.dispose();
    reason.dispose();
    if (saved == true) await _refresh();
  }

  // Compact card summary uses frozen credits for completed work and
  // current allocations only for tasks still in progress.
  ({String mechanics, String hours}) _compactTaskCredit(
      Map<String, dynamic> task, Map<String, dynamic>? completed) {
    final splits = completed != null
      ? (completed['payroll_allocations'] as List?)
          ?.whereType<Map<String, dynamic>>().toList() ?? []
      : allocationsByLine[task['line_id'].toString()] ?? [];
    if (splits.isNotEmpty) {
      final mechanics = splits.map((row) =>
        _employeeName(row['employee_id']?.toString())).join(' + ');
      final total = splits.fold<double>(0, (sum, row) =>
        sum + ((row['hours'] as num?)?.toDouble() ?? 0));
      return (mechanics: mechanics,
        hours: total > 0 ? '${total.toStringAsFixed(1)} hrs' : 'Unpaid');
    }
    final mechanic = completed != null
      ? completed['completed_by']?.toString()
      : task['employee_id']?.toString();
    final hours = completed != null ? 0.0
      : (task['payroll_hours'] as num?)?.toDouble();
    return (mechanics: _employeeName(mechanic),
      hours: hours == null ? '—'
        : hours == 0 ? 'Unpaid' : '${hours.toStringAsFixed(1)} hrs');
  }

  // A collapsed task is two lines high. Tapping any card expands its full
  // description/completion details; editing stays in its separate pencil.
  Widget _taskCard(Map<String, dynamic> task) {
    final record = _firstCompletion(task);
    final done = record != null || task['status'] == 'done';
    final description = record?['description']?.toString() ??
      _description(task);
    final credit = _compactTaskCredit(task, record);
    final id = _identity(task);
    final expanded = expandedTaskKeys.contains(id);
    final completedAt = record?['completed_at'];
    final stamp = completedAt is int
      ? DateFormat('MMM d, yyyy · h:mm a').format(
          DateTime.fromMillisecondsSinceEpoch(completedAt)) : '';
    final isRecheck = task['document_id'] ==
      LocalJobTasksLabStore.recheckDocumentId;
    final corrections = _taskCorrections(task);
    final splitCount = record != null
      ? (record['payroll_allocations'] as List?)?.length ?? 0
      : allocationsByLine[task['line_id'].toString()]?.length ?? 0;
    return Card(
      key: ValueKey('service-task-card-$id'),
      margin: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      elevation: 1.5,
      shadowColor: const Color(0x220C344D),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFCAD9E2), width: 1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('compact-task-$id'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() {
          if (expanded) {
            expandedTaskKeys.remove(id);
          } else {
            expandedTaskKeys.add(id);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    done ? Icons.check_circle
                      : task['status'] == 'in_progress'
                        ? Icons.timelapse : Icons.radio_button_unchecked,
                    size: 19,
                    color: done ? const Color(0xFF169D70)
                      : task['status'] == 'in_progress'
                        ? BriskersColors.jobs : const Color(0xFF718096)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(description,
                          maxLines: expanded ? null : 1,
                          overflow: expanded ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14,
                            fontWeight: FontWeight.w700, height: 1.16)),
                        const SizedBox(height: 3),
                        Row(children: [
                          Expanded(child: Text(credit.mechanics,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155)))),
                          const SizedBox(width: 6),
                          Text(credit.hours,
                            style: const TextStyle(fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF64748B))),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (done)
                    PopupMenuButton<String>(
                      tooltip: 'Completed · Owner correction',
                      child: const SizedBox(
                        width: 34, height: 34,
                        child: Icon(Icons.lock_outline, size: 19,
                          color: Color(0xFF64748B))),
                      onSelected: (action) {
                        if (action == 'correct') {
                          _ownerCorrectEarnedHours(task);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'correct',
                          child: Text('Owner correction · TEST')),
                      ],
                    )
                  else
                    IconButton(
                      tooltip: 'Edit task',
                      onPressed: () => _editTask(task),
                      icon: const Icon(Icons.edit_outlined, size: 19,
                        color: BriskersColors.jobs),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 34, height: 38)),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF64748B), size: 18),
                ],
              ),
              // Keep the whole mechanic section inside the expanded task.
              // The next service task is a separate, individually bordered card.
              if (expanded)
                _mechanicProgressControls(task,completeTask:done),
              if (!done && _mechanicsOnTask(task).length > 1 && !expanded)
                Padding(
                  padding:const EdgeInsets.only(top:4,left:28),
                  child:Text(
                    '${_mechanicsOnTask(task).where((mechanic)=>
                      _mechanicTaskStatus(task,mechanic)=='done').length}'
                    ' of ${_mechanicsOnTask(task).length} mechanics Done'
                    ' · Tap to manage',
                    style:const TextStyle(fontSize:11.5,
                      color:Color(0xFF64748B)))),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 9, 4, 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isRecheck)
                        const Text('Additional work · Not on Invoice',
                          style: TextStyle(fontSize: 12,
                            color: Color(0xFF526273))),
                      if (splitCount > 1)
                        Text(record != null
                          ? _completedAssignment(record)
                          : _laborAssignment(task),
                          style: const TextStyle(fontSize: 12.5,
                            color: Color(0xFF526273))),
                      if(isRecheck && !done &&
                          ((task['payroll_hours'] as num?)?.toDouble() ?? 0) == 0)
                        TextButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (dialog) => AlertDialog(
                                title: const Text('Move to General Tasks?'),
                                content: const Text(
                                  'This unpaid, unfinished internal task '
                                  'will no longer appear under Job J-24.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialog,false),
                                    child: const Text('Cancel')),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(dialog,true),
                                    child: const Text('Move')),
                                ],
                              ),
                            );
                            if(confirm != true) return;
                            try {
                              await store.moveUnpaidRecheckToShop(
                                businessId: BriskersLabFixture.businessId,
                                jobId: BriskersLabFixture.jobId,
                                lineId: task['line_id'].toString());
                              await _refresh();
                            } catch (error) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$error')));
                              }
                            }
                          },
                          icon: const Icon(Icons.drive_file_move_outline),
                          label: const Text('Move to General Tasks')),
                      Text(done
                        ? stamp.isEmpty
                          ? 'Done'
                          : 'Done · $stamp'
                        : task['status'] == 'in_progress'
                          ? 'In Progress'
                          : 'Not Started',
                        style: const TextStyle(fontSize: 12,
                          color: Color(0xFF64748B))),
                      if (corrections.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        const Text('Owner corrections:',
                          style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w700)),
                        for (final correction in corrections)
                          Text(
                            '${(correction['delta_hours'] as num).toDouble() > 0 ? '+' : ''}'
                            '${correction['delta_hours']} hrs · '
                            '${_employeeName(correction['employee_id']?.toString())} · '
                            '${correction['reason']}',
                            style: const TextStyle(fontSize: 12,
                              color: Color(0xFF526273))),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editTask(Map<String, dynamic> task) async {
    if (_firstCompletion(task) != null) return;
    final description = TextEditingController(text: _description(task));
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16,
            // Reserve physical system-navigation space below Save.
            MediaQuery.viewInsetsOf(sheetContext).bottom +
            MediaQuery.viewPaddingOf(sheetContext).bottom + 30),
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
    );
    description.dispose();
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

  Future<void> _assignLeadMechanic() async {
    String selected = leadMechanicId ?? '';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(18, 12, 18,
            MediaQuery.viewInsetsOf(sheet).bottom +
            MediaQuery.viewPaddingOf(sheet).bottom + 30),
          child: SingleChildScrollView(child: Column(
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
          )),
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
    final pending = active.where((task) =>
      _firstCompletion(task) == null && task['status'] != 'done').toList();
    final unfinished = pending.length;
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
                  Text('Job J-24 · $unfinished active tasks to finish. '
                    'Previously completed work will not be changed.'),
                  const SizedBox(height: 10),
                  for (final task in pending)
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
                    'in the completed work list. Payroll Preview updates '
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
              const Color(0xFF15988F), () => _labNotice('Work Performed'),
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
                  onTap: () => _navigate(12),
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

  Future<void> _addRecheckWork() async {
    final description = TextEditingController();
    final hours = TextEditingController();
    String assignee = leadMechanicId ?? '';
    bool paid = true;
    final added = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      showDragHandle: true, useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheet).bottom),
          child: SafeArea(
            top: false,
            child: SizedBox(
              // Reserve space above Android's gesture/navigation bar.
              // The form scrolls while the primary action stays visible.
              height: (MediaQuery.sizeOf(sheet).height -
                MediaQuery.viewInsetsOf(sheet).bottom) * 0.82,
              child: Column(children: [
                Expanded(child: SingleChildScrollView(
                  key: const Key('recheck-form-scroll'),
                  keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pay mechanic for this task'),
                subtitle: const Text('Turn off to record unpaid recheck work'),
                value: paid,
                onChanged: (value) => update(() => paid = value),
              ),
              if (paid)
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
                      const SizedBox(height: 12),
                    ],
                  ))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('recheck-add-sticky-button'),
                onPressed: () async {
                  final qty = paid ? double.tryParse(hours.text.trim()) : 0.0;
                  if (description.text.trim().isEmpty ||
                      qty == null || !qty.isFinite ||
                      (paid && qty <= 0)) {
                    ScaffoldMessenger.of(sheet).showSnackBar(
                      const SnackBar(content: Text(
                        'Enter description and positive hours if paid')));
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
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    description.dispose();
    hours.dispose();
    if (added == true) await _refresh();
  }

  Future<void> _addInternalShopTask() async {
    final description = TextEditingController();
    String assigned = '';
    String category = 'General';
    DateTime? dueDate;
    final created = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true, isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheet).bottom),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('New General Task',
                      style: TextStyle(fontSize: 20,
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('Internal work · No customer, job, invoice or '
                      'automatic payroll charge',
                      style: TextStyle(color: Color(0xFF64748B))),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Task description',
                        border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: assigned,
                      decoration: const InputDecoration(
                        labelText: 'Assign employee',
                        border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(
                          value: '', child: Text('Unassigned')),
                        for (final e in BriskersLabFixture.employees)
                          DropdownMenuItem(
                            value: e['id']!,
                            child: Text(_employeeName(e['id'])),
                          ),
                      ],
                      onChanged: (v) => update(() => assigned = v ?? ''),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(
                        labelText: 'Category', border: OutlineInputBorder()),
                      items: [
                        for (final name in ['General','Cleaning','Inventory',
                          'Office','Maintenance','Yard','Errands'])
                          DropdownMenuItem(value:name,child:Text(name)),
                      ],
                      onChanged: (v) => update(() => category = v ?? 'General'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context:sheet, initialDate:dueDate ?? DateTime.now(),
                          firstDate:DateTime(2020),lastDate:DateTime(2100));
                        if(selected!=null) update(()=>dueDate=selected);
                      },
                      icon:const Icon(Icons.calendar_month_outlined),
                      label:Text(dueDate==null?'Due date (optional)':
                        'Due '+DateFormat('MMM d, yyyy').format(dueDate!)),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        if (description.text.trim().isEmpty) return;
                        try {
                          await store.addShopTask(
                            businessId: BriskersLabFixture.businessId,
                            description: description.text,
                            employeeId: assigned,
                            category: category, dueDate: dueDate);
                          if (sheet.mounted) Navigator.pop(sheet, true);
                        } catch (error) {
                          if (sheet.mounted) {
                            ScaffoldMessenger.of(sheet).showSnackBar(
                              SnackBar(content: Text('$error')));
                          }
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Save General Task'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    description.dispose();
    if (created == true) await _refresh();
  }

  Widget _tasksWorkspace() => TasksWorkspaceLab(
    key: const Key('approved-tasks-workspace'),
    serviceTasks: tasks,
    generalTasks: shopTasks,
    allocationsByLine: allocationsByLine,
    employeeName: _employeeName,
    serviceTaskCard: _taskCard,
    onAddService: _addRecheckWork,
    onAddGeneral: _addInternalShopTask,
    onGeneralStatus: (id, status) async {
      await store.setShopTaskStatus(
        businessId: BriskersLabFixture.businessId,
        taskId: id, status: status);
      await _refresh();
    },
    onOpenJob: () => _openVehicleJob(0),
  );

  Widget _shopTasksPage() {
    final active = shopTasks.where((task) => task['status'] != 'done').toList();
    final completed = shopTasks.where((task) => task['status'] == 'done').toList();
    Widget render(Map<String,dynamic> task) {
      final status = task['status']?.toString() ?? 'planned';
      final id = task['id'] as int;
      return Card(
        key: ValueKey('shop-task-$id'),
        margin: const EdgeInsets.fromLTRB(12, 3, 12, 3),
        child: ListTile(
          leading: Icon(status=='done' ? Icons.check_circle :
            status=='in_progress' ? Icons.timelapse : Icons.circle_outlined,
            color: status=='done' ? const Color(0xFF117C56) :
              BriskersColors.jobs),
          title: Text(task['description']?.toString()??'',
            style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(_employeeName(task['employee_id']?.toString())+
            ' · '+(status=='done' ? 'Done' :
              status=='in_progress' ? 'In Progress' : 'Not Started')),
          trailing: PopupMenuButton<String>(
            tooltip: 'Change General Task progress',
            onSelected: (value) async {
              await store.setShopTaskStatus(
                businessId: BriskersLabFixture.businessId,
                taskId: id, status: value);
              await _refresh();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value:'planned',child:Text('Not Started')),
              PopupMenuItem(value:'in_progress',child:Text('In Progress')),
              PopupMenuItem(value:'done',child:Text('Done')),
            ],
          ),
        ),
      );
    }
    return ListView(children: [
      _sectionHeader('General Tasks',
        subtitle: 'Internal work · Not attached to customer jobs'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: FilledButton.icon(
          onPressed: _addInternalShopTask,
          icon: const Icon(Icons.add),
          label: const Text('New General Task')),
      ),
      const SizedBox(height: 14),
      for (final task in active) render(task),
      if (active.isEmpty) const ListTile(title: Text('No active shop tasks')),
      ExpansionTile(
        title: Text('Done · '+completed.length.toString()),
        initiallyExpanded: false,
        children: [for (final task in completed) render(task)]),
    ]);
  }

  Widget _taskList() {
    final original = tasks.where((task) =>
      task['source_missing'] != 1 &&
      task['document_id'] == BriskersLabFixture.invoiceId).toList();
    final additional = tasks.where((task) =>
      task['source_missing'] != 1 &&
      task['document_id'] ==
        LocalJobTasksLabStore.recheckDocumentId).toList();
    final active = [...original, ...additional].where((task) =>
      _firstCompletion(task) == null && task['status'] != 'done').toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        TextButton.icon(
          onPressed: () => _openVehicleJob(0),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to Job J-24'),
        ),
        _sectionHeader('Job J-24 tasks & completed work',
          subtitle: 'One entry per task · Original work stays preserved'),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(children: [
            const Text('Job status', style: TextStyle(
              fontWeight: FontWeight.w700)),
            const Spacer(),
            _jobStatusControl(),
          ]),
        ),
        if (jobStatusCode != 'completed')
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: OutlinedButton.icon(
              onPressed: _addRecheckWork,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add job recheck · Not on Invoice'),
            ),
          ),
        if (active.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: OutlinedButton.icon(
              onPressed: _confirmCompleteAllTasks,
              icon: const Icon(Icons.done_all),
              label: const Text('Mark all active tasks Done'),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 5),
          child: Text('Original work · Invoice #6342',
            style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.w800))),
        if (original.isEmpty)
          const ListTile(title: Text('No invoice labor tasks')),
        ...original.map(_taskCard),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 5),
          child: Text('Additional job work / rechecks',
            style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.w800))),
        if (additional.isEmpty)
          const ListTile(
            title: Text('No additional work recorded'),
            subtitle: Text('Reopen the job and add a new task if needed.')),
        ...additional.map(_taskCard),
      ],
    );
  }

  // ignore: unused_element
  String _labMoney(int cents) => NumberFormat.simpleCurrency(
    locale: 'en_US').format(cents / 100);

  Future<void> _setTestPayrollRate(String employeeId) async {
    final current = testHourlyRates[employeeId];
    final controller = TextEditingController(
      text: current == null ? '' : (current / 100).toStringAsFixed(2));
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Test hourly rate · ${_employeeName(employeeId)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Local test calculation only. '
              'This will not change the real employee pay rate.'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true),
              decoration: const InputDecoration(
                prefixText: r'$ ',
                labelText: 'Hourly rate',
                border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final dollars = double.tryParse(controller.text.trim());
              if (dollars == null || !dollars.isFinite ||
                  dollars < 0 || dollars > 10000) {
                ScaffoldMessenger.of(dialog).showSnackBar(
                  const SnackBar(content: Text('Enter a valid hourly rate')));
                return;
              }
              try {
                await store.setPayrollRate(
                  businessId: BriskersLabFixture.businessId,
                  employeeId: employeeId,
                  centsPerHour: (dollars * 100).round(),
                );
                if (dialog.mounted) Navigator.pop(dialog, true);
              } catch (error) {
                if (dialog.mounted) {
                  ScaffoldMessenger.of(dialog).showSnackBar(
                    SnackBar(content: Text('$error')));
                }
              }
            },
            child: const Text('Save test rate')),
        ],
      ),
    );
    controller.dispose();
    if (saved == true) await _refresh();
  }

  Future<void> _recordTestPayrollPayment(String employeeId) async {
    final amount = TextEditingController();
    final notes = TextEditingController();
    String kind = 'pay';
    String method = 'cash';
    DateTime paidAt = DateTime.now();
    final saved = await showModalBottomSheet<bool>(
      context: context, showDragHandle: true, isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16,
            MediaQuery.viewInsetsOf(sheet).bottom + 20),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Record TEST payment · ${_employeeName(employeeId)}',
                style: const TextStyle(fontSize: 19,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('SIMULATION ONLY · No real payroll or cash posted.',
                style: TextStyle(
                  fontSize: 12, color: BriskersColors.expenses)),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
                decoration: const InputDecoration(
                  prefixText: r'$ ',
                  labelText: 'Amount paid',
                  border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(
                  labelText: 'Payment type',
                  border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'pay',
                    child: Text('Partial / full payment')),
                  DropdownMenuItem(value: 'advance',
                    child: Text('Advance / unfinished work')),
                ],
                onChanged: (v) => update(() => kind = v ?? 'pay')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(
                  labelText: 'Payment method',
                  border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'check', child: Text('Check')),
                  DropdownMenuItem(value: 'zelle', child: Text('Zelle')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => update(() => method = v ?? 'cash')),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                onPressed: () async {
                  final chosen = await showDatePicker(
                    context: sheet, initialDate: paidAt,
                    firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (chosen != null) {
                    update(() => paidAt = chosen);
                  }
                },
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text('Payment date: '
                  "${DateFormat('MMM d, yyyy').format(paidAt)}"),
              ),
              const SizedBox(height: 9),
              TextField(
                controller: notes,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder())),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  final dollars = double.tryParse(amount.text.trim());
                  if (dollars == null || !dollars.isFinite ||
                      dollars <= 0 || dollars > 1000000) {
                    ScaffoldMessenger.of(sheet).showSnackBar(
                      const SnackBar(content: Text('Enter a positive amount')));
                    return;
                  }
                  try {
                    await store.recordLabPayrollPayment(
                      businessId: BriskersLabFixture.businessId,
                      employeeId: employeeId,
                      cents: (dollars * 100).round(),
                      kind: kind, method: method, note: notes.text,
                      paidAt: paidAt,
                    );
                    if (sheet.mounted) Navigator.pop(sheet, true);
                  } catch (error) {
                    if (sheet.mounted) {
                      ScaffoldMessenger.of(sheet).showSnackBar(
                        SnackBar(content: Text('$error')));
                    }
                  }
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save TEST payment'),
              ),
            ],
          )),
        ),
      ),
    );
    amount.dispose();
    notes.dispose();
    if (saved == true) await _refresh();
  }

  Future<void> _openEmployeeProfile(String employeeId, [DateTime? week]) async {
    final employee = BriskersLabFixture.employees.firstWhere(
      (value) => value['id'] == employeeId,
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeePayrollProfileLab(
          employeeId: employeeId,
          name: fullNames[employeeId] ?? employee['name']!,
          nickname: nicknames[employeeId] ?? employee['nickname'] ?? employee['name']!,
          role: employee['role']!,
          tasks: tasks,
          generalTasks: shopTasks,
          allocationsByLine: allocationsByLine,
          payments: testPayrollPayments,
          rateCents: testHourlyRates[employeeId],
          initialTab: 0,
          initialWeek: week,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _reviewEmployeeWeek(String employeeId, DateTime week) =>
    _openEmployeeProfile(employeeId, week);

  Widget _payrollPage() => LabPayrollOverviewScreen(
    employees: BriskersLabFixture.employees,
    nicknames: nicknames,
    rates: testHourlyRates,
    payments: testPayrollPayments,
    tasks: tasks,
    allocationsByLine: allocationsByLine,
    onOpenProfile: (id, week) => _openEmployeeProfile(id, week),
    onReviewWeek: _reviewEmployeeWeek,
  );

  Widget _settingsPage() => ListView(
    children: [
      _sectionHeader('Test Settings'),
      ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: const Text('Edit employee names'),
        subtitle: const Text('Full names and preferred display names'),
        onTap: _editEmployeeNames,
      ),
      ExpansionTile(
        leading: const Icon(Icons.payments_outlined),
        title: const Text('TEST payroll tools'),
        subtitle: const Text('Rates and simulated disbursements'),
        children: [
          for (final employee in BriskersLabFixture.employees)
            ListTile(
              title: Text(_employeeName(employee['id']!)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(
                  onPressed: () => _setTestPayrollRate(employee['id']!),
                  child: const Text('Rate')),
                TextButton(
                  onPressed: () => _recordTestPayrollPayment(employee['id']!),
                  child: const Text('Payment')),
              ]),
            ),
        ],
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
          _homeTile('Tasks & work history', '${tasks.length} Labor tasks',
            Icons.rule_outlined, BriskersColors.jobs,
            () => _navigate(3)),
          _homeTile('Payroll', 'Test-only earnings and payments',
            Icons.account_balance_wallet_outlined, BriskersColors.invoices,
            () => _navigate(5)),
        ),
        tileRow(
          _homeTile('Settings', 'Test app preferences',
            Icons.settings_outlined, BriskersColors.settings,
            () => _navigate(6)),
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

  /// Recreates the real invoice Items arrangement for phone layout QA:
  /// Item | Qty | Amount, with a mechanic/hour edit control by each labor
  /// heading. Price data and source invoice editing are never introduced.
  String _invoiceMechanicSummary(Map<String, dynamic> task) {
    final saved = _firstCompletion(task);
    if (saved != null) {
      final frozen = (saved['payroll_allocations'] as List?)
        ?.whereType<Map<String, dynamic>>().toList() ?? [];
      if (frozen.isEmpty) return _completedAssignment(saved);
      return frozen.map((row) {
        final hours = (row['hours'] as num?)?.toDouble() ?? 0;
        return '${_employeeName(row['employee_id']?.toString())} '
          '${hours.toStringAsFixed(1)}h';
      }).join(' · ');
    }
    final rows = allocationsByLine[task['line_id'].toString()] ?? const [];
    if (rows.isNotEmpty) {
      return rows.map((a) {
        final hours = (a['hours'] as num?)?.toDouble() ?? 0;
        return '${_employeeName(a['employee_id']?.toString())} '
          '${hours.toStringAsFixed(1)}h';
      }).join(' · ');
    }
    final hours = (task['payroll_hours'] as num?)?.toDouble();
    return '${_employeeName(task['employee_id']?.toString())} '
      '${hours == null ? '—' : hours.toStringAsFixed(1)}h';
  }

  Widget _testInvoiceLaborRow(Map<String, dynamic> task) {
    final locked = _firstCompletion(task) != null;
    final book = (task['source_invoice_hours'] as num?)?.toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE1E6E9)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('Labor', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800,
                color: Color(0xFF0D1528))),
              const SizedBox(width: 8),
              Expanded(child: Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  key: ValueKey('labor-hours-edit-${task['line_id']}'),
                  onTap: locked ? null : () => _editInvoiceLabor(task),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 5, 0, 5),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.engineering_outlined, size: 17,
                        color: BriskersColors.jobs),
                      const SizedBox(width: 4),
                      Flexible(child: Text(_invoiceMechanicSummary(task),
                        maxLines: 2,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700,
                          color: BriskersColors.jobs))),
                      const SizedBox(width: 5),
                      Icon(locked ? Icons.lock_outline : Icons.edit_outlined,
                        size: 18, color: locked
                          ? const Color(0xFF64748B) : BriskersColors.jobs),
                    ]),
                  ),
                ),
              )),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(
                _description(task),
                style: const TextStyle(
                  fontSize: 13.5, height: 1.25,
                  color: Color(0xFF405064)))),
              SizedBox(width: 58, child: Text(
                book == null ? '—' : book.toStringAsFixed(1),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15.5, color: Color(0xFF182239)))),
              const SizedBox(width: 92, child: Text('—',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15.5, color: Color(0xFF182239)))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _invoiceRedactedAmount(String label, {bool bold = false}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Text(label, style: TextStyle(
          fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
        const Spacer(),
        Text('—', style: TextStyle(
          fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
      ]),
    );

  Widget _testInvoicePage() {
    final lines = tasks.where((task) =>
      task['source_missing'] != 1 &&
      task['document_id'] == BriskersLabFixture.invoiceId).toList();
    const tabs = ['Items', 'Payment', 'Notes', 'Expenses'];
    return ListView(
      children: [
        _sectionHeader('Invoice #6342',
          subtitle: 'Sanitized invoice layout · Offline Tasks TEST'),
        const Card(
          margin: EdgeInsets.fromLTRB(10, 0, 10, 6),
          child: ListTile(
            leading: Icon(Icons.receipt_long_outlined,
              color: BriskersColors.invoices),
            title: Text('Richard Goff',
              style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('2012 Hyundai Equus · Job J-24'),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: const BoxDecoration(color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE4E9EB)))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < tabs.length; i++)
                TextButton(
                  onPressed: () => setState(() => invoiceTestTab = i),
                  style: TextButton.styleFrom(
                    foregroundColor: i == invoiceTestTab
                      ? BriskersColors.invoices : const Color(0xFF64748B),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17, vertical: 11)),
                  child: Text(tabs[i], style: TextStyle(
                    fontWeight: i == invoiceTestTab
                      ? FontWeight.w800 : FontWeight.w500)),
                ),
            ]),
          ),
        ),
        if (invoiceTestTab == 0) ...[
          Container(
            color: const Color(0xFFF2F6F7),
            padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 9),
            child: const Row(children: [
              Expanded(child: Text('Item', style: TextStyle(
                color: Color(0xFF405064),
                fontWeight: FontWeight.w500))),
              SizedBox(width: 58, child: Text('Qty',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF405064),
                  fontWeight: FontWeight.w500))),
              SizedBox(width: 92, child: Text('Amount',
                textAlign: TextAlign.right,
                style: TextStyle(color: Color(0xFF405064),
                  fontWeight: FontWeight.w500))),
            ]),
          ),
          for (final task in lines) _testInvoiceLaborRow(task),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 8),
            child: Column(children: [
              _invoiceRedactedAmount('Subtotal'),
              _invoiceRedactedAmount('Taxes'),
              const Divider(height: 16),
              _invoiceRedactedAmount('TOTAL', bold: true),
              _invoiceRedactedAmount('Amount Paid'),
              _invoiceRedactedAmount('Balance Due', bold: true),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Text(
              'Financial amounts are intentionally redacted (—), not zero. '
              'Tap the small pencil beside a labor item to edit ONLY the '
              'test mechanic hours and assignments. The invoice Qty '
              'stays at billed book time. No live invoice is changed.',
              style: TextStyle(fontSize: 12,
                color: Color(0xFF667085))),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              '${tabs[invoiceTestTab]} data is not copied into '
              'this isolated test. Return to Items to test the '
              'invoice labor layout.',
              style: const TextStyle(color: Color(0xFF64748B))),
          ),
      ],
    );
  }

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
      case 3: return _tasksWorkspace();
      case 12: return _taskList();
      case 4: return _shopTasksPage();
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
