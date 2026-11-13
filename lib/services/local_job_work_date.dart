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
    await db.customStatement(
      'INSERT INTO local_job_work_dates(business_id,job_id,work_date) '
      'SELECT business_id,id,? FROM local_jobs WHERE business_id=? AND id=? '
      'ON CONFLICT(business_id,job_id) DO UPDATE SET work_date=excluded.work_date',
      [LocalTaskSchedule.day(date), business, job],
    );
  }
}
