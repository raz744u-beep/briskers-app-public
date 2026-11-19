import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/historical_task_recordkeeping.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late LocalPayrollRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db=BriskersLocalDatabase(NativeDatabase.memory());
    repo=LocalPayrollRepository(db,business:'shop',owner:true,deviceId:'owner');
    await repo.prepare();
    await repo.bindPaymentAuthority(writerDeviceId:'owner',assertVerifiedPairing:(){});
    for(var i=0;i<6;i++){
      final employee='employee-$i', job='job-$i';
      await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status) VALUES(?,'shop','owner','Repair','open')",[job]);
      await repo.saveEmployeeCompensation(employee:employee,name:'Mechanic $i',rate:3500,weeklyBase:false);
      await repo.createRecheck(operation:'work-$i',job:job,description:'Repair $i',
        employee:employee,name:'Mechanic $i',rate:3500,estimatedMinutes:120);
    }
  });
  tearDown(() => db.close());

  test('employee SQL scope agrees with full projection including historical mechanic overrides', () async {
    final all=await repo.work();
    final incoming=all.singleWhere((r)=>r['employee_id']=='employee-1');
    final outgoing=all.singleWhere((r)=>r['employee_id']=='employee-0');
    for(final row in [incoming,outgoing]){
      final job=row['job_id'] as String;
      await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,kind,document_date) VALUES(?,'shop',?,'invoice','2026-11-02')",['invoice-$job',job]);
      await db.customStatement("UPDATE regular_payroll_task_sources SET source_kind='invoice',invoice_id=? WHERE business_id='shop' AND task_id=?",['invoice-$job',row['task_id']]);
    }
    final notes=HistoricalTaskRecordkeeping(db);
    await notes.save('shop',incoming['id'] as String,'employee-0','Mechanic 0',180);
    await notes.save('shop',outgoing['id'] as String,'employee-2','Mechanic 2',120);
    final before=await repo.work();
    for(final employee in ['employee-0','employee-1','employee-2']){
      final scoped=await repo.work(employee:employee);
      expect(scoped,unorderedEquals(before.where((row)=>row['employee_id']==employee)));
    }
    final own=(await repo.work(employee:'employee-0')).single;
    expect(own['id'],incoming['id']);
    expect(own['recordkeeping_only'],true);
    expect(own['estimated_minutes'],180);
    expect(await repo.work(),before,reason:'Reading Work must not rewrite assignments or wages');
  });

  test('employee task-source read stays within the employee jobs and empty scope stays empty', () async {
    final work=await repo.work(employee:'employee-0');
    final jobs=work.map((r)=>r['job_id'] as String).toSet();
    final all=await repo.tasks();
    final scoped=await repo.tasks(jobs:jobs);
    expect(scoped,unorderedEquals(all.where((r)=>jobs.contains(r['job_id']))));
    expect(scoped,hasLength(1));
    expect(await repo.tasks(jobs:{}),isEmpty);
    final employees=await repo.employees();
    final own=await repo.localCompensation(employees,employee:'employee-0');
    expect(own.map((r)=>r['id']),['employee-0']);
    expect(await repo.employees(),employees);
  });

  test('profile reuses one authorized repository and scopes its Work reads', () {
    final source=File('lib/screens/payroll/owner_payroll_screen.dart').readAsStringSync();
    expect(source,contains('get _viewRepository => _taskEditRepository'));
    expect(source,contains('grant:_grant,employee:profileEmployee'));
    expect(source,contains('repository.tasks(jobs: profileEmployee==null?null:'));
    expect(source,contains('applyNov12OilSeparatorCarry()'));
    expect(source,contains('applyOwnerNov13WorkDates()'));
  });
}
