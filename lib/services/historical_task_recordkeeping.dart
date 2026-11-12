import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';

/// Owner recordkeeping corrections never rewrite settled payroll allocations.
/// The original allocation ID remains the audit link to every paid snapshot.
class HistoricalTaskRecordkeeping {
  HistoricalTaskRecordkeeping(this.db);
  final BriskersLocalDatabase db;

  Future<void> prepare() => db.customStatement('''
    CREATE TABLE IF NOT EXISTS historical_task_recordkeeping_v1 (
      business_id TEXT NOT NULL, allocation_id TEXT NOT NULL,
      employee_id TEXT NOT NULL, employee_name TEXT NOT NULL,
      minutes INTEGER NOT NULL CHECK(minutes>=0),
      PRIMARY KEY(business_id,allocation_id))
  ''');

  Future<Map<String, Map<String, dynamic>>> read(String business) async {
    await prepare();
    final rows = await db
        .customSelect(
          'SELECT * FROM historical_task_recordkeeping_v1 WHERE business_id=?',
          variables: [Variable(business)],
        )
        .get();
    return {
      for (final row in rows) row.read<String>('allocation_id'): row.data,
    };
  }

  Future<void> save(
    String business,
    String allocation,
    String employee,
    String name,
    int minutes,
  ) async {
    if (employee.isEmpty ||
        name.trim().isEmpty ||
        minutes < 0 ||
        minutes > 600000) {
      throw ArgumentError('Valid mechanic and assigned hours required.');
    }
    await prepare();
    await db.customStatement(
      '''
      INSERT INTO historical_task_recordkeeping_v1 VALUES(?,?,?,?,?)
      ON CONFLICT(business_id,allocation_id) DO UPDATE SET
        employee_id=excluded.employee_id,employee_name=excluded.employee_name,
        minutes=excluded.minutes
    ''',
      [business, allocation, employee, name, minutes],
    );
  }
}
