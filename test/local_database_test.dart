import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';

void main() {
  test('local Briskers database opens and creates schema', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());

    final row =
        await database.customSelect('SELECT 1 AS ready').getSingle();

    expect(row.read<int>('ready'), 1);
    await database.close();
  });
}
