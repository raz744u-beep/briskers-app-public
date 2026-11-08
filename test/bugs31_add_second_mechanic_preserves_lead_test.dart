import 'dart:io';
import 'package:briskers_app/services/job_task_summary.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_task_assignment_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Assign / split never retires the existing inherited mechanic', () async {
    // This is the regression for an untouched Main Mechanic allocation.
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      LocalDocumentDetailCache.sqliteWritesEnabled=false;
    });
    await LocalDocumentDetailCache.initialize(db);
    final payroll=LocalPayrollRepository(db,business:'shop',owner:true);
    await payroll.prepare();
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) "
      "VALUES('job','shop','owner','Supercharger replacement','open','J-TEST')");
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,kind,document_number) "
      "VALUES('invoice','shop','job','invoice','6365')");
    await LocalDocumentDetailCache(database:db).save('shop','invoice',{
      'id':'invoice','kind':'invoice','job_id':'job',
      'lines':[{'id':'labor','name':'Labor','line_kind':'labor',
        'description':'Remove and install supercharger','quantity':8.5,
        'unit_price':100}],
    });
    await payroll.saveEmployeeCompensation(
      employee:'chris',name:'Chris',rate:4000,weeklyBase:false);
    await payroll.saveEmployeeCompensation(
      employee:'kam',name:'Kam',rate:4200,weeklyBase:false);
    await payroll.setMainMechanic('job','chris','Chris');
    final before=await payroll.work();
    expect(before.where((x)=>x['employee_id']=='chris'),hasLength(1));
    expect(before.single['estimated_minutes'],510);

    // Same operation as the UI Add/split path: link the new employee,
    // register new labor and mark only the NEW mechanic explicit.
    final links=LocalTaskAssignmentStore(db);
    await links.linkEmployee('shop','job','kam','Kam');
    await payroll.registerAssignedLabor(
      jobId:'job',invoiceId:'invoice',lineId:'labor',
      employeeId:'kam',employeeName:'Kam',rateCents:4200);
    final task=(await payroll.tasks()).singleWhere(
      (r)=>r['source_line_id']=='labor')['id'] as String;
    await links.allocate('shop',task,'kam',inherited:false);

    final after=await payroll.work();
    final byEmployee={for(final row in after) row['employee_id']:row};
    expect(byEmployee.keys.toSet(),{'chris','kam'},
      reason:'Adding Kam must not remove Chris');
    expect(byEmployee['chris']!['estimated_minutes'],510);
    expect(byEmployee['kam']!['estimated_minutes'],0,
      reason:'Second mechanic starts with 0 planned hours, not a duplicate 8.5');
    expect(after.every((row)=>row['actual_minutes']==0),isTrue);

    await payroll.setEstimatedMinutes(task,'chris',540);
    await payroll.setEstimatedMinutes(task,'kam',120);
    final split=await payroll.work();
    expect(split.map((row)=>row['estimated_minutes']).toSet(),{540,120});
    await expectLater(payroll.editAllocation(task:task,previous:'chris',employee:'kam',name:'Kam',minutes:300),throwsStateError);
    await payroll.editAllocation(task:task,previous:'kam',employee:'third',name:'Third',minutes:90);
    final reassigned=await payroll.work();
    expect(reassigned.where((r)=>r['employee_id']=='third').single['estimated_minutes'],90);
    expect(reassigned.where((r)=>r['employee_id']=='chris').single['estimated_minutes'],540);
    await payroll.addShopTask('chris','Clean lift','General',job:'job');
    await payroll.addShopTask('chris','Sweep shop','General');
    final shopTasks=await payroll.shopTasks('chris');
    expect(shopTasks.singleWhere((r)=>r['description']=='Clean lift')['job_id'],'job');
    expect(shopTasks.singleWhere((r)=>r['description']=='Sweep shop')['job_id'],isNull);
    final summary=JobTaskSummary(db);
    expect((await summary.progress('shop','job')).total,2);
    expect((await summary.progress('shop','job')).done,0);
    expect((await summary.hours('shop',['job']))['job']!.values.toSet(),{540,90});
    final third=reassigned.singleWhere((r)=>r['employee_id']=='third');
    await payroll.recordAllocatedTime(third['id'] as String,'Done',90,90,'2026-11-08');
    expect((await summary.progress('shop','job')).done,0);
    final chris=reassigned.singleWhere((r)=>r['employee_id']=='chris');
    await payroll.recordAllocatedTime(chris['id'] as String,'Done',540,540,'2026-11-08');
    expect((await summary.progress('shop','job')).done,1);
    await expectLater(payroll.removeOpenAllocation(task,'chris'),throwsStateError);
    await db.customStatement("UPDATE local_documents SET document_date='2026-11-06' WHERE id='invoice'");
    expect((await payroll.work()).every((r)=>r['archived_labor']==1),isTrue);
    await payroll.reviewUnpaidCarry('third',third['id'] as String);
    expect((await payroll.work(employee:'third')).single['archived_labor'],0);
    expect((await payroll.work(employee:'chris')).single['archived_labor'],1);
    final invoice=await LocalDocumentDetailCache(database:db).load('shop','invoice');
    expect((invoice!['lines'] as List).single['quantity'],8.5);
  });

  test('Job labor Assign / split is additive in source, never replace', () {
    final screen=File('lib/screens/payroll/owner_payroll_screen.dart')
      .readAsStringSync();
    final start=screen.indexOf('Future<void> _assign(');
    final end=screen.indexOf('Future<void> _recordTaskProgress(',start);
    expect(start,greaterThanOrEqualTo(0));
    expect(end,greaterThan(start));
    final handler=screen.substring(start,end);
    expect(handler,contains("title: const Text('Add mechanic to invoice labor')"));
    expect(handler,isNot(contains('assignments.retireInherited(')));
    expect(handler,contains('await assignments.allocate('));
    expect(handler,contains('inherited: false'));
  });
}
