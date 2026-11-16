import 'package:briskers_app/services/payroll_owner_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_mechanic_work_credit_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>SharedPreferences.setMockInitialValues({}));

  test('Owner Already Paid settles one immutable allocation, no payroll post',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalPayrollRepository(db,business:'shop',owner:true);
    await repo.prepare();
    await db.customStatement(
      "INSERT INTO regular_payroll_jobs(business_id,id,label) VALUES('shop','job','J-test')");
    await db.customStatement(
      "INSERT INTO regular_payroll_tasks(business_id,id,job_id,labor_id,description,planned) "
      "VALUES('shop','task','job','line','Historical work',70)");
    await db.customStatement(
      "INSERT INTO regular_payroll_employees(business_id,id,name,rate,base_enabled) "
      "VALUES('shop','emp','Kam',3500,0)");
    await db.customStatement(
      "INSERT INTO regular_payroll_portions(business_id,id,task_id,employee_id,state,completed_date) "
      "VALUES('shop','alloc','task','emp','Done','2026-11-06')");
    await db.customStatement(
      "INSERT INTO regular_payroll_estimates(business_id,task_id,employee_id,minutes) "
      "VALUES('shop','task','emp',70)");
    final credits = LocalMechanicWorkCreditRepository(database:db);
    await credits.createAssignment(
      businessId:'shop',allocationId:'alloc',jobId:'job',
      laborLineId:'line',taskId:'task',employeeId:'emp',
      actualMinutes:70,rateCents:3500,
    );
    await credits.recordWork(
      businessId:'shop',allocationId:'alloc',employeeId:'emp',
      expectedRevision:1,actualMinutes:70,completed:true,
    );

    await repo.confirmHistoricalAlreadyPaid('alloc');
    await repo.confirmHistoricalAlreadyPaid('alloc'); // idempotent
    final rows = await repo.work(employee:'emp');
    expect(rows,hasLength(1));
    expect(rows.single['state'],'Done');
    expect(rows.single['pay_status'],'Already Paid');
    expect(rows.single['owner_prior_paid'],1);
    expect(rows.single['paid'],1);
    expect(rows.single['remaining_minutes'],0);
    expect(rows.single['paid_minutes'],70);

    final payments = await db.customSelect(
      'SELECT operation_id FROM regular_payroll_payments').get();
    final coverage = await db.customSelect(
      'SELECT credit_id FROM regular_payroll_work_coverage').get();
    expect(payments,isEmpty); // No invented payroll expense.
    expect(coverage,isEmpty); // No fabricated payment coverage.
    final audits = await db.customSelect(
      "SELECT id FROM regular_payroll_audit "
      "WHERE event='owner_confirmed_historical_already_paid'").get();
    expect(audits,hasLength(1));
    final second=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(second.close);
    final transferred=await PayrollOwnerLedger(db,'shop').export();
    await PayrollOwnerLedger(second,'shop').mergeSnapshot(transferred,canonical:true);
    await PayrollOwnerLedger(second,'shop').mergeSnapshot(transferred,canonical:true);
    final otherRepo=LocalPayrollRepository(second,business:'shop',owner:true);
    final transferredWork=await otherRepo.work(employee:'emp');
    expect(transferredWork.single['pay_status'],'Already Paid');
    expect(transferredWork.single['remaining_minutes'],0);
    expect(await second.customSelect('SELECT * FROM regular_payroll_payments').get(),isEmpty);


    await expectLater(
      repo.setEstimatedMinutes('task','emp',120,reviseCompletedUnpaid:true),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repo.updateWork('alloc','In Progress',120,'2026-11-10'),
      throwsA(isA<StateError>()),
    );
  });
}
