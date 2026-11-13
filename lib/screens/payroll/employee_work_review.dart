import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/work_status_colors.dart';

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
      'carry_week',
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
      final d = date(r);
      return d != null &&
          !d.isBefore(start) &&
          d.isBefore(end) &&
          r['source_active'] != 0;
    }).toList();
    int sum(Iterable<Map<String, dynamic>> rs) =>
        rs.fold(0, (n, r) => n + minutes(r));
    String hrs(int n) => (n / 60).toStringAsFixed(2);
    return ListView(
      key: const Key('employee-work-review'),
      padding: const EdgeInsets.all(12),
      children: [
        const Card(
          color: Color(0xFFEAF2FF),
          child: ListTile(
            leading: Icon(Icons.assignment_outlined),
            title: Text(
              'Work Review (Read Only)',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text('Assigned jobs and labor for the selected week.'),
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
            initiallyExpanded: true,
            title: Text(
              'Currently Assigned Jobs (${jobs.length})',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            children: [
              for (final j in jobs)
                ListTile(
                  onTap: () => onJob(j['id'] as String),
                  title: Text(
                    '${j['job_number'] ?? 'Job'} · ${j['customer_name'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('${j['vehicle_label'] ?? ''}'),
                  trailing: Text(
                    j['status'] == 'in_progress' ? 'In Progress' : 'Open',
                    style: TextStyle(
                      color: j['status'] == 'in_progress'
                          ? WorkStatusColors.progress
                          : WorkStatusColors.open,
                    ),
                  ),
                ),
              if (jobs.isEmpty)
                const ListTile(title: Text('No current assigned jobs.')),
            ],
          ),
        ),
        Card(
          color: const Color(0xFFEDF8F1),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Labor This Week · ${visible.length} tasks',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text('Assigned hours: ${hrs(sum(visible))} hrs'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    for (final state in ['Done', 'In Progress', 'Open'])
                      Text(
                        '${state == 'Done'
                            ? 'Completed'
                            : state == 'Open'
                            ? 'Not Started'
                            : state}\n${hrs(sum(visible.where((r) => r['state'] == state)))} hrs',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: color(state),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Completed unpaid: ${hrs(visible.where((r) => r['state'] == 'Done' && r['archived_labor'] != 1 && r['assignment_conflict'] != 1).fold<int>(0, (n, r) => n + (r['remaining_minutes'] as int? ?? 0)))} hrs',
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
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(color: color(r['state'] as String?), width: 5),
              ),
            ),
            child: ListTile(
              title: Text(
                '${r['job_number'] ?? 'Job'} · ${r['description'] ?? 'Labor'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
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
      ],
    );
  }
}
