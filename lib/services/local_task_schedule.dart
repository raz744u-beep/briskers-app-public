import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';

/// Scheduling belongs to the task, never to a payment or invoice.
class LocalTaskSchedule {
  const LocalTaskSchedule(this.db);
  final BriskersLocalDatabase db;
  static String day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static DateTime? parse(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final result = DateTime.tryParse(value);
    return result != null && day(result) == value ? result : null;
  }

  static bool overdue(Map<String, dynamic> task, {DateTime? now}) {
    final status = (task['state'] ?? task['status'])?.toString().toLowerCase();
    final end = parse(task['work_end_date']);
    final today = now ?? DateTime.now();
    return status != 'done' &&
        end != null &&
        end.isBefore(DateTime(today.year, today.month, today.day));
  }

  static bool inWeek(Map<String, dynamic> task, DateTime monday) {
    final start = parse(task['work_start_date']);
    final end = parse(task['work_end_date']);
    return start != null &&
        end != null &&
        start.isBefore(monday.add(const Duration(days: 5))) &&
        !end.isBefore(monday);
  }

  Future<void> prepare() => db.customStatement(
    'CREATE TABLE IF NOT EXISTS regular_task_schedule_v1 ('
    'business_id TEXT NOT NULL,task_id TEXT NOT NULL,start_date TEXT NOT NULL,end_date TEXT NOT NULL,'
    "priority TEXT NOT NULL DEFAULT 'Normal',payroll_treatment TEXT NOT NULL DEFAULT 'unpaid',revision INTEGER NOT NULL DEFAULT 0,"
    'PRIMARY KEY(business_id,task_id))',
  );
  Future<void> created(String business, String task, DateTime date) async {
    await prepare();
    await db.customStatement(
      'INSERT OR IGNORE INTO regular_task_schedule_v1(business_id,task_id,start_date,end_date) VALUES(?,?,?,?)',
      [business, task, day(date), day(date)],
    );
  }

  Future<void> save(
    String business,
    String task,
    String start,
    String end,
    String priority, {
    String? treatment,
  }) async {
    if (parse(start) == null ||
        parse(end) == null ||
        start.compareTo(end) > 0 ||
        !const ['High', 'Normal', 'Low'].contains(priority) ||
        (treatment != null &&
            !const ['unpaid', 'review'].contains(treatment))) {
      throw ArgumentError(
        'Enter valid start/end dates and priority. End Date must be on or after Start Date.',
      );
    }
    await prepare();
    final exists = await db
        .customSelect(
          'SELECT id FROM regular_payroll_tasks WHERE business_id=? AND id=?',
          variables: [Variable(business), Variable(task)],
        )
        .get();
    if (exists.length != 1) {
      throw StateError(
        'The saved task is unavailable. Refresh before editing.',
      );
    }
    await db.customStatement(
      'INSERT INTO regular_task_schedule_v1(business_id,task_id,start_date,end_date,priority,payroll_treatment) VALUES(?,?,?,?,?,?) '
      'ON CONFLICT(business_id,task_id) DO UPDATE SET start_date=excluded.start_date,end_date=excluded.end_date,priority=excluded.priority,'
      'payroll_treatment=COALESCE(?,regular_task_schedule_v1.payroll_treatment),revision=regular_task_schedule_v1.revision+1',
      [business, task, start, end, priority, treatment ?? 'unpaid', treatment],
    );
  }
}
