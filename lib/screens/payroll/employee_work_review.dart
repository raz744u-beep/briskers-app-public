import 'approved_tasks_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/work_status_colors.dart';
import '../../services/local_task_schedule.dart';

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

  @override
  Widget build(BuildContext context) {
    final start = monday(week);
    final visible = rows.where((row) => fallsInWeek(row, week)).toList();
    final inProgressPaid = visible.where((row) => row['state'] == 'In Progress')
        .fold<int>(0, (sum, row) => sum + (row['paid_minutes'] as int? ?? 0));
    int sum(Iterable<Map<String, dynamic>> rs) =>
        rs.fold(0, (n, r) => n + minutes(r));
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
                  Container(
                    margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                      border: Border(
                        left: BorderSide(
                          color: color(r['state'] as String?),
                          width: 5,
                        ),
                      ),
                    ),
                    child: Column(children: [
                      Material(color:Colors.transparent,child:ListTile(
                      isThreeLine:true,
                      key: ValueKey('assigned-task-${r['id']}'),
                      onTap: onTask == null ? null : () => onTask!(r),
                      title: Text(
                        '${r['description'] ?? 'Labor'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${r['job_number'] ?? 'Job'} · ${r['customer_name'] ?? ''}\n${employeeName ?? r['employee_name'] ?? 'Mechanic'} · ${hrs(r['estimated_minutes'] as int? ?? 0)} h',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: SizedBox(height:54,child:FittedBox(fit:BoxFit.scaleDown,child:Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TaskPriorityPill(
                            priority: r['priority']?.toString() ?? 'Normal',
                          ),
                          const SizedBox(height: 4),
                          TaskStatusPill(r['state']),
                        ],
                      ))),
                    )),
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
                              Expanded(child: Column(children: [
                                Text(label, style: const TextStyle(fontSize: 11)),
                                Text('${hrs(minutes)} hrs', style: TextStyle(
                                  color: tint, fontWeight: FontWeight.w800)),
                              ])),
                          ],
                        ),
                      ),
                    ]),
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
                              'Total assigned: ${hrs(visible.fold<int>(0, (n, row) => n + (row['estimated_minutes'] as int? ?? 0)))} hrs',
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
                        children: [
                          for (final state in [
                            'Done',
                            'In Progress',
                            'Open',
                          ]) ...[
                            if (state != 'Done')
                              const VerticalDivider(
                                width: 1,
                                color: Color(0xFFAAC8BD),
                              ),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
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
                                            : state}\n${hrs(sum(visible.where((r) => r['state'] == state)))} hrs',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: color(state),
                                        ),
                                      ),
                                      if (state == 'In Progress' && inProgressPaid > 0)
                                        Text('(includes ${hrs(inProgressPaid)} hrs paid on these tasks)',
                                          style: const TextStyle(fontSize: 11)),
                                    ],
                                  ),
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
