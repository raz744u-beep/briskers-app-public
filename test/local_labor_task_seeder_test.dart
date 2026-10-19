import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_job_task_store.dart';
import 'package:briskers_app/local/local_labor_task_seeder.dart';

void main() {
  test('J12 labor seeds only once and does not change invoice data', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final seeder = LocalLaborTaskSeeder(LocalJobTaskStore(db));
      final lines = <Map<String, dynamic>>[
        {'id':'part-1','name':'Oil pan','line_kind':'item','quantity':1},
        {'id':'labor-1','name':'Labor','description':'Replace oil pan','line_kind':'item','quantity':2},
        {'id':'labor-2','name':'Labor','description':'Replace control arms','line_kind':'labor','quantity':5.2},
      ];
      expect(await seeder.seed(businessId:'shop-1',jobId:'job-12',savedLines:lines), 2);
      expect(await seeder.seed(businessId:'shop-1',jobId:'job-12',savedLines:lines), 0);
      final tasks = await LocalJobTaskStore(db).listForJob('shop-1','job-12');
      expect(tasks, hasLength(2));
      expect(tasks.first['payroll_hours'], 2);
      expect(tasks.last['payroll_hours'], 5.2);
      expect(lines[1]['quantity'], 2);
    } finally {
      await db.close();
    }
  });
}
