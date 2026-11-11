import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_mechanic_work_credit_repository.dart';
import 'package:briskers_app/services/verified_paid_labor.dart';
import 'package:briskers_app/services/job_task_summary.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('only matched complete payroll coverage projects completion without writes', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalPayrollRepository(db, business: 'shop', owner: true);
    await repo.prepare();
    final credits = LocalMechanicWorkCreditRepository(database: db);
    for (final id in [
      'full',
      'partial',
      'orphan',
      'wrong-person',
      'uncertain',
    ]) {
      await db.customStatement(
        "INSERT INTO regular_payroll_jobs(business_id,id,label) VALUES('shop',?,?)",
        [id, id],
      );
      await db.customStatement(
        "INSERT INTO regular_payroll_tasks(business_id,id,job_id,labor_id,description,planned) VALUES('shop',?,?,?,?,360)",
        [id, id, id, id],
      );
      await db.customStatement(
        "INSERT INTO regular_payroll_employees(business_id,id,name,rate) VALUES('shop',?,?,3500)",
        [id, id],
      );
      await db.customStatement(
        "INSERT INTO regular_payroll_portions(business_id,id,task_id,employee_id,state) VALUES('shop',?,?,?,'Open')",
        [id, id, id],
      );
      await db.customStatement(
        "INSERT INTO regular_payroll_task_sources VALUES('shop',?,?,?,'invoice',1)",
        [id, id, id],
      );
      await credits.createAssignment(
        businessId: 'shop',
        allocationId: id,
        jobId: id,
        laborLineId: id,
        taskId: id,
        employeeId: id,
        actualMinutes: 360,
        rateCents: 3500,
      );
      if (id == 'uncertain') continue;
      await db.customStatement(
        "INSERT INTO regular_payroll_work_coverage VALUES('shop',?,?,?,21000,'{}')",
        [id, id, id == 'partial' ? 120 : 360],
      );
      if (id == 'orphan') continue;
      await db.customStatement(
        "INSERT INTO regular_payroll_payments VALUES('shop',?,?,'2026-11-02','{}',21000,0,21000,'Cash','2026-11-06')",
        [id, id == 'wrong-person' ? 'other' : id],
      );
    }
    final before =
        (await db.customSelect('SELECT * FROM regular_payroll_portions').get())
            .map((r) => r.data)
            .toList();
    expect(await VerifiedPaidLabor(db).allocations('shop'), {'full'});
    expect(await VerifiedPaidLabor(db).allocations('other-shop'), isEmpty);
    expect((await JobTaskSummary(db).progress('shop', 'full')).done, 1);
    expect((await JobTaskSummary(db).progress('shop', 'partial')).done, 0);
    expect((await JobTaskSummary(db).progress('shop', 'uncertain')).done, 0);
    final work = await repo.work();
    expect(work.singleWhere((r) => r['id'] == 'full')['state'], 'Done');
    for (final id in ['partial', 'orphan', 'wrong-person', 'uncertain']) {
      expect(work.singleWhere((r) => r['id'] == id)['state'], 'Open');
    }
    expect(
      (await db.customSelect('SELECT * FROM regular_payroll_portions').get())
          .map((r) => r.data)
          .toList(),
      before,
    );
    expect(
      await db.customSelect('SELECT * FROM regular_payroll_payments').get(),
      hasLength(3),
    );
    await expectLater(
      repo.updateWork('full', 'In Progress', 360, '2026-11-10'),
      throwsA(
        predicate((e) => e.toString().contains('Paid work is immutable')),
      ),
    );
  });
}
