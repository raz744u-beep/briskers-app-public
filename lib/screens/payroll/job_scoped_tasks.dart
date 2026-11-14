import '../../widgets/task_schedule_indicator.dart';
import '../../core/work_status_colors.dart';
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
    this.laborActions,
    this.onMarkAllDone,
    this.markAllDoneCount = 0,
  });

  final Widget Function(Map<String, dynamic>)? laborActions;
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
  final Future<void> Function(int taskId, String nextStatus)
      onGeneralProgress;
  final ValueChanged<Map<String, dynamic>>? onManageLabor;
  final ValueChanged<Map<String,dynamic>>? onEditLabor;
  final ValueChanged<Map<String, dynamic>>? onManageGeneral;

  @override
  State<JobScopedTasks> createState() => _JobScopedTasksState();
}

class _JobScopedTasksState extends State<JobScopedTasks> {
  static const blue = WorkStatusColors.progress;
  static const orange = WorkStatusColors.open;
  static const green = WorkStatusColors.done;
  final Set<String> _expanded = <String>{};
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

  Color _accent(String status) => switch (status) {
    'In Progress' => blue,
    'Not Started' => orange,
    _ => green,
  };
  Color _surface(String status) => switch (status) {
    'In Progress' => const Color(0xFFEAF4FF),
    'Not Started' => const Color(0xFFFFF6ED),
    _ => const Color(0xFFEAF8EF),
  };
  IconData _statusIcon(String status) => switch (status) {
    'In Progress' => Icons.play_circle_fill,
    'Not Started' => Icons.hourglass_top,
    _ => Icons.check_circle,
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

  void _toggle(String key) => setState(() {
    if (!_expanded.add(key)) _expanded.remove(key);
  });

  Future<void> _longPress(String key, Map<String, dynamic> row,
      bool general) async {
    final editableLabor = !general &&
        widget.onManageLabor != null;
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true, useSafeArea: true,
      builder: (sheet) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('View task details'),
            onTap: () {
              Navigator.pop(sheet);
              _toggle(key);
            },
          ),
          if (!general && widget.onEditLabor!=null)ListTile(leading:const Icon(Icons.edit_calendar_outlined),title:const Text('Edit Task'),onTap:(){Navigator.pop(sheet);widget.onEditLabor!(row);}),
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
          if(_status(row,general)!='Done') ListTile(leading:const Icon(Icons.check_circle_outline),title:const Text('Mark Done'),onTap:() async {
            Navigator.pop(sheet);
            await _act(key,() async {if(general){await widget.onGeneralProgress(row['id'] as int,'done');}else{for(final allocation in _allocations(row).where(_canChange)){await widget.onLaborProgress(allocation,true);}}});
          }),
          const SizedBox(height: 8),
        ],
      )),
    );
  }

  Widget _action(String key, String status, {
    Map<String, dynamic>? allocation,
    int? generalTask,
  }) {
    if (status == 'Done') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: green,
          borderRadius: BorderRadius.circular(11)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check, color: Colors.white, size: 17),
          SizedBox(width: 5),
          Text('Done', style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.w800)),
        ]),
      );
    }
    if (allocation == null && generalTask == null) return const SizedBox.shrink();
    final finish = status == 'In Progress';
    final enabled = _running == null &&
        (allocation == null || _canChange(allocation));
    final onPress = !enabled ? null : () => _act(key, () async {
      if (allocation != null) {
        await widget.onLaborProgress(allocation, finish);
      } else {
        await widget.onGeneralProgress(
          generalTask!, finish ? 'done' : 'in_progress');
      }
    });
    if (finish) {
      return FilledButton.icon(
        onPressed: onPress,
        style: FilledButton.styleFrom(backgroundColor: blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.check, size: 17),
        label: const Text('Finish'),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPress,
      style: OutlinedButton.styleFrom(foregroundColor: orange,
        side: const BorderSide(color: orange),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact),
      icon: const Icon(Icons.play_arrow, size: 17),
      label: const Text('Start'),
    );
  }

  Widget _details(Map<String, dynamic> row, bool general,
      List<Map<String, dynamic>> allocations, String status, String key) {
    final notes = (row['notes'] ?? row['note'] ?? '').toString().trim();
    final employee = widget.employeeName(row['employee_id']?.toString());
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(height: 12),
        if(!general && row['work_start_date']!=null)Text('Work dates: ${row['work_start_date']} – ${row['work_end_date']}'),
        if(!general && allocations.isEmpty && widget.onEditLabor!=null)TextButton(onPressed:()=>widget.onEditLabor!(row),child:const Text('Edit Task')),
        if (general) Text('Mechanic: ' + employee),
        if (!general)
          for (final allocation in allocations)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if(allocations.length>1)Row(children: [
                Expanded(child: Text(
                  widget.employeeName(allocation['employee_id']?.toString()) +
                  ' · ' +
                  ((allocation['estimated_minutes'] as int? ?? 0) / 60)
                    .toStringAsFixed(1) + ' hrs',
                  maxLines: 2)),
                // Single mechanic already has the action on the closed
                // card. Inline details stay read-only, without duplicates.
                // Split tasks retain independent per-mechanic actions.
                if (allocations.length > 1)
                  _action(key + '-' + allocation['id'].toString(),
                    allocation['state']?.toString() == 'Done' ? 'Done' :
                      allocation['state']?.toString() == 'In Progress'
                        ? 'In Progress' : 'Not Started',
                    allocation: allocation),
                ]),
                if (widget.laborActions != null) widget.laborActions!(allocation),
              ]),
            ),
        if (!general && widget.onManageLabor != null &&
            row['invoice_id'] is String && row['source_line_id'] is String)
          TextButton.icon(
            onPressed: _running != null ? null : () => widget.onManageLabor!(row),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit Assignment'),
          ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text('Notes: ' + notes),
        ],
      ]),
    );
  }

  Widget _task(Map<String, dynamic> row, bool general) {
    final status = _status(row, general);
    final key = (general ? 'g-' : 'l-') +
        (general ? row['id'] : row['line_id']).toString();
    final allocations = general ? <Map<String, dynamic>>[] : _allocations(row);
    final title = (row['custom_description'] ??
        row['source_description'] ?? row['description'] ?? 'Task').toString();
    final name = general
        ? widget.employeeName(row['employee_id']?.toString())
        : allocations.map((a) =>
            widget.employeeName(a['employee_id']?.toString())).toSet().join(', ');
    final assigned = general ? (row['estimated_minutes'] as int? ?? 0)
        : allocations.fold<int>(0, (n, a) =>
            n + (a['estimated_minutes'] as int? ?? 0));
    final hrs = assigned > 0
        ? ' · ' + (assigned / 60).toStringAsFixed(1) + ' hrs' : '';
    final color = _accent(status);
    final expanded = _expanded.contains(key);
    return Padding(
      key: ValueKey('job-task-' + key),
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _surface(status),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _toggle(key),
          onLongPress: () => _longPress(key, row, general),
          child: Container(
            decoration: BoxDecoration(
              // Flutter requires a uniform border when using rounded corners.
              // The status-colored outline, icon and tint remain visible.
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 12, 9, 12),
                child: Row(children: [
                  Icon(_statusIcon(status), color: color, size: 29),
                  const SizedBox(width: 9),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: expanded?null:1, overflow: expanded?null:TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 14.5)),
                      const SizedBox(height: 4),
                      Text((general ? 'General' : 'Labor') +
                        (name.isEmpty ? '' : ' · ' + name) + hrs,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                    ],
                  )),
                  if(!general)TaskScheduleIndicator({...row,'status':status}),
                  const SizedBox(width: 7),
                  if (general)
                    _action(key, status, generalTask: row['id'] as int?)
                  else if (allocations.length == 1)
                    _action(key, status,
                      allocation: allocations.single)
                  else if (allocations.isEmpty && status != 'Done')
                    // Do not create payable labor from a historical source
                    // that is read-only under the payroll cutover policy.
                    // Current work without an allocation can be recovered
                    // explicitly by the Owner.
                    row['archived_labor'] == 1
                        ? const Text('Historical · read only')
                        : OutlinedButton(
                            onPressed: widget.onManageLabor == null
                                ? null : () => widget.onManageLabor!(row),
                            child: const Text('Assign mechanic'),
                          )
                  else if (allocations.length > 1 && status != 'Done')
                    // Split work has separate Start/Finish actions per
                    // mechanic in expanded details. Make them discoverable
                    // from the collapsed card instead of showing no action.
                    TextButton(
                      onPressed: expanded ? null : () => _toggle(key),
                      child: const Text('View mechanics'),
                    )
                  else if (status == 'Done')
                    _action(key, status),
                ]),
              ),
              if (expanded)
                _details(row, general, allocations, status, key),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labor = widget.serviceTasks.where((t) =>
        t['job_id'] == widget.jobId && t['source_missing'] != 1).toList();
    final general = widget.generalTasks.where((t) =>
        t['job_id'] == widget.jobId).toList();
    final rows = <({Map<String, dynamic> data, bool general, String status})>[
      for (final t in labor)
        (data: t, general: false, status: _status(t, false)),
      for (final t in general)
        (data: t, general: true, status: _status(t, true)),
    ]..sort((a, b) => _order(a.status).compareTo(_order(b.status)));
    final source = labor.firstOrNull;
    final number = source?['job_number']?.toString().trim() ?? '';
    final customer = source?['customer_name']?.toString().trim() ?? '';
    final vehicle = source?['vehicle_label']?.toString().trim() ?? '';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
        child: Column(children: [
          // Both creation actions must fit the narrow Android job screen.
          // FittedBox scales only label content, never the touch target.
          Row(children: [
            Expanded(child: SizedBox(height: 44,
              child: OutlinedButton(
                onPressed: widget.onAddLabor,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  minimumSize: Size.zero,
                ),
                child: const FittedBox(fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, size: 20), SizedBox(width: 5),
                    Text('Labor Task', style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
                  ])),
              ))),
            const SizedBox(width: 8),
            Expanded(child: SizedBox(height: 44,
              child: OutlinedButton(
                onPressed: widget.onAddGeneral,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  minimumSize: Size.zero,
                ),
                child: const FittedBox(fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, size: 20), SizedBox(width: 5),
                    Text('General Task', style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
                  ])),
              ))),
          ]),
          if (number.isNotEmpty || customer.isNotEmpty || vehicle.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF7FAFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD0D7E2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((number.isEmpty ? 'Job' : number) +
                  (customer.isEmpty ? '' : ' · ' + customer),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
                if (vehicle.isNotEmpty)
                  Text(vehicle, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ],
          if(widget.markAllDoneCount>0 && widget.onMarkAllDone!=null)
            Align(alignment:Alignment.centerLeft,child:Padding(
              padding:const EdgeInsets.only(top:6),
              child:FilledButton.icon(
                key:const Key('job-mark-all-done'),
                onPressed:_running!=null?null:()=>_act('bulk-done',widget.onMarkAllDone!),
                style:FilledButton.styleFrom(backgroundColor:green,
                  foregroundColor:Colors.white,visualDensity:VisualDensity.compact,
                  padding:const EdgeInsets.symmetric(horizontal:12,vertical:8)),
                icon:const Icon(Icons.done_all,size:18),
                label:const Text('Mark All Done'),
              ),
            )),
        ]),
      ),
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          Text(rows.length.toString() + ' tasks',
            style: const TextStyle(fontWeight: FontWeight.w800,
              fontSize: 17)),
          const SizedBox(height: 12),
          if (rows.isEmpty) const Text(
            'No tasks saved for this job. Add a Labor Task or General Task.'),
          for (final task in rows) _task(task.data, task.general),
        ],
      )),
    ]);
  }
}
