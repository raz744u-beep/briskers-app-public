import 'compact_task_card.dart';
import '../../core/work_status_colors.dart';
// ignore_for_file: curly_braces_in_flow_control_structures, prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/service_task_order.dart';
import '../../services/job_task_summary.dart';
import '../../widgets/job_list_approved_card.dart';

/// Tasks workspace. Only customer/job-linked records appear
/// under Service Tasks. General Tasks can reference a job without billing it.
class TasksWorkspace extends StatefulWidget {
  const TasksWorkspace({
    super.key,
    required this.serviceTasks,
    required this.generalTasks,
    required this.allocationsByLine,
    required this.employeeName,
    required this.employeeIds,
    required this.serviceTaskCard,
    required this.onAddGeneral,
    required this.onGeneralStatus,
    required this.onOpenJob,
    required this.onEmployeeTap,
    this.initialGeneral = false,
    this.scopedJob,
    this.onAddService,
    this.onAddRecheck,
    this.onRecoverHistory,
    this.onOpenInvoice,
    this.onEditService,
    this.onEditGeneral,
    this.onMarkDone,
  });

  final List<Map<String, dynamic>> serviceTasks;
  final List<Map<String, dynamic>> generalTasks;
  final Map<String, List<Map<String, dynamic>>> allocationsByLine;
  final String Function(String?) employeeName;
  final List<String> employeeIds;
  final Widget Function(Map<String, dynamic>) serviceTaskCard;
  final VoidCallback onAddGeneral;
  final ValueChanged<Map<String, dynamic>>? onEditService,
      onEditGeneral,
      onMarkDone;
  final VoidCallback? onAddService;
  final ValueChanged<String>? onAddRecheck;
  final VoidCallback? onRecoverHistory;
  final Future<void> Function(int taskId, String status) onGeneralStatus;
  final ValueChanged<String> onOpenJob;
  final ValueChanged<String>? onOpenInvoice;
  final ValueChanged<String> onEmployeeTap;
  final bool initialGeneral;
  final String? scopedJob;

  @override
  State<TasksWorkspace> createState() => _TasksWorkspaceState();
}

class _TasksWorkspaceState extends State<TasksWorkspace> {
  late bool _general;
  final _search = TextEditingController();
  String _employee = '';
  String _status = 'Active';
  String _kind = 'All Types';
  String _category = 'All Categories';
  String _job = 'All Jobs';
  String _date = 'Any';
  String _servicePeriod = 'Any time';
  String _sort = 'Newest First';
  final Set<String> _expandedJobs = <String>{};

  @override
  void initState() {
    super.initState();
    _general = widget.initialGeneral;
    _search.addListener(_onSearch);
  }

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  String _statusName(Object? v) {
    switch (v?.toString()) {
      case 'in_progress':
        return 'In Progress';
      case 'done':
        return 'Done';
      default:
        return 'Not Started';
    }
  }

  bool _matchesStatus(Map<String, dynamic> row) {
    final status = _statusName(row['status']);
    // Historical invoice labor is visible under All / Paid / Done,
    // but never masquerades as a new active or payable task.
    final historical = row['archived_labor'] == 1;
    if (historical && (_status == 'Active' || _status == 'Unpaid'))
      return false;
    if (_status == 'Unpaid') {
      return status == 'Done' && (row['remaining_minutes'] as int? ?? 0) > 0;
    }
    if (_status == 'Paid') {
      return status == 'Done' && row['paid'] == 1;
    }
    return _status == 'All' ||
        (_status == 'Active' && status != 'Done') ||
        status == _status;
  }

  bool _matchesEmployee(Map<String, dynamic> row, {required bool general}) {
    if (_employee.isEmpty) return true;
    if (general) return row['employee_id']?.toString() == _employee;
    final line = row['line_id']?.toString() ?? '';
    final allocations = widget.allocationsByLine[line] ?? const [];
    if (allocations.isNotEmpty) {
      return allocations.any((a) => a['employee_id']?.toString() == _employee);
    }
    return row['employee_id']?.toString() == _employee;
  }

  bool _matchesDate(Map<String, dynamic> row) {
    if (_date == 'Any') return true;
    final raw = row['due_at'];
    if (raw is! int) return false;
    final due = DateTime.fromMillisecondsSinceEpoch(raw);
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final date = DateTime(due.year, due.month, due.day);
    if (_date == 'Today') return date == day;
    if (_date == 'This Week') {
      final monday = day.subtract(Duration(days: day.weekday - 1));
      return !date.isBefore(monday) &&
          date.isBefore(monday.add(const Duration(days: 7)));
    }
    if (_date == 'Overdue') return date.isBefore(day);
    return true;
  }

  // Service periods use actual saved Job/invoice/completion dates—not
  // list position or invoice number. Unknown dates stay visible only when
  // the Owner chooses All time; this prevents fabricated recent activity.
  bool _matchesServicePeriod(Map<String, dynamic> row) {
    if (_servicePeriod == 'Any time') return true;
    final isDone = _statusName(row['status']) == 'Done';
    final completed = isDone
        ? ServiceTaskOrder.timestamp(row['completed_date'])
        : 0;
    final timestamp = completed > 0
        ? completed
        : ServiceTaskOrder.timestamp(
            row['invoice_date'] ??
                row['invoice_created_at'] ??
                row['job_created_at'] ??
                row['job_document_date'],
          );
    if (timestamp <= 0) return false;
    final event = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final date = DateTime(event.year, event.month, event.day);
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final weekStart = day.subtract(Duration(days: day.weekday - 1));
    switch (_servicePeriod) {
      case 'This week':
        return !date.isBefore(weekStart) &&
            date.isBefore(weekStart.add(const Duration(days: 7)));
      case 'Last week':
        return !date.isBefore(weekStart.subtract(const Duration(days: 7))) &&
            date.isBefore(weekStart);
      case 'Last 7 days':
        return !date.isBefore(day.subtract(const Duration(days: 6))) &&
            !date.isAfter(day);
      case 'Last 30 days':
        return !date.isBefore(day.subtract(const Duration(days: 29))) &&
            !date.isAfter(day);
      case 'Last 90 days':
        return !date.isBefore(day.subtract(const Duration(days: 89))) &&
            !date.isAfter(day);
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _service => _serviceRows();

  List<Map<String, dynamic>> _serviceRows({bool includeCompleted = false}) {
    final q = _search.text.toLowerCase().trim();
    final rows = widget.serviceTasks.where((task) {
      if (widget.scopedJob != null && task['job_id'] != widget.scopedJob)
        return false;
      final desc =
          (task['custom_description'] ?? task['source_description'] ?? '')
              .toString()
              .toLowerCase();
      // Task-first Job work and rechecks both lack an invoice line. The
      // saved source kind distinguishes them; absence of an invoice alone
      // must not relabel ordinary Job work as a recheck.
      final sourceKind = task['source_kind']?.toString();
      final isInvoice =
          sourceKind == 'invoice' ||
          (sourceKind == null && task['document_id'] != null);
      if (_kind == 'Invoice Labor' && !isInvoice) return false;
      if (_kind == 'Rechecks' && sourceKind != 'recheck') return false;
      if (_job != 'All Jobs' && task['job_id']?.toString() != _job)
        return false;
      return task['source_missing'] != 1 &&
          (_matchesStatus(task) ||
              (includeCompleted &&
                  _status == 'Active' &&
                  task['status'] == 'done' &&
                  task['archived_labor'] != 1)) &&
          _matchesEmployee(task, general: false) &&
          _matchesServicePeriod(task) &&
          (q.isEmpty ||
              desc.contains(q) ||
              (task['job_number']?.toString().toLowerCase().contains(q) ??
                  false) ||
              widget
                  .employeeName(task['employee_id']?.toString())
                  .toLowerCase()
                  .contains(q));
    }).toList();
    rows.sort(
      (a, b) =>
          ServiceTaskOrder.compareLines(a, b, newest: _sort != 'Oldest First'),
    );
    return rows;
  }

  List<Map<String, dynamic>> get _internal {
    final q = _search.text.toLowerCase().trim();
    final rows = widget.generalTasks.where((task) {
      if (widget.scopedJob != null && task['job_id'] != widget.scopedJob)
        return false;
      final description = task['description']?.toString().toLowerCase() ?? '';
      return (_job == 'All Jobs' || task['job_id'] == _job) &&
          _matchesStatus(task) &&
          _matchesEmployee(task, general: true) &&
          (_category == 'All Categories' ||
              task['category']?.toString() == _category) &&
          _matchesDate(task) &&
          (q.isEmpty ||
              description.contains(q) ||
              widget
                  .employeeName(task['employee_id']?.toString())
                  .toLowerCase()
                  .contains(q));
    }).toList();
    rows.sort((a, b) {
      if (_sort == 'Due Date') {
        final left = a['due_at'] as int? ?? 9223372036854775807;
        final right = b['due_at'] as int? ?? 9223372036854775807;
        return left.compareTo(right);
      }
      final d = ((b['id'] as int?) ?? 0).compareTo((a['id'] as int?) ?? 0);
      return _sort == 'Oldest First' ? -d : d;
    });
    return rows;
  }

  List<String> get _employeeChoices => [
    'All Employees',
    for (final id in widget.employeeIds) _employeeLabel(id),
  ];

  String _employeeLabel(String id) {
    final name = widget.employeeName(id);
    final matching = widget.employeeIds.where(
      (candidate) => widget.employeeName(candidate) == name,
    );
    return matching.length == 1 ? name : '$name · $id';
  }

  String _employeeIdForName(String name) {
    if (name == 'All Employees') return '';
    for (final id in widget.employeeIds) {
      if (_employeeLabel(id) == name) return id;
    }
    return '';
  }

  Future<void> _filters() async {
    var employee = _employee;
    var status = _status, type = _kind, category = _category;
    var job = _job, date = _date, sort = _sort, period = _servicePeriod;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor:Colors.white,
      builder: (sheet) => StatefulBuilder(
        builder: (context, refresh) {
          Widget dropdown(
            String name,
            String value,
            List<String> values,
            void Function(String) update,
          ) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DropdownButtonFormField<String>(
              key: ValueKey('$name:$value'),
              initialValue: value,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                labelText: name,
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF1F5F4),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                for (final choice in values)
                  DropdownMenuItem(
                    value: choice,
                    child: Text(
                      name == 'Job' && choice != 'All Jobs'
                          ? _jobLabel(choice)
                          : choice,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) refresh(() => update(v));
              },
            ),
          );
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                MediaQuery.viewInsetsOf(context).bottom + 8,
              ),
              child: SizedBox(
                height:
                    (MediaQuery.sizeOf(context).height * .82 -
                            MediaQuery.viewInsetsOf(context).bottom)
                        .clamp(120.0, 900.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Task Filters',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => refresh(() {
                                    employee = '';
                                    status = 'Active';
                                    type = 'All Types';
                                    category = 'All Categories';
                                    job = 'All Jobs';
                                    date = 'Any';
                                    sort = 'Newest First';
                                    period = 'Any time';
                                  }),
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                            dropdown(
                              'Employee',
                              employee.isEmpty
                                  ? 'All Employees'
                                  : _employeeLabel(employee),
                              _employeeChoices,
                              (v) => employee = _employeeIdForName(v),
                            ),
                            if (!_general) ...[
                              if (widget.scopedJob == null)
                                dropdown('Job', job, [
                                  'All Jobs',
                                  for (final id
                                      in widget.serviceTasks
                                          .map(
                                            (t) =>
                                                t['job_id']?.toString() ?? '',
                                          )
                                          .where((e) => e.isNotEmpty)
                                          .toSet())
                                    id,
                                ], (v) => job = v),
                              dropdown('Task Type', type, [
                                'All Types',
                                'Invoice Labor',
                                'Rechecks',
                              ], (v) => type = v),
                              dropdown('Period', period, [
                                'Any time',
                                'This week',
                                'Last week',
                                'Last 7 days',
                                'Last 30 days',
                                'Last 90 days',
                              ], (v) => period = v),
                            ] else ...[
                              dropdown('Category', category, [
                                'All Categories',
                                'General',
                                'Cleaning',
                                'Inventory',
                                'Office',
                                'Maintenance',
                                'Yard',
                                'Errands',
                              ], (v) => category = v),
                              dropdown('Due Date', date, [
                                'Any',
                                'Today',
                                'This Week',
                                'Overdue',
                              ], (v) => date = v),
                            ],
                            dropdown('Status', status, [
                              'Active',
                              'Unpaid',
                              'Paid',
                              'All',
                              'Not Started',
                              'In Progress',
                              'Done',
                            ], (v) => status = v),
                            dropdown(
                              'Sort By',
                              sort,
                              ['Newest First', 'Oldest First', 'Due Date']
                                  .where((s) => _general || s != 'Due Date')
                                  .toList(),
                              (v) => sort = v,
                            ),
                            if (widget.onRecoverHistory != null) ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  widget.onRecoverHistory!();
                                },
                                icon: const Icon(Icons.history),
                                label: const Text(
                                  'Recover missing historical invoice tasks',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: BriskersColors.jobs,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () {
                        setState(() {
                          _employee = employee;
                          _status = status;
                          _kind = type;
                          _category = category;
                          _job = job;
                          _date = date;
                          _sort = sort;
                          _servicePeriod = period;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('Apply Filters'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _serviceView() {
    final rows = _service;
    final byJob = <String, List<Map<String, dynamic>>>{};
    for (final task in rows) {
      final id = task['job_id']?.toString() ?? 'Unlinked Job';
      byJob.putIfAbsent(id, () => []).add(task);
    }
    final entries = byJob.entries.toList()
      ..sort(
        (a, b) => ServiceTaskOrder.compareJobs(
          a.value.first,
          b.value.first,
          newest: _sort != 'Oldest First',
        ),
      );
    return ListView(
      key: const Key('service-tasks-list'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tasks · ' + rows.length.toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            if (widget.scopedJob == null && widget.onAddService != null)
              TextButton.icon(
                onPressed: widget.onAddService,
                icon: const Icon(Icons.add),
                label: const Text('New Task'),
              ),
          ],
        ),

        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.serviceTasks.isEmpty
                      ? 'No service tasks are available in this view. This does not mean invoice labor or payment history was deleted.'
                      : 'No service tasks match these filters. Your saved work may be completed, paid, or historical.',
                ),
                if (_status != 'All' && widget.serviceTasks.isNotEmpty)
                  TextButton.icon(
                    key: const Key('show-all-service-task-statuses'),
                    onPressed: () => setState(() => _status = 'All'),
                    icon: const Icon(Icons.history),
                    label: const Text('Show all task statuses'),
                  ),
              ],
            ),
          ),
        for (final entry in entries) ...[
          _serviceJobCard(
            entry,
            expandedDetails: _expandedJobs.contains(entry.key)
                ? Column(
                    children: [
                      const Divider(height: 1),
                      // Match the approved isolated Tasks TEST: a distinct white
                      // rounded work card sits inside each tinted Job group.
                      for (final task
                          in _serviceRows(includeCompleted: true).where(
                            (task) =>
                                (task['job_id']?.toString() ??
                                    'Unlinked Job') ==
                                entry.key,
                          ))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                          child: CompactTaskCard(
                            key: ValueKey(task['line_id']),
                      task:task,
                            title:
                                (task['source_description'] ??
                                        task['description'] ??
                                        'Labor task')
                                    .toString(),
                            subtitle:
                                (widget.allocationsByLine[task['line_id']] ??
                                        [])
                                    .map(
                                      (r) =>
                                          '${widget.employeeName(r['employee_id'] as String?)} · ${((r['estimated_minutes'] as int? ?? 0) / 60).toStringAsFixed(1)} h',
                                    )
                                    .join(' · '),
                            status: _statusName(task['status']),
                            onLongPress: () => _taskActions(task, false),
                            details: widget.serviceTaskCard(task),
                          ),
                        ),
                      // A missing Job link is display-only. Never dispatch a
                      // fabricated label as a canonical Job ID for a recheck.
                      if (entry.key != 'Unlinked Job') ...[
                        TextButton.icon(
                          onPressed: () => widget.onOpenJob(entry.key),
                          icon: const Icon(Icons.open_in_new, size: 17),
                          label: const Text('Open Job Details'),
                        ),
                        if (widget.onAddRecheck != null)
                          TextButton.icon(
                            onPressed: () => widget.onAddRecheck!(entry.key),
                            icon: const Icon(Icons.add_task_outlined, size: 17),
                            label: const Text('Add Recheck'),
                          ),
                      ],
                      const SizedBox(height: 5),
                    ],
                  )
                : null,
          ),
        ],
      ],
    );
  }

  Widget _serviceJobCard(
    MapEntry<String, List<Map<String, dynamic>>> entry, {
    Widget? expandedDetails,
  }) {
    final tasks = entry.value;
    final first = tasks.first;
    final jobTasks = widget.serviceTasks
        .where((t) => (t['job_id']?.toString() ?? 'Unlinked Job') == entry.key)
        .toList();
    final progressTasks = jobTasks.isEmpty ? tasks : jobTasks;
    final done = progressTasks.where((t) => t['status'] == 'done').length;
    final status = done == progressTasks.length
        ? 'completed'
        : (done > 0 || progressTasks.any((t) => t['status'] == 'in_progress'))
        ? 'in_progress'
        : 'open';
    final color = status == 'open'
        ? WorkStatusColors.open
        : approvedJobListStatusColor({'status': status});
    final people = <String, int>{};
    final seen = <String>{};
    for (final task in progressTasks) {
      for (final person
          in widget.allocationsByLine[task['line_id']] ??
              const <Map<String, dynamic>>[]) {
        if (!seen.add(
          person['id']?.toString() ??
              '${task['line_id']}:${person['employee_id']}',
        ))
          continue;
        final label = widget.employeeName(person['employee_id']?.toString());
        people[label] =
            (people[label] ?? 0) + (person['estimated_minutes'] as int? ?? 0);
      }
    }
    final invoice =
        tasks
            .map((t) => t['invoice_number']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .firstOrNull ??
        '';
    final invoiceId = tasks
        .map(
          (t) =>
              t['invoice_id']?.toString() ?? t['document_id']?.toString() ?? '',
        )
        .where((s) => s.isNotEmpty)
        .firstOrNull;
    final descriptions = tasks
        .map(
          (t) => (t['source_description'] ?? t['description'] ?? '').toString(),
        )
        .where((s) => s.isNotEmpty)
        .toList();
    return JobListApprovedCard(
      job: {
        'status': status,
        'status_color': '#F58A00',
        'additional_work_count': descriptions.length > 2
            ? descriptions.length - 2
            : 0,
      },
      number: first['job_number']?.toString() ?? '',
      customer: first['customer_name']?.toString() ?? '',
      invoiceNumber: invoice,
      vehicle: first['vehicle_label']?.toString() ?? '',
      description: descriptions.take(2).join(' · '),
      mechanic: 'Unassigned',
      employee: '',
      mechanicMinutes: people,
      progress: JobTaskProgress(done, progressTasks.length),
      statusControl: ApprovedListStatusBadge(
        label: done == progressTasks.length
            ? 'Done'
            : status == 'in_progress'
            ? 'In Progress'
            : 'Not Started',
        color: color,
        icon: done == progressTasks.length
            ? Icons.check
            : status == 'in_progress'
            ? Icons.circle_outlined
            : Icons.schedule,
      ),
      onOpen: () => setState(() {
        if (!_expandedJobs.add(entry.key)) _expandedJobs.remove(entry.key);
      }),
      onOpenInvoice: invoiceId == null || widget.onOpenInvoice == null
          ? null
          : () => widget.onOpenInvoice!(invoiceId),
      expandedDetails: expandedDetails,
    );
  }

  Widget _generalView() {
    final tasks = _internal;
    return ListView(
      key: const Key('general-tasks-list'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'General Tasks · ' + tasks.length.toString(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (widget.scopedJob == null)
              TextButton.icon(
                onPressed: widget.onAddGeneral,
                icon: const Icon(Icons.add),
                label: const Text('New Task'),
              ),
          ],
        ),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(15),
            child: Text('No general tasks match these filters.'),
          ),
        for (final task in tasks)
          CompactTaskCard(
            key: ValueKey('general-task-${task['id']}'),
            title: task['description']?.toString() ?? '',
            subtitle: widget.employeeName(task['employee_id'] as String?),
            status: _statusName(task['status']),
            onLongPress: () => _taskActions(task, true),
            details: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task['due_at'] is int)
                  Text(
                    'Due ${DateFormat('MMM d, yyyy · h:mm a').format(DateTime.fromMillisecondsSinceEpoch(task['due_at'] as int))}',
                  ),
                Text(task['category']?.toString() ?? 'General'),
                if (task['status'] != 'done')
                  TextButton.icon(
                    onPressed: () =>
                        widget.onGeneralStatus(task['id'] as int, 'done'),
                    icon: const Icon(Icons.check),
                    label: const Text('Mark Done'),
                  ),
                if (widget.onEditGeneral != null)
                  TextButton.icon(
                    onPressed: () => widget.onEditGeneral!(task),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Task'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _jobLabel(String id) {
    final row = widget.serviceTasks.where((t) => t['job_id'] == id).firstOrNull;
    return row == null
        ? id
        : '${row['job_number'] ?? id} · ${row['customer_name'] ?? ''}';
  }

  Future<void> _taskActions(Map<String, dynamic> task, bool general) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((general ? widget.onEditGeneral : widget.onEditService) != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Task'),
                onTap: () {
                  Navigator.pop(sheet);
                  (general ? widget.onEditGeneral : widget.onEditService)!(
                    task,
                  );
                },
              ),
            if (!general && widget.onEditService != null)
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Edit Assignment'),
                onTap: () {
                  Navigator.pop(sheet);
                  widget.onEditService!(task);
                },
              ),
            if (task['status'] != 'done' &&
                (general || (widget.onMarkDone != null && (widget.allocationsByLine[task['line_id']]??[]).any((r)=>r['state']!='Done' && r['archived_labor']!=1 && r['source_active']!=0 && r['assignment_conflict']!=1 && (r['paid_minutes'] as int? ?? 0)==0 && (r['estimated_minutes'] as int? ?? 0)>0))))
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Mark Done'),
                onTap: () {
                  Navigator.pop(sheet);
                  if (general) {
                    widget.onGeneralStatus(task['id'] as int, 'done');
                  } else {
                    widget.onMarkDone!(task);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Column(
          children: [
            if (widget.scopedJob != null)
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: widget.onAddService,
                      icon: const Icon(Icons.add),
                      label: const Text('Labor Task'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: widget.onAddGeneral,
                      icon: const Icon(Icons.add),
                      label: const Text('General Task'),
                    ),
                  ),
                ],
              ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F7),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  for (final option in [false, true])
                    Expanded(
                      child: InkWell(
                        key: ValueKey(
                          option ? 'general-tasks-tab' : 'service-tasks-tab',
                        ),
                        onTap: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() {
                            _general = option;
                            _status = 'Active';
                            _employee = '';
                            _sort = 'Newest First';
                            _servicePeriod = 'Any time';
                            _job = 'All Jobs';
                            _search.clear();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: _general == option
                                ? BriskersColors.jobs
                                : null,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Text(
                            option ? 'General Tasks' : 'Service Tasks',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _general == option
                                  ? Colors.white
                                  : const Color(0xFF344054),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      hintText: _general
                          ? 'Search general tasks · $_status'
                          : 'Search job tasks · $_status',
                      prefixIcon: const Icon(Icons.search, size: 21),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 19),
                              onPressed: _search.clear,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('toggle-task-filters'),
                  onPressed: _filters,
                  tooltip: 'Task filters · $_status',
                  icon: const Icon(Icons.tune),
                  color: BriskersColors.jobs,
                ),
              ],
            ),
          ],
        ),
      ),
      Expanded(
        child: ClipRect(child: _general ? _generalView() : _serviceView()),
      ),
    ],
  );
}
