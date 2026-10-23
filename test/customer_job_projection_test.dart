import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_repository.dart';

void main() {
  late BriskersLocalDatabase db;
  setUp(() => db = BriskersLocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('customer history preserves mechanic, scope and hours without network', () async {
    for (final (id, shop, customer) in [('job', 'shop', 'customer'),
      ('other-customer', 'shop', 'other'), ('other-shop', 'other', 'customer')]) {
      await db.customStatement(
        'INSERT INTO local_jobs(id,business_id,customer_id,access_scope,title,status,'
        'assigned_employee_id,assigned_employee_name,assigned_position,planned_hours) '
        'VALUES(?,?,?,?,?,?,?,?,?,?)',
        [id, shop, customer, 'all', 'Saved repair', 'completed',
         'employee', 'Kamerron', 'Mechanic', 2.0]);
    }
    final jobs = await LocalJobRepository(database: db).forCustomer('shop', 'customer');
    expect(jobs, hasLength(1));
    expect(jobs.single['id'], 'job');
    expect(jobs.single['assigned_employee'], 'Kamerron');
    expect(jobs.single['assigned_employee_id'], 'employee');
    expect(jobs.single['planned_hours'], 2);
    expect((await db.customSelect('SELECT COUNT(*) AS n FROM local_jobs').get()).single.read<int>('n'), 3);
  });
}
