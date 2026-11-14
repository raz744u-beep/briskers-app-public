import 'package:drift/drift.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../local/briskers_local_database.dart';
import 'local_task_schedule.dart';

/// Owner's calendar date, separate from immutable creation and financial dates.
class LocalJobWorkDate {
  const LocalJobWorkDate(this.db);
  final BriskersLocalDatabase db;
  static final _shop = _location();
  static tz.Location _location() {
    tzdata.initializeTimeZones();
    return tz.getLocation('America/Chicago');
  }

  static DateTime today({DateTime? now}) {
    final local = tz.TZDateTime.from(now ?? DateTime.now(), _shop);
    return DateTime(local.year, local.month, local.day);
  }

  Future<void> prepare() => db.customStatement(
    'CREATE TABLE IF NOT EXISTS local_job_work_dates ('
    'business_id TEXT NOT NULL,job_id TEXT NOT NULL,work_date TEXT NOT NULL,'
    'PRIMARY KEY(business_id,job_id))',
  );

  Future<DateTime?> read(String business, String job) async {
    await prepare();
    final row = await db
        .customSelect(
          'SELECT work_date FROM local_job_work_dates WHERE business_id=? AND job_id=?',
          variables: [Variable(business), Variable(job)],
        )
        .getSingleOrNull();
    return LocalTaskSchedule.parse(row?.data['work_date']);
  }

  Future<void> save(String business, String job, DateTime date) async {
    await prepare();
    await LocalTaskSchedule(db).prepare();
    await db.transaction(() async {
      await db.customStatement(
        'INSERT INTO local_job_work_dates(business_id,job_id,work_date) '
        'SELECT business_id,id,? FROM local_jobs WHERE business_id=? AND id=? '
        'ON CONFLICT(business_id,job_id) DO UPDATE SET work_date=excluded.work_date',
        [LocalTaskSchedule.day(date), business, job],
      );
      final exists = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='regular_payroll_tasks'",
          )
          .get();
      if (exists.isNotEmpty) {
        await db.customStatement(
          "UPDATE regular_task_schedule_v1 SET start_date=?,end_date=?,revision=revision+1 WHERE business_id=? "
          "AND EXISTS(SELECT 1 FROM regular_task_metadata m JOIN regular_payroll_tasks t ON t.business_id=m.business_id AND t.id=m.task_id "
          "WHERE m.business_id=regular_task_schedule_v1.business_id AND m.task_id=regular_task_schedule_v1.task_id AND m.date_mode='inherited' AND t.job_id=?) "
          "AND (start_date<>? OR end_date<>?)",
          [
            LocalTaskSchedule.day(date),
            LocalTaskSchedule.day(date),
            business,
            job,
            LocalTaskSchedule.day(date),
            LocalTaskSchedule.day(date),
          ],
        );
      }
    });
  }
}
