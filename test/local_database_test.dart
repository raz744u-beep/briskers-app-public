import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';

void main() {
  test('local Briskers database opens and creates schema', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());

    final row =
        await database.customSelect('SELECT 1 AS ready').getSingle();

    expect(row.read<int>('ready'), 1);

    final tables = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ).get();
    final names = tables.map((row) => row.read<String>('name')).toSet();
    expect(names, contains('local_finding_photos'));
    expect(names, contains('local_job_statuses'));
    expect(names, contains('local_customers'));
    expect(names, contains('local_vehicles'));
    expect(names, contains('local_customer_vehicles'));

    final syncColumns = await database.customSelect(
      'PRAGMA table_info(local_sync_states)',
    ).get();
    final syncColumnNames = syncColumns
        .map((row) => row.read<String>('name'))
        .toSet();
    expect(syncColumnNames, contains('metadata_json'));

    await database.close();
  });
}
