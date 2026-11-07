import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invoice 3.6 labor hours inherit Main Mechanic even with pay unset',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
    });
    final repo = LocalPayrollRepository(db, business: 'shop', owner: true);
    await repo.prepare();
    await LocalDocumentDetailCache.initialize(db);
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,"
      "assigned_employee_id,assigned_employee_name) "
      "VALUES('job','shop','owner','Synthetic suspension repair','open',"
      "'J-DEFAULT','chris','Chris')",
    );
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,kind,document_number) "
      "VALUES('invoice','shop','job','invoice','TEST-DEFAULT')",
    );
    await LocalDocumentDetailCache(database: db).save('shop', 'invoice', {
      'id': 'invoice', 'kind': 'invoice', 'job_id': 'job',
      'lines': [
        {'id': 'labor', 'line_kind': 'labor',
         'description': 'Replace front air struts', 'quantity': 3.6,
         'unit_price': 150},
      ],
    });
    final credits = await repo.work(employee: 'chris');
    expect(credits, hasLength(1));
    expect(credits.single['estimated_minutes'], 216);
    expect(credits.single['actual_minutes'], 0);
    expect(credits.single['paid_minutes'], 0);
    final staff = await repo.employees();
    expect(staff.singleWhere((e) => e['id'] == 'chris')['rate'], 0,
      reason: 'Unconfigured pay must not block assignment or invent wages');
    await repo.setEstimatedMinutes(
      credits.single['task_id'] as String, 'chris', 150);
    final edited = (await repo.work(employee: 'chris')).single;
    expect(edited['estimated_minutes'], 150,
      reason: 'Owner can override mechanic planning without changing invoice');
    final saved = await LocalDocumentDetailCache(database: db)
        .load('shop', 'invoice');
    expect((saved!['lines'] as List).single['quantity'], 3.6);
  });
}
