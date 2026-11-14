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
  });
  final DateTime week;
  final List<Map<String, dynamic>> rows, jobs;
  final ValueChanged<DateTime> onWeekChanged;
  final ValueChanged<String> onJob;
  static DateTime monday(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
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
  @override
  Widget build(BuildContext context) {
    final start = monday(week), end = monday(week).add(const Duration(days: 5));
    final visible = rows.where((r) {
      if (LocalTaskSchedule.parse(r['work_start_date']) != null &&
          LocalTaskSchedule.parse(r['work_end_date']) != null) {
        return LocalTaskSchedule.inWeek(r, start) && r['source_active'] != 0;
      }
      final d = date(r);
      return d != null &&
          !d.isBefore(start) &&
          d.isBefore(end) &&
          r['source_active'] != 0;
    }).toList();
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
          const Card(
            color: Color(0xFFD6E9FF),
            child: ListTile(
              leading: Icon(
                Icons.assignment_outlined,
                size: 30,
                color: taskNavy,
              ),
              title: Text(
                'Work Review (Read Only)',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              dense: false,
              subtitle: Text(
                'Assigned jobs & weekly labor',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Card(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous work week',
                  onPressed: () =>
                      onWeekChanged(week.subtract(const Duration(days: 7))),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end.subtract(const Duration(days: 1)))}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
              key: const PageStorageKey('work-review-assigned-jobs'),
              initiallyExpanded: true,
              title: Text(
                'Currently Assigned Jobs (${jobs.length})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              children: [
                for (final j in jobs)
                  Container(
                    margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                      border: const Border(
                        left: BorderSide(color: taskBlue, width: 5),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22051D35),
                          offset: Offset(0, 2),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: ListTile(
                        onTap: () => onJob(j['id'] as String),
                        title: Text(
                          '${j['job_number'] ?? 'Job'} · ${j['customer_name'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('${j['vehicle_label'] ?? ''}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TaskStatusPill(j['status'], icon: false),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (jobs.isEmpty)
                  const ListTile(title: Text('No current assigned jobs.')),
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
                      Expanded(
                        child: Text(
                          'Labor This Week · ${visible.length} tasks',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        '${hrs(sum(visible))} hrs',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF075C18),
                        ),
                      ),
                    ],
                  ),
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
                                  child: Text(
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
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
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
          if (visible.isEmpty)
            const ListTile(title: Text('No recorded labor for this week.')),
          for (final r in visible)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22051D35),
                    offset: Offset(0, 2),
                    blurRadius: 2,
                  ),
                ],
                border: Border(
                  left: BorderSide(
                    color: color(r['state'] as String?),
                    width: 5,
                  ),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    useSafeArea: true,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (sheet) => SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${r['job_number'] ?? 'Job'} · ${r['customer_name'] ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text('${r['description'] ?? 'Labor'}'),
                            const SizedBox(height: 10),
                            Text(
                              '${hrs(minutes(r))} h · ${r['state']} · ${paymentState(r)}',
                            ),
                            Text(
                              '${r['work_start_date'] ?? ''} – ${r['work_end_date'] ?? ''}',
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(sheet),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    '${r['job_number'] ?? 'Job'} · ${r['description'] ?? 'Labor'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  subtitle: Text(
                    '${r['customer_name'] ?? ''}\n${r['state'] == 'Done'
                        ? 'Completed'
                        : r['state'] == 'Open'
                        ? 'Not Started'
                        : r['state']} · ${paymentState(r)}',
                  ),
                  trailing: Text(
                    '${hrs(minutes(r))} h',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
