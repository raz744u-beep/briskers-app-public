import '../local/briskers_local_database.dart';

/// Explicit task presentation/date provenance. Unknown legacy dates stay put.
class LocalTaskMetadata {
  const LocalTaskMetadata(this.db);
  final BriskersLocalDatabase db;
  Future<void> prepare() async {
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS regular_task_metadata ('
      'business_id TEXT NOT NULL,task_id TEXT NOT NULL,description TEXT,'
      "date_mode TEXT NOT NULL DEFAULT 'unknown',revision INTEGER NOT NULL DEFAULT 0,"
      'PRIMARY KEY(business_id,task_id))',
    );
  }

  Future<void> description(String business, String task, String value) async {
    if (value.trim().isEmpty) throw ArgumentError('Enter a task description.');
    await prepare();
    await db.customStatement(
      'INSERT INTO regular_task_metadata(business_id,task_id,description) VALUES(?,?,?) '
      'ON CONFLICT(business_id,task_id) DO UPDATE SET description=excluded.description,revision=revision+1',
      [business, task, value.trim()],
    );
  }

  Future<void> manualDates(String business, String task) async {
    await prepare();
    await db.customStatement(
      "INSERT INTO regular_task_metadata(business_id,task_id,date_mode) VALUES(?,?,'manual') "
      "ON CONFLICT(business_id,task_id) DO UPDATE SET date_mode='manual',revision=revision+1",
      [business, task],
    );
  }
}
