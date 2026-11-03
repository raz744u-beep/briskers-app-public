import 'package:drift/drift.dart' show Variable;

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// A durable business- and employee-ID-scoped local display alias.
///
/// Nicknames live in the same SQLite database as Briskers shop records, so
/// normal app-database backups contain them. Full legal employee names are
/// never modified. Remote nickname synchronization remains a separate gate.
class EmployeeNicknameStore {
  EmployeeNicknameStore({BriskersLocalDatabase? database})
      : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;
  static final _schemaReady = Expando<Future<void>>();

  Future<void> _ensureSchema() {
    final existing = _schemaReady[_database];
    if (existing != null) return existing;
    Future<void> install() async {
      try {
        await _database.customStatement(
          '''CREATE TABLE IF NOT EXISTS local_employee_nicknames(
            business_id TEXT NOT NULL,
            employee_id TEXT NOT NULL,
            nickname TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (business_id, employee_id)
          )''',
        );
      } catch (_) {
        _schemaReady[_database] = null;
        rethrow;
      }
    }
    final created = install();
    _schemaReady[_database] = created;
    return created;
  }

  Future<Map<String, String>> all(String businessId) async {
    if (businessId.trim().isEmpty) return {};
    await _ensureSchema();
    final rows = await _database.customSelect(
      'SELECT employee_id,nickname FROM local_employee_nicknames '
      'WHERE business_id=?',
      variables: [Variable<String>(businessId)],
    ).get();
    return {
      for (final row in rows)
        if (row.read<String>('nickname').trim().isNotEmpty)
          row.read<String>('employee_id'): row.read<String>('nickname').trim(),
    };
  }

  Future<String?> get(String businessId, String employeeId) async {
    if (employeeId.trim().isEmpty) return null;
    return (await all(businessId))[employeeId];
  }

  Future<void> save(
    String businessId,
    String employeeId,
    String nickname,
  ) async {
    if (businessId.trim().isEmpty || employeeId.trim().isEmpty) {
      throw ArgumentError('A business and employee ID are required.');
    }
    final value = nickname.trim();
    if (value.length > 32 || value.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError('Nickname must be at most 32 characters on one line.');
    }
    await _ensureSchema();
    await _database.transaction(() async {
      if (value.isEmpty) {
        await _database.customStatement(
          'DELETE FROM local_employee_nicknames '
          'WHERE business_id=? AND employee_id=?',
          [businessId, employeeId],
        );
      } else {
        await _database.customStatement(
          '''INSERT INTO local_employee_nicknames(
            business_id,employee_id,nickname,updated_at
          ) VALUES (?,?,?,?)
          ON CONFLICT(business_id,employee_id) DO UPDATE SET
            nickname=excluded.nickname,updated_at=excluded.updated_at''',
          [
            businessId,
            employeeId,
            value,
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          ],
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> decorate(
    String businessId,
    List<Map<String, dynamic>> employees,
  ) async {
    final names = await all(businessId);
    return [
      for (final employee in employees)
        {
          ...employee,
          if (names[employee['id']?.toString()] != null)
            'nickname': names[employee['id']?.toString()],
        },
    ];
  }

  static String displayName(Map<String, dynamic> employee) {
    final nickname = employee['nickname']?.toString().trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    return employee['name']?.toString().trim() ?? '';
  }
}
