import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_task_schedule.dart';
import 'package:briskers_app/services/payroll_owner_ledger.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;late BriskersLocalDatabase db;late LocalPayrollRepository repo;
  void open(){db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/shop.sqlite')));repo=LocalPayrollRepository(db,business:'shop',owner:true,deviceId:'owner',assertLanWriter:()async{});}
  setUp(()async{SharedPreferences.setMockInitialValues({});dir=await Directory.systemTemp.createTemp('nov13-local');open();await repo.prepare();await repo.bindPaymentAuthority(writerDeviceId:'owner',assertVerifiedPairing:(){});
    for(final n in [40,48,49,54]) {
      await db.customStatement('INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,customer_name) VALUES(?,?,?,?,?,?,?)',['j$n','shop','owner','Repair $n',n==54?'in_progress':'closed','J-$n',n==40?'Gloria Johnson':n==54?'Nathan Hogue':'Historical customer']);
    }
  });
  tearDown(()async{await db.close();await dir.delete(recursive:true);});
  Future<void> task(String op,int job,String description,int minutes,{String status='Done',String treatment='unpaid',String start='2026-11-09',String end='2026-11-10'})=>repo.saveServiceTask(operation:op,job:'j$job',description:description,mechanics:[{'employee':'chris','name':'Chris','rate':4000,'minutes':minutes}],start:start,end:end,priority:'Normal',status:status,treatment:treatment);
  Future<String> finances() async=>jsonEncode({for(final table in ['regular_payroll_payments','regular_payroll_work_coverage','regular_payroll_owner_prior_paid_v1','local_mechanic_work_credits_v1','regular_payroll_portions','regular_payroll_estimates','local_jobs'])table:(await db.customSelect('SELECT * FROM $table').get()).map((r)=>r.data).toList()});
  test('closed-job date edits preserve paid records, move weekly review, survive restart and LAN transfer',()async{
    await task('paid48',48,'Water pump',450,treatment:'paid');await task('paid49',49,'Paid repair',90,treatment:'paid');
    final before=await finances();final rows=await repo.work();
    // Synthetic dates test the controls; the app never chooses actual J-48/J-49 dates.
    await repo.saveTaskSchedule(rows[0]['task_id'] as String,'2026-11-02','2026-11-03','High');
    await repo.saveTaskSchedule(rows[1]['task_id'] as String,'2026-11-05','2026-11-06','Low');
    expect(await finances(),before);
    await db.close();open();
    final restored=await repo.work();
    expect(restored.where((r)=>LocalTaskSchedule.inWeek(r,DateTime(2026,11,9))),isEmpty);
    expect(restored.where((r)=>LocalTaskSchedule.inWeek(r,DateTime(2026,11,2))),hasLength(2));
    expect(restored.every((r)=>r['state']=='Done'&&r['paid']==1&&r['remaining_minutes']==0),isTrue);
    expect(await finances(),before);
    final replica=BriskersLocalDatabase(NativeDatabase.memory());
    try{await PayrollOwnerLedger(replica,'shop').mergeSnapshot(await PayrollOwnerLedger(db,'shop').export(),canonical:true);final other=await LocalPayrollRepository(replica,business:'shop',owner:true).work();expect(other.map((r)=>r['work_start_date']).toSet(),{'2026-11-02','2026-11-05'});expect(other.every((r)=>r['paid']==1),isTrue);}finally{await replica.close();}
  });
  test('Chris acceptance: 12 unpaid completed hours, 480 gross, historical paid work and Not Started excluded, one payment',()async{
    await task('paid48',48,'Water pump',390,treatment:'paid',start:'2026-11-02',end:'2026-11-06');
    await task('paid48-plugs',48,'Engine block plugs',30,treatment:'paid',start:'2026-11-02',end:'2026-11-06');
    await task('paid49',49,'Battery DME',120,treatment:'paid',start:'2026-11-02',end:'2026-11-06');
    await task('new-oil',40,'Oil Separator',600);
    await task('oil-change',54,'Oil Change',60);
    await task('brake',54,'Brake Flush',60);
    await task('filter',54,'Replace filters',60,status:'Open');
    await task('new-oil',40,'Oil Separator',600); // retry same operation
    final all=await repo.work(employee:'chris');expect(all,hasLength(7));
    final payable=all.where((r)=>r['state']=='Done'&&r['paid']==0).toList();
    expect(payable.fold<int>(0,(n,r)=>n+(r['remaining_minutes'] as int)),720);
    expect(payable.fold<int>(0,(n,r)=>n+(r['gross_cents'] as int)),48000);
    Future<bool> pay(String op)=>repo.verify(operation:op,employee:'chris',week:'2026-11-09',date:'2026-11-13',method:'Cash',selected:payable,base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:0,confirmedNet:48000);
    expect(await pay('weekly'),isTrue);expect(await pay('weekly'),isFalse);await expectLater(pay('duplicate'),throwsStateError);
    expect(await db.customSelect('SELECT * FROM regular_payroll_payments').get(),hasLength(1));
    final after=await repo.work();expect(after.singleWhere((r)=>r['description']=='Replace filters')['state'],'Open');expect(after.where((r)=>r['owner_prior_paid']==1),hasLength(3));
  });
  test('invalid dates roll back; priority and overdue never replace Done',()async{
    await task('open',54,'Open repair',60,status:'In Progress',start:'2026-11-02',end:'2026-11-03');final r=(await repo.work()).single;
    expect(LocalTaskSchedule.overdue(r,now:DateTime(2026,11,13)),isTrue);
    expect(LocalTaskSchedule.overdue({...r,'state':'Done'},now:DateTime(2026,11,13)),isFalse);
    await expectLater(repo.saveTaskSchedule(r['task_id'] as String,'2026-11-11','2026-11-09','High'),throwsArgumentError);
    expect((await repo.work()).single['work_end_date'],'2026-11-03');
    expect(LocalTaskSchedule.parse('2026-02-31'),isNull);
  });
  test('General Task one-operation save and edits retain identity, status, due time and reminder across restart',()async{
    final due=DateTime(2026,11,20,15,30);
    Future<int> save()=>repo.saveGeneralTask(operation:'general',employee:'chris',description:'Order part',category:'General',job:'j40',due:due,reminder:true,reminderMinutes:15);
    final id=await save();expect(await save(),id);await repo.setShopTaskStatus('chris',id,'done');
    await repo.saveGeneralTask(operation:'edit',id:id,previousEmployee:'chris',employee:'chris',description:'Order correct part',category:'General',job:'j40',due:due.add(const Duration(days:1)),reminder:false);
    await db.close();open();final rows=await repo.shopTasks();expect(rows,hasLength(1));expect(rows.single['id'],id);expect(rows.single['status'],'done');expect(rows.single['reminder_enabled'],0);expect(rows.single['due_at'],due.add(const Duration(days:1)).millisecondsSinceEpoch);
    expect(await db.customSelect('SELECT * FROM regular_payroll_payments').get(),isEmpty);
  });
}
