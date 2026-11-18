import 'approved_tasks_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/work_status_colors.dart';
import '../../services/local_task_schedule.dart';
import '../../services/local_invoice_task_store.dart';
import '../../widgets/briskers_dialog.dart';

/// Read-only projection of saved allocations. No task or payment mutations.
class EmployeeWorkReview extends StatelessWidget {
  const EmployeeWorkReview({
    super.key,
    required this.week,
    required this.rows,
    required this.jobs,
    required this.onWeekChanged,
    required this.onJob,
    this.onTask,
    this.payrollSummary,
    this.employeeName,
    this.employeeId,
    this.paidMinutesThisWeek,
  });
  final DateTime week;
  final List<Map<String, dynamic>> rows, jobs;
  final ValueChanged<DateTime> onWeekChanged;
  final ValueChanged<String> onJob;
  final ValueChanged<Map<String, dynamic>>? onTask;
  final Widget? payrollSummary;
  final String? employeeName, employeeId;
  final int? paidMinutesThisWeek;
  static DateTime monday(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
  static String weekLabel(DateTime week) {
    final start = monday(week);
    final friday = start.add(const Duration(days: 4));
    return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(friday)}';
  }

  static DateTime? date(Map<String, dynamic> r) {
    for (final key in [
      'work_start_date',
      'work_end_date',
      'completed_date',
      'invoice_date',
      'job_document_date',
    ]) {
      final d = DateTime.tryParse(r[key]?.toString() ?? '');
      if (d != null) return d;
    }
    final created = r['job_created_at'];
    return created is int && created > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            created < 100000000000 ? created * 1000 : created,
          )
        : null;
  }

  static int minutes(Map<String, dynamic> r) =>
      r['state'] == 'Done' && (r['actual_minutes'] as int? ?? 0) > 0
      ? r['actual_minutes'] as int
      : r['estimated_minutes'] as int? ?? 0;
  static String paymentState(Map<String, dynamic> r) =>
      r['paid'] == 1 || r['owner_prior_paid'] == 1
      ? 'Paid'
      : r['archived_labor'] == 1 || r['assignment_conflict'] == 1
      ? 'Unknown · Needs review'
      : (r['paid_minutes'] as int? ?? 0) > 0
      ? 'Partially paid'
      : 'Unpaid';
  static Color color(String? state) => switch (state) {
    'Done' => WorkStatusColors.done,
    'In Progress' => WorkStatusColors.progress,
    _ => WorkStatusColors.open,
  };
  static bool fallsInWeek(Map<String, dynamic> r, DateTime week) {
    final start = monday(week), end = start.add(const Duration(days: 5));
      if (LocalTaskSchedule.parse(r['work_start_date']) != null &&
          LocalTaskSchedule.parse(r['work_end_date']) != null) {
        return LocalTaskSchedule.inWeek(r, start) && r['source_active'] != 0;
      }
      final d = date(r);
      return d != null &&
          !d.isBefore(start) &&
          d.isBefore(end) &&
          r['source_active'] != 0;
  }

  /// A schedule/import date must not move historical or previously completed
  /// labor into a new week. This projection never changes a task or payment.
  static String weeklyReason(Map<String, dynamic> row, DateTime week, {DateTime? now}) {
    final start = monday(week), end = start.add(const Duration(days: 5));
    if (row['duplicate_of_task_id'] != null) return 'Excluded: verified duplicate listing';
    if (row['source_active'] == 0) return 'Excluded: inactive source';
    if (row['assignment_conflict'] == 1) return 'Excluded: assignment needs review';
    if (row['archived_labor'] == 1 || row['recordkeeping_only'] == true) {
      final originalDate = LocalTaskSchedule.parse(row['invoice_date']) ??
          LocalTaskSchedule.parse(row['job_document_date']);
      if (originalDate != null && originalDate.isBefore(DateTime.parse(LocalInvoiceTaskStore.payrollCutover)) &&
          !originalDate.isBefore(start) && originalDate.isBefore(end)) {
        return 'Included: historical invoice date';
      }
      return 'Excluded: historical labor';
    }
    if (row['state'] == 'Done') {
      final completed = LocalTaskSchedule.parse(row['completed_date']);
      if (completed != null) {
        return !completed.isBefore(start) && completed.isBefore(end)
            ? 'Included: completed this week'
            : 'Excluded: completed outside this week';
      }
      if (row['paid'] == 1 || row['owner_prior_paid'] == 1 ||
          (row['paid_minutes'] as int? ?? 0) > 0) {
        return 'Excluded: paid labor without a completion date';
      }
    }
    if (fallsInWeek(row, week)) return 'Included: saved work dates';
    final scheduledEnd = LocalTaskSchedule.parse(row['work_end_date']) ?? date(row);
    if (start == monday(now ?? DateTime.now()) && row['state'] == 'In Progress' &&
        scheduledEnd != null && scheduledEnd.isBefore(start)) {
      return 'Included: work still in progress';
    }
    return 'Excluded: outside this week';
  }

  static List<Map<String, dynamic>> weeklyRows(
    List<Map<String, dynamic>> rows, DateTime week, {DateTime? now}
  ) => rows.where((row) => weeklyReason(row, week, now: now).startsWith('Included:')).toList();

  String _auditLine(Map<String, dynamic> row) => [
    '${row['job_number'] ?? 'Job'} · ${row['customer_name'] ?? ''}',
    '${row['description'] ?? 'Labor'} · ${row['state'] ?? ''}',
    'Assigned: ${((row['estimated_minutes'] as int? ?? 0) / 60).toStringAsFixed(2)} h; '
      'recorded: ${(minutes(row) / 60).toStringAsFixed(2)} h; '
      'paid: ${((row['paid_minutes'] as int? ?? 0) / 60).toStringAsFixed(2)} h; '
      'remaining: ${((row['remaining_minutes'] as int? ?? 0) / 60).toStringAsFixed(2)} h',
    'Payment state: ${paymentState(row)}; archived: ${row['archived_labor'] ?? 0}',
    'Original task ID: ${row['duplicate_of_task_id'] ?? 'this task'}; source: ${row['source_kind'] ?? 'unknown'}; '
      'last paid week: ${row['last_paid_week'] ?? 'unknown'}; prior-paid flag: ${row['owner_prior_paid'] ?? 0}',
    'Work dates: ${row['work_start_date'] ?? 'unknown'} – ${row['work_end_date'] ?? 'unknown'}; '
      'completed: ${row['completed_date'] ?? 'unknown'}; invoice date: ${row['invoice_date'] ?? 'unknown'}',
    weeklyReason(row, week),
    'Allocation ID: ${row['id']}; task ID: ${row['task_id']}; '
      'Job ID: ${row['job_id']}; invoice ID: ${row['invoice_id']}; line ID: ${row['source_line_id']}',
  ].join('\n');

  Future<void> _showBreakdown(BuildContext context) async {
    final report = [
      'Weekly labor — ${employeeName ?? 'Employee'} — ${weekLabel(week)}',
      'Read only: task and payment records unchanged.',
      for (final row in rows) _auditLine(row),
    ].join('\n\n');
    await showDialog<void>(context: context, builder: (dialogContext) => BriskersDialog(
      title: 'Weekly hours breakdown', icon: Icons.fact_check_outlined,
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.48,
        child: rows.isEmpty ? const Text('No saved labor records.') : ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 24),
          itemBuilder: (_, index) => SelectableText(_auditLine(rows[index])),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(dialogContext),
          style: BriskersDialog.cancelStyle, child: const Text('Close')),
        FilledButton.icon(onPressed: () async {
          await Clipboard.setData(ClipboardData(text: report));
          if (dialogContext.mounted) Navigator.pop(dialogContext);
        }, style: BriskersDialog.confirmStyle(), icon: const Icon(Icons.copy),
          label: const Text('Copy breakdown')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final start = monday(week);
    final visible = weeklyRows(rows, week);
    int unpaidAssignment(Map<String, dynamic> row) {
      final assigned = row['estimated_minutes'] as int? ?? 0;
      final paid = row['paid_minutes'] as int? ?? 0;
      return (assigned - paid).clamp(0, 0x7fffffff);
    }
    int sum(Iterable<Map<String, dynamic>> rs, {bool unpaid = false}) =>
        rs.fold(0, (n, r) => n + (unpaid ? unpaidAssignment(r) : minutes(r)));
    String hrs(int n) => (n / 60).toStringAsFixed(2);
    return Theme(
      data: Theme.of(context).copyWith(
        cardTheme: CardThemeData(
          color: const Color(0xFFF9FAFF),
          surfaceTintColor: Colors.transparent,
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shadowColor: const Color(0x40051D35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: const BorderSide(color: Color(0xFFE0E4ED)),
          ),
        ),
      ),
      child: ListView(
        key: const Key('employee-work-review'),
        primary: false,
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Card(
            color: const Color(0xFFD6E9FF),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous work week',
                  onPressed: () =>
                      onWeekChanged(week.subtract(const Duration(days: 7))),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: week,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) onWeekChanged(monday(picked));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            color: taskNavy,
                            size: 23,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              weekLabel(week),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next work week',
                  onPressed: () =>
                      onWeekChanged(week.add(const Duration(days: 7))),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Card(
            child: ExpansionTile(
              shape:const Border(),collapsedShape:const Border(),
              key: ValueKey('work-review-assigned-tasks-${employeeId ?? employeeName}-${start.toIso8601String()}'),
              initiallyExpanded: rows.any((r) => r['state'] != 'Done' && r['source_active'] != 0 && r['assignment_conflict'] != 1),
              title: Text(
                'Currently Assigned Tasks (${rows.where((r) => r['state'] != 'Done' && r['source_active'] != 0 && r['assignment_conflict'] != 1).length})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              children: [
                for (final r in rows.where(
                  (r) =>
                      r['state'] != 'Done' &&
                      r['source_active'] != 0 &&
                      r['assignment_conflict'] != 1,
                ))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: ColoredBox(
                        color: color(r['state'] as String?),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: ColoredBox(
                            color: Colors.white,
                            child: Column(
                              children: [
                                Material(
                                  color: Colors.transparent,
                                  child: ListTile(
                                    isThreeLine: true,
                                    key: ValueKey('assigned-task-${r['id']}'),
                                    onTap: onTask == null ? null : () => onTask!(r),
                                    title: Text(
                                      '${r['description'] ?? 'Labor'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    subtitle: Text(
                                      "${r['job_number'] ?? 'Job'} · ${r['customer_name'] ?? ''}\n"
                                      "${employeeName ?? r['employee_name'] ?? 'Mechanic'} · "
                                      "${hrs(r['estimated_minutes'] as int? ?? 0)} h",
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: SizedBox(
                                      height: 54,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TaskPriorityPill(
                                              priority: r['priority']?.toString() ?? 'Normal',
                                            ),
                                            const SizedBox(height: 4),
                                            TaskStatusPill(r['state']),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                  child: Row(
                                    children: [
                                      for (final (label, minutes, tint) in [
                                        ('Assigned', r['estimated_minutes'] as int? ?? 0, taskNavy),
                                        ('Paid', r['paid_minutes'] as int? ?? 0, taskGreen),
                                        ('Remaining', ((r['estimated_minutes'] as int? ?? 0) -
                                            (r['paid_minutes'] as int? ?? 0)).clamp(0, 0x7fffffff), taskNavy),
                                      ])
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Text(label, style: const TextStyle(fontSize: 11)),
                                              Text('${hrs(minutes)} hrs', style: TextStyle(
                                                color: tint, fontWeight: FontWeight.w800)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!rows.any(
                  (r) =>
                      r['state'] != 'Done' &&
                      r['source_active'] != 0 &&
                      r['assignment_conflict'] != 1,
                ))
                  const ListTile(title: Text('No current assigned tasks.')),
              ],
            ),
          ),
          Card(
            color: const Color(0xFFE0FAD8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.assignment_outlined, color: taskGreen),
                      const SizedBox(width: 7),
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Weekly Labor', maxLines: 1,
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Total assigned: ${hrs(sum(visible, unpaid: true))} hrs',
                              maxLines: 1,
                              style: const TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w800, color: Color(0xFF075C18)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(weekLabel(week), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FFFA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final state in ['Done', 'In Progress', 'Open']) ...[
                            if (state != 'Done')
                              const VerticalDivider(
                                width: 1,
                                color: Color(0xFFAAC8BD),
                              ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                child: Column(
                                  children: [
                                    Icon(
                                      taskStatusIcon(state),
                                      color: color(state),
                                      size: 18,
                                    ),
                                    Text(
                                      '${state == 'Done'
                                          ? 'Completed'
                                          : state == 'Open'
                                          ? 'Not Started'
                                          : state}\n${hrs(sum(visible.where((r) => r['state'] == state), unpaid: state != 'Done'))} hrs',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: color(state),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (paidMinutesThisWeek != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Expanded(child: Text('Total Paid This Week')),
                      Text('${hrs(paidMinutesThisWeek!)} hrs',
                        style: const TextStyle(color: taskGreen, fontWeight: FontWeight.w800)),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Completed unpaid:',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                      Text(
                        '${hrs(visible.where((r) => r['state'] == 'Done' && r['archived_labor'] != 1 && r['assignment_conflict'] != 1).fold<int>(0, (n, r) => n + (r['remaining_minutes'] as int? ?? 0)))} hrs',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    key: const Key('weekly-hours-breakdown'),
                    onPressed: () => _showBreakdown(context),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('View hours breakdown'),
                  ),
                ],
              ),
            ),
          ),
          ?payrollSummary,
        ],
      ),
    );
  }
}
