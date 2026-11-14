import 'package:briskers_app/services/payroll_lan_peer.dart';
import 'package:briskers_app/services/completed_task_history.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_job_work_date.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/payroll_owner_ledger.dart';
import 'package:briskers_app/services/local_invoice_task_store.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;late BriskersLocalDatabase db;late LocalPayrollRepository repo;
  void open(){db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/shop.sqlite')));repo=LocalPayrollRepository(db,business:'shop',owner:true,deviceId:'owner',assertLanWriter:()async{});}
  setUp(()async{SharedPreferences.setMockInitialValues({});await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);dir=await Directory.systemTemp.createTemp('bugs36');open();await repo.prepare();await LocalDocumentSqlStore.ensure(db);
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,customer_name,assigned_employee_id,created_at) VALUES('j56','shop','owner','Invoice','closed','J-56','Terrance Sanders','chris',123456)");
    await LocalJobWorkDate(db).save('shop','j56',DateTime(2026,11,13));
    for(final e in ['chris','kam']) {await repo.saveEmployeeCompensation(employee:e,name:e,rate:e=='chris'?4000:3500,weeklyBase:false);}
  });
  tearDown(()async{await db.close();await dir.delete(recursive:true);});
  Future<String> create(String op,{String treatment='unpaid',String status='Done'})async{
    await repo.saveServiceTask(operation:op,job:'j56',description:'Remove oil pan. Replace pip control valve.',mechanics:[{'employee':'chris','name':'Chris','minutes':300}],start:'2026-11-13',end:'2026-11-13',priority:'Normal',status:status,treatment:treatment);
    return jsonEncode(['j56','job',op]);
  }
  Future<void> edit(String id,String operation,{String employee='chris',String previous='chris',int minutes=300,String description='Remove oil pan. Replace pip control valve.',bool datesEdited=false})=>repo.saveServiceTask(operation:operation,task:id,job:'j56',description:description,mechanics:[{'employee':employee,'previous':previous,'name':employee,'minutes':minutes}],start:'2026-11-13',end:'2026-11-13',priority:'Normal',status:'Done',treatment:'preserve',datesEdited:datesEdited);
  Future<String> financial()async=>jsonEncode({for(final table in ['regular_payroll_payments','regular_payroll_work_coverage','regular_payroll_owner_prior_paid_v1','local_documents','local_document_details']) table:(await db.customSelect('SELECT * FROM $table').get()).map((r)=>r.data).toList()});
  Future<void> replicaCheck(Future<void> Function(LocalPayrollRepository,BriskersLocalDatabase) check)async{
    final copy=BriskersLocalDatabase(NativeDatabase.memory());
    try{await PayrollOwnerLedger(copy,'shop').mergeSnapshot(await PayrollOwnerLedger(db,'shop').export(),canonical:true);await check(LocalPayrollRepository(copy,business:'shop',owner:true),copy);}finally{await copy.close();}
  }
  test('priority-only edits preserve inherited dates, paid coverage and general reminders through restart',()async{
    final paid=await create('priority-paid',treatment:'paid');final automatic=await create('priority-auto');
    final general=await repo.saveGeneralTask(operation:'priority-general',employee:'kam',description:'Call customer',category:'Office',job:'j56',due:DateTime(2026,11,20,15),reminder:true);
    final before=await financial();final oldWork=await repo.work();final oldGeneral=(await repo.shopTasks()).single;
    for(final id in [paid,automatic]){await repo.setTaskPriority(id,'High');await repo.setTaskPriority(id,'High');}
    await repo.setTaskPriority('$general','Low',general:true);
    expect(await financial(),before);
    for(final old in oldWork){final row=(await repo.work()).singleWhere((r)=>r['id']==old['id']);for(final k in ['id','task_id','state','estimated_minutes','actual_minutes','paid','paid_minutes','completed_date','work_start_date','work_end_date']){expect(row[k],old[k],reason:k);}expect(row['priority'],'High');}
    expect((await db.customSelect('SELECT date_mode FROM regular_task_metadata').get()).every((r)=>r.data['date_mode']=='inherited'),isTrue);
    await db.close();open();expect((await repo.work()).every((r)=>r['priority']=='High'),isTrue);
    final restored=(await repo.shopTasks()).single;expect(restored['priority'],'Low');for(final k in ['id','employee_id','description','due_at','reminder_enabled','reminder_minutes','status']){expect(restored[k],oldGeneral[k],reason:k);}
    await LocalJobWorkDate(db).save('shop','j56',DateTime(2026,11,16));expect((await repo.work()).every((r)=>r['work_start_date']=='2026-11-16'),isTrue);expect(await financial(),before);
    await replicaCheck((r,d)async{expect((await r.work()).every((w)=>w['priority']=='High'&&w['work_start_date']=='2026-11-16'),isTrue);});
  });
  test('Done unpaid 5h transfers Chris to Kam offline, retries/restart/sync do not duplicate',()async{
    final id=await create('five');final other=await create('other',status:'Open');await repo.setEstimatedMinutes(other,'chris',1080);
    final original=(await repo.work()).singleWhere((r)=>r['task_id']==id);
    final finances=await financial();
    await edit(id,'transfer',employee:'kam');await edit(id,'transfer',employee:'kam');
    Future<void> check(LocalPayrollRepository r,BriskersLocalDatabase database)async{
      final rows=await r.work();expect(rows,hasLength(2));
      final chris=rows.singleWhere((r)=>r['employee_id']=='chris');expect(chris['state'],'Open');expect(chris['estimated_minutes'],1080);expect(chris['remaining_cents'],0);
      final kam=rows.singleWhere((r)=>r['employee_id']=='kam');expect(kam['task_id'],id);expect(kam['state'],'Done');expect(kam['actual_minutes'],300);expect(kam['remaining_cents'],17500);expect(kam['completed_date'],original['completed_date']);
      expect((await database.customSelect('SELECT assigned_employee_id,status FROM local_jobs').get()).single.data,{'assigned_employee_id':'chris','status':'closed'});
    }
    await check(repo,db);expect(await financial(),finances);await db.close();open();await check(repo,db);await replicaCheck(check);
    await edit(id,'back',employee:'chris',previous:'kam');expect((await repo.work()).where((r)=>r['employee_id']=='kam'),isEmpty);
    expect((await repo.work()).singleWhere((r)=>r['task_id']==id)['remaining_cents'],20000);
  });
  test('paired mechanic receives corrected date provenance and retired unpaid allocation once',()async{
    final id=await create('paired');
    final copy=BriskersLocalDatabase(NativeDatabase.memory());
    final mechanic=LocalPayrollRepository(copy,business:'shop',owner:false,pairedEmployee:'chris');
    try {
      final first=(await repo.assignmentSnapshots('chris')).single;
      await mechanic.applyLanChange(PayrollLanOperation.assignment,{...first,'assignment_revision':1},employee:'chris',assertLink:(){});
      await LocalJobWorkDate(db).save('shop','j56',DateTime(2026,11,16));
      await repo.editAllocation(task:id,previous:'chris',employee:'kam',name:'Kam',minutes:300);
      final snapshot=(await repo.assignmentSnapshots('chris')).single;
      await mechanic.applyLanChange(PayrollLanOperation.assignment,{...snapshot,'assignment_revision':2},employee:'chris',assertLink:(){});
      await mechanic.applyLanChange(PayrollLanOperation.assignment,{...snapshot,'assignment_revision':2},employee:'chris',assertLink:(){});
      expect((await copy.customSelect('SELECT start_date FROM regular_task_schedule_v1').get()).single.data['start_date'],'2026-11-16');
      expect((await copy.customSelect('SELECT date_mode FROM regular_task_metadata').get()).single.data['date_mode'],'inherited');
      expect((await copy.customSelect('SELECT actual_minutes FROM local_mechanic_work_credits_v1').get()).single.data['actual_minutes'],0);
      expect(await mechanic.mechanicWork(job:'j56',employee:'chris',assertSession:(){}),isEmpty);
    } finally {await copy.close();}
  });
  test('paid allocations reject changes, text-only edit retains identity, status, hours, wages',()async{
    final id=await create('paid',treatment:'paid');final before=(await repo.work()).single;final finances=await financial();
    await expectLater(edit(id,'bad',employee:'kam'),throwsStateError);
    await expectLater(edit(id,'hours',minutes:240),throwsStateError);
    await edit(id,'typo',description:'Remove oil pan. Replace oil control valve.');
    final after=(await repo.work()).single;for(final k in ['id','task_id','employee_id','state','actual_minutes','estimated_minutes','paid','completed_date','rate_cents']) {expect(after[k],before[k],reason:k);}
    expect(after['description'],'Remove oil pan. Replace oil control valve.');expect(await financial(),finances);
  });
  test('partially paid allocation cannot transfer or change hours; remaining wages and receipt persist',()async{
    final id=await create('partial');await repo.bindPaymentAuthority(writerDeviceId:'owner',assertVerifiedPairing:(){});
    final row=(await repo.work()).single;
    await repo.verify(operation:'payment',employee:'chris',week:'2026-11-09',date:'2026-11-13',method:'Cash',selected:[{...row,'pay_minutes':60}],base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:0,confirmedNet:4000);
    final before=await financial();await expectLater(edit(id,'transfer',employee:'kam'),throwsStateError);await expectLater(edit(id,'hours',minutes:240),throwsStateError);
    expect(await financial(),before);expect((await repo.work()).single['remaining_minutes'],240);
  });
  test('inherited dates move; same-date manual override and legacy dates stay; non-date edits do not break inheritance',()async{
    final a=await create('automatic'),b=await create('manual'),c=await create('legacy');
    await edit(a,'text',description:'Correct task text');await edit(b,'manual-date',datesEdited:true);
    await db.customStatement('DELETE FROM regular_task_metadata WHERE task_id=?',[c]);
    final credits=jsonEncode((await db.customSelect('SELECT * FROM local_mechanic_work_credits_v1').get()).map((r)=>r.data).toList());final finances=await financial();
    await LocalJobWorkDate(db).save('shop','j56',DateTime(2026,11,16));
    Future<void> check(LocalPayrollRepository r,BriskersLocalDatabase database)async{
      final rows=await r.work();for(final row in rows){expect(row['work_start_date'],row['task_id']==a?'2026-11-16':'2026-11-13');expect(row['work_end_date'],row['work_start_date']);expect(row['completed_date'],'2026-11-13');expect(row['state'],'Done');}
    }
    await check(repo,db);expect(await financial(),finances);expect(jsonEncode((await db.customSelect('SELECT * FROM local_mechanic_work_credits_v1').get()).map((r)=>r.data).toList()),credits);
    await db.close();open();await check(repo,db);await replicaCheck(check);
  });
  test('invoice task text override survives invoice replay without changing original line or historical wages',()async{
    final detail=<String,dynamic>{'id':'6376','job_id':'j56','kind':'invoice','status':'closed','lines':[{'id':'line','line_kind':'labor','description':'Original invoice description','quantity':5}]};
    await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,kind,document_number,document_date,status) VALUES('6376','shop','j56','invoice','6376','2026-11-06','closed')");
    await LocalInvoiceTaskStore(db).save('shop','6376',detail);
    final task=(await repo.tasks()).single;final id=task['id'] as String;
    await repo.saveServiceTask(operation:'invoice-text',task:id,job:'j56',description:'Corrected task only',mechanics:[],start:'2026-11-13',end:'2026-11-13',priority:'Normal',status:'Done',treatment:'preserve');
    await LocalInvoiceTaskStore(db).save('shop','6376',detail);
    expect((await repo.tasks()).single['description'],'Corrected task only');expect((detail['lines'] as List).single['description'],'Original invoice description');
    expect(await db.customSelect('SELECT * FROM regular_payroll_payments').get(),isEmpty);
  });
  test('customer history only calls a repair completed when every active assignment is Done',()async{
    final id=await create('history');
    expect(await CompletedTaskHistory(db).read('shop',job:'j56',wholeTasksOnly:true),hasLength(1));
    await repo.assignTask(id,'kam','Kam');await repo.setEstimatedMinutes(id,'kam',120);
    expect(await CompletedTaskHistory(db).read('shop',job:'j56'),hasLength(1));
    expect(await CompletedTaskHistory(db).read('shop',job:'j56',wholeTasksOnly:true),isEmpty);
  });
  test('text edit on mixed Done/Open allocations does not complete or credit the unfinished share',()async{
    final id=await create('mixed');await repo.assignTask(id,'kam','Kam');await repo.setEstimatedMinutes(id,'kam',120);
    final before=await repo.work();
    await repo.saveServiceTask(operation:'mixed-text',task:id,job:'j56',description:'Correct mixed task text',mechanics:[{'employee':'chris','previous':'chris','name':'Chris','minutes':300},{'employee':'kam','previous':'kam','name':'Kam','minutes':120}],start:'2026-11-13',end:'2026-11-13',priority:'Normal',status:'In Progress',treatment:'preserve');
    final after=await repo.work();for(final row in after){final old=before.singleWhere((r)=>r['id']==row['id']);for(final key in ['state','actual_minutes','remaining_minutes','completed_date']){expect(row[key],old[key]);}}
  });
  test('adding a second mechanic to Done preserves completion date and splits unpaid hours',()async{
    final id=await create('split');await repo.saveServiceTask(operation:'split-edit',task:id,job:'j56',description:'Same work',mechanics:[{'employee':'chris','previous':'chris','name':'Chris','minutes':180},{'employee':'kam','name':'Kam','minutes':120}],start:'2026-11-13',end:'2026-11-13',priority:'Normal',status:'Done',treatment:'preserve');
    final rows=await repo.work();expect(rows,hasLength(2));expect(rows.every((r)=>r['state']=='Done'&&r['completed_date']=='2026-11-13'),isTrue);expect(rows.fold<int>(0,(n,r)=>n+(r['actual_minutes'] as int)),300);
  });
}
