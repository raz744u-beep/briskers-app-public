import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';

/// A one-time presentation cutoff. Future reminders and newly added tasks
/// remain active; this never writes wages or changes the original task status.
class HistoricalGeneralTasks {
  HistoricalGeneralTasks(this.db);
  final BriskersLocalDatabase db;
  Future<Set<int>> completed(String business) async {
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS historical_general_task_cutover_v1 '
      '(business_id TEXT PRIMARY KEY)',
    );
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS historical_general_tasks_v1 '
      '(business_id TEXT NOT NULL,task_id INTEGER NOT NULL,PRIMARY KEY(business_id,task_id))',
    );
    final ready = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('regular_payroll_shop_tasks','regular_payroll_shop_task_jobs')",
        )
        .get();
    if (ready.length != 2) return {};
    await db.transaction(() async {
      final seeded = await db
          .customSelect(
            'SELECT 1 FROM historical_general_task_cutover_v1 WHERE business_id=?',
            variables: [Variable(business)],
          )
          .get();
      if (seeded.isNotEmpty) return;
      await db.customStatement(
        '''INSERT OR IGNORE INTO historical_general_tasks_v1
        SELECT t.business_id,t.id FROM regular_payroll_shop_tasks t
        JOIN regular_payroll_shop_task_jobs l ON l.business_id=t.business_id AND l.task_id=t.id
        JOIN local_jobs j ON j.business_id=l.business_id AND j.id=l.job_id
        WHERE t.business_id=? AND (t.due_at IS NULL OR t.due_at < 1794204000000)
        AND COALESCE((SELECT MIN(d.document_date) FROM local_documents d
          WHERE d.business_id=j.business_id AND d.job_id=j.id),date(j.created_at,'-6 hours')) < '2026-11-09'
      ''',
        [business],
      );
      await db.customStatement(
        'INSERT INTO historical_general_task_cutover_v1 VALUES(?)',
        [business],
      );
    });
    return (await db
            .customSelect(
              'SELECT task_id FROM historical_general_tasks_v1 WHERE business_id=?',
              variables: [Variable(business)],
            )
            .get())
        .map((r) => r.read<int>('task_id'))
        .toSet();
  }
}
