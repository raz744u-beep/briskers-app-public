import 'approved_tasks_ui.dart';
// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';

/// Compact, job-only Tasks presentation approved by the Owner.
/// This reads the SAME saved allocations and general tasks as payroll.
/// No status/employee/time filters and no additional task/payment ledger.
class JobScopedTasks extends StatefulWidget {
  const JobScopedTasks({
    super.key,
    required this.jobId,
    required this.serviceTasks,
    required this.generalTasks,
    required this.allocationsByLine,
    required this.employeeName,
    required this.onAddLabor,
    required this.onAddGeneral,
    required this.onLaborProgress,
    required this.onGeneralProgress,
    this.onManageLabor,
    this.onEditLabor,
    this.onManageGeneral,
    this.onReconcileLabor,
    this.onReviewLabor,
    this.onMarkAllDone,
    this.markAllDoneCount = 0,
    this.onOpenTask,
    this.onPriority,
  });

  final ValueChanged<Map<String, dynamic>>? onReconcileLabor;
  final ValueChanged<Map<String, dynamic>>? onReviewLabor;
  final void Function(Map<String, dynamic>, bool)? onOpenTask;
  final void Function(Map<String, dynamic>, bool, String)? onPriority;
  final String jobId;
  final Future<void> Function()? onMarkAllDone;
  final int markAllDoneCount;
  final List<Map<String, dynamic>> serviceTasks;
  final List<Map<String, dynamic>> generalTasks;
  final Map<String, List<Map<String, dynamic>>> allocationsByLine;
  final String Function(String?) employeeName;
  final VoidCallback? onAddLabor;
  final VoidCallback onAddGeneral;
  final Future<void> Function(Map<String, dynamic> allocation, bool finish)
  onLaborProgress;
  final Future<void> Function(int taskId, String nextStatus) onGeneralProgress;
  final ValueChanged<Map<String, dynamic>>? onManageLabor;
  final ValueChanged<Map<String, dynamic>>? onEditLabor;
  final ValueChanged<Map<String, dynamic>>? onManageGeneral;

  @override
  State<JobScopedTasks> createState() => _JobScopedTasksState();
}

class _JobScopedTasksState extends State<JobScopedTasks> {
  String? _running;

  String _status(Map<String, dynamic> task, bool general) {
    final raw = task['status']?.toString() ?? '';
    if (raw == 'done' || raw == 'Done') return 'Done';
    if (raw == 'in_progress' || raw == 'In Progress') return 'In Progress';
    return 'Not Started';
  }

  int _order(String status) => switch (status) {
    'In Progress' => 0,
    'Not Started' => 1,
    _ => 2,
  };

  List<Map<String, dynamic>> _allocations(Map<String, dynamic> task) =>
      widget.allocationsByLine[task['line_id']?.toString() ?? ''] ??
      const <Map<String, dynamic>>[];

  bool _canChange(Map<String, dynamic> row) =>
      row['archived_labor'] != 1 &&
      row['source_active'] != 0 &&
      row['assignment_conflict'] != 1 &&
      row['state'] != 'Done' &&
      (row['paid_minutes'] as int? ?? 0) == 0 &&
      row['paid'] != 1;

  Future<void> _act(String key, Future<void> Function() action) async {
    if (_running != null) return;
    setState(() => _running = key);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<void> _longPress(
    String key,
    Map<String, dynamic> row,
    bool general,
  ) async {
    final editableLabor = !general && widget.onManageLabor != null;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('View task details'),
                onTap: () {
                  Navigator.pop(sheet);
                  widget.onOpenTask?.call(row, general);
                },
              ),
              if (!general && widget.onEditLabor != null)
                ListTile(
                  leading: const Icon(Icons.edit_calendar_outlined),
                  title: const Text('Edit Task'),
                  onTap: () {
                    Navigator.pop(sheet);
                    widget.onEditLabor!(row);
                  },
                ),
              if (editableLabor)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit Assignment'),
                  onTap: () {
                    Navigator.pop(sheet);
                    widget.onManageLabor!(row);
                  },
                ),
              if (general && widget.onManageGeneral != null)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit Task'),
                  onTap: () {
                    Navigator.pop(sheet);
                    widget.onManageGeneral!(row);
                  },
                ),
              if (_status(row, general) != 'Done' &&
                  (general ||
                      _allocations(row).any(
                        (r) =>
                            _canChange(r) &&
                            (r['estimated_minutes'] as int? ?? 0) > 0,
                      )))
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Mark Done'),
                  onTap: () async {
                    Navigator.pop(sheet);
                    await _act(key, () async {
                      if (general) {
                        await widget.onGeneralProgress(
                          row['id'] as int,
                          'done',
                        );
                      } else {
                        for (final allocation in _allocations(
                          row,
                        ).where(_canChange)) {
                          await widget.onLaborProgress(allocation, true);
                        }
                      }
                    });
                  },
                ),
              if (!general)
                for (final allocation in _allocations(row)) ...[
                  if (_canReconcile(allocation) &&
                      widget.onReconcileLabor != null)
                    ListTile(
                      leading: const Icon(Icons.verified_outlined),
                      title: const Text('Reconcile historical wages'),
                      subtitle: _allocations(row).length > 1
                          ? Text(
                              widget.employeeName(
                                allocation['employee_id']?.toString(),
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(sheet);
                        widget.onReconcileLabor!(allocation);
                      },
                    ),
                  if (_canReconcile(allocation) &&
                      allocation['archived_labor'] == 1 &&
                      widget.onReviewLabor != null)
                    ListTile(
                      leading: const Icon(Icons.manage_search),
                      title: const Text('Review unpaid work'),
                      onTap: () {
                        Navigator.pop(sheet);
                        widget.onReviewLabor!(allocation);
                      },
                    ),
                ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  bool _canReconcile(Map<String, dynamic> row) =>
      row['owner_prior_paid'] != 1 &&
      row['paid'] != 1 &&
      (row['paid_minutes'] as int? ?? 0) == 0 &&
      row['assignment_conflict'] != 1 &&
      row['source_active'] != 0;
  Widget _task(Map<String, dynamic> row, bool general) {
    final allocations = _allocations(row);
    final assignment = general
        ? 'General · ${widget.employeeName(row['employee_id']?.toString())}'
        : allocations.isEmpty
        ? 'Labor · Unassigned'
        : 'Labor · ${allocations.map((a) => "${widget.employeeName(a['employee_id']?.toString())} · ${((a['estimated_minutes'] as int? ?? 0) / 60).toStringAsFixed(1)} hrs").join(' · ')}';
    final key =
        '${general ? 'g' : 'l'}-${general ? row['id'] : row['line_id']}';
    return ApprovedTaskListCard(
      key: ValueKey('job-task-$key'),
      task: row,
      assignment: assignment,
      general: general,
      jobScoped: true,
      onTap: () => widget.onOpenTask?.call(row, general),
      onLongPress: () => _longPress(key, row, general),
      onPriority: widget.onPriority == null
          ? null
          : (p) => widget.onPriority!(row, general, p),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labor = widget.serviceTasks
        .where((t) => t['job_id'] == widget.jobId && t['source_missing'] != 1)
        .toList();
    final general = widget.generalTasks
        .where((t) => t['job_id'] == widget.jobId)
        .toList();
    final rows = <({Map<String, dynamic> data, bool general, String status})>[
      for (final t in labor)
        (data: t, general: false, status: _status(t, false)),
      for (final t in general)
        (data: t, general: true, status: _status(t, true)),
    ]..sort((a, b) => _order(a.status).compareTo(_order(b.status)));
    final source = labor.firstOrNull ?? general.firstOrNull;
    final vehicle = source?['vehicle_label']?.toString() ?? '';
    final done = rows.where((r) => r.status == 'Done').length;
    final progress = rows.isEmpty ? 0.0 : done / rows.length;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (vehicle.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFF),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFD6DDE8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.directions_car_outlined, color: taskNavy),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    vehicle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 9),
        Row(
          children: [
            for (final option in [false, true]) ...[
              if (option) const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: option ? widget.onAddGeneral : widget.onAddLabor,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF001D78),
                    side: const BorderSide(color: taskNavy),
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.add, size: 25),
                  label: FittedBox(
                    child: Text(
                      option ? 'General Task' : 'Labor Task',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (widget.markAllDoneCount > 0 &&
                widget.onMarkAllDone != null) ...[
              Expanded(
                flex: 5,
                child: FilledButton.icon(
                  key: const Key('job-mark-all-done'),
                  onPressed: _running != null
                      ? null
                      : () => _act('bulk-done', widget.onMarkAllDone!),
                  style: FilledButton.styleFrom(
                    backgroundColor: taskGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 40),
                  ),
                  icon: const Icon(Icons.check),
                  label: const FittedBox(
                    child: Text(
                      'Mark All Done',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              Container(
                height: 36,
                width: 1,
                color: const Color(0xFFC4CBD6),
                margin: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ],
            Expanded(
              flex: 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${rows.length} tasks ($done of ${rows.length} completed)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: LinearProgressIndicator(
                            value: progress,
                            color: taskGreen,
                            backgroundColor: const Color(0xFFD9DDE3),
                            minHeight: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        if (rows.isEmpty)
          const Text(
            'No tasks saved for this job. Add a Labor Task or General Task.',
          ),
        for (final task in rows) _task(task.data, task.general),
      ],
    );
  }
}
