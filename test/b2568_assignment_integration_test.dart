import 'package:drift/drift.dart' show Variable;
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'dart:convert';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:briskers_app/services/payroll_owner_lease.dart';
import 'package:briskers_app/services/completed_task_history.dart';

class _Unused implements OwnerEnrollmentStore {
  @override Future<String?> read() async=>null;
  @override Future<void> write(String value) async{}
  @override Future<void> clear() async{}
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('synthetic J-44 invoice 6363: main inheritance, manual/split allocations, actual vs credit, payment and restart',()async{
    SharedPreferences.setMockInitialValues({});
    final directory=await Directory.systemTemp.createTemp('briskers429');
    final file=File('${directory.path}/shop.sqlite');
    var db=BriskersLocalDatabase(NativeDatabase(file));
    addTearDown(()async{await db.close();LocalDocumentDetailCache.sqliteWritesEnabled=false;await directory.delete(recursive:true);});
    const who=OwnerSessionIdentity('owner','synthetic');
    final auth=LocalOwnerAuthorization(store:_Unused(),currentIdentity:()=>who,
      verifyOwner:(_)async=>throw StateError('Internet must not be used'),authenticateDevice:()async=>true,
      verifyLocalOwner:(s)async=>VerifiedOwnerEnrollment(who,s));
    final grant=await auth.authorizeLocal('shop');
    final identity=await PayrollLanIdentity.fromSeed(List.filled(32,7));
    final secure=<String,String>{};
    final lease=PayrollOwnerLease(identity:identity,business:'shop',anchor:identity.deviceId,
      read:(k)async=>secure[k],write:(k,v)async{secure[k]=v;});
    await lease.migrate(grant);
    LocalPayrollRepository ledger()=>LocalPayrollRepository(db,business:'shop',owner:true,deviceId:identity.deviceId,
      ownerProof:null,assertOwnerGrant:()=>grant.assertValid('shop','owner'));
    var repo=ledger();
    await repo.prepare();
    await LocalDocumentDetailCache.initialize(db);
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,customer_id,vehicle_label) VALUES('job','shop','owner','Turbo repair','open','J-44','customer','2021 Synthetic SUV')");
    await db.customStatement("INSERT INTO local_documents(document_date,id,business_id,job_id,kind,document_number) VALUES('2026-11-09','invoice','shop','job','invoice','6363')");
    for(final e in ['a','b','c']){await repo.saveEmployeeCompensation(employee:e,name:'Mechanic $e',rate:4000,weeklyBase:false);}
    Map<String,dynamic> invoice({num quantity=6,bool more=false})=>{'id':'invoice','kind':'invoice','job_id':'job','total_amount':quantity*100,
      'lines':[{'id':'turbo','line_kind':'labor','description':'Replace turbocharger and gaskets','quantity':quantity,'unit_price':100},
        {'id':'second','line_kind':'labor','description':'Diagnostic','quantity':1},
        {'id':'inherited','line_kind':'labor','description':'Test drive','quantity':1},
        if(more){'id':'later','line_kind':'labor','description':'New labor','quantity':2}]};
    await LocalDocumentDetailCache(database:db).save('shop','invoice',invoice());
    await repo.setMainMechanic('job','a','Mechanic a');
    expect(await repo.work(),hasLength(3));
    final tasks=await repo.tasks();
    String task(String line)=>tasks.singleWhere((r)=>r['source_line_id']==line)['id'] as String;
    await repo.assignTask(task('turbo'),'b','Mechanic b',rate:4000);
    // Explicitly keep A and add B to split a single canonical task.
    await repo.assignTask(task('second'),'a','Mechanic a',rate:4000);
    await repo.assignTask(task('second'),'b','Mechanic b',rate:4000);
    await repo.setEstimatedMinutes(task('second'),'a',150);
    await repo.setEstimatedMinutes(task('second'),'b',60);
    await repo.setMainMechanic('job','c','Mechanic c');
    var work=await repo.work();
    expect(work.where((r)=>r['source_line_id']=='turbo').single['employee_id'],'b');
    expect(work.where((r)=>r['source_line_id']=='second').map((r)=>r['employee_id']).toSet(),{'a','b'});
    expect(work.where((r)=>r['source_line_id']=='inherited').single['employee_id'],'c');
    await LocalDocumentDetailCache(database:db).save('shop','invoice',invoice(quantity:7,more:true));
    await LocalDocumentDetailCache(database:db).save('shop','invoice',invoice(quantity:7,more:true));
    work=await repo.work();
    expect(work.where((r)=>r['source_line_id']=='later').single['employee_id'],'c');
    expect(work.where((r)=>r['source_line_id']=='second'&&r['employee_id']=='a').single['estimated_minutes'],150);
    final turbo=work.singleWhere((r)=>r['source_line_id']=='turbo');
    expect(turbo['estimated_minutes'],360);
    await repo.updateWork(turbo['id'] as String,'In Progress',0,'2026-11-05');
    await repo.recordAllocatedTime(turbo['id'] as String,'Done',120,180,'2026-11-05');
    final earned=(await repo.work(employee:'b')).singleWhere((r)=>r['source_line_id']=='turbo');
    expect(earned['recorded_actual_minutes'],120);expect(earned['actual_minutes'],180);
    var payer=LocalPayrollRepository(db,business:'shop',owner:true,deviceId:identity.deviceId,ownerProof:await lease.proof(grant));
    final selected=[{...earned,'pay_minutes':60}];
    expect(await payer.verify(operation:'first',employee:'b',week:'2026-11-02',date:'2026-11-05',method:'Cash',selected:selected,
      base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:0,confirmedNet:4000),isTrue);
    final history=await CompletedTaskHistory(db).read('shop',customer:'customer');
    expect(history.single['actual_minutes'],120);expect(history.single['task_id'],task('turbo'));
    await expectLater(repo.recordAllocatedTime(turbo['id'] as String,'Done',999,999,'2026-11-05'),throwsStateError);
    await db.close();db=BriskersLocalDatabase(NativeDatabase(file));repo=ledger();
    payer=LocalPayrollRepository(db,business:'shop',owner:true,deviceId:identity.deviceId,ownerProof:await lease.proof(grant));
    expect(await payer.verify(operation:'first',employee:'b',week:'2026-11-02',date:'2026-11-05',method:'Cash',selected:selected,
      base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:0,confirmedNet:4000),isFalse);
    final remaining=(await repo.work(employee:'b')).singleWhere((r)=>r['source_line_id']=='turbo');
    expect(remaining['remaining_minutes'],120);expect(remaining['remaining_cents'],8000);
    expect(await repo.history('a'),isEmpty);expect(await repo.history('b'),hasLength(1));
    final document=await LocalDocumentDetailCache(database:db).load('shop','invoice');
    expect(document!['total_amount'],700);expect((document['lines'] as List).first['quantity'],7);
    expect((await db.customSelect("SELECT status FROM local_jobs WHERE id='job'").getSingle()).data['status'],'open');
    await repo.addShopTask('a','Clean desk','General');
    expect(await CompletedTaskHistory(db).read('shop',job:'job'),hasLength(1));
    await expectLater(LocalPayrollRepository(db,business:'shop',owner:false).setMainMechanic('job','b','B'),throwsStateError);
    // A disconnected mechanic's original inherited allocation must not vanish
    // when its main mechanic changes before their progress is delivered.
    final old=(await db.customSelect("SELECT allocation_id,revision FROM local_mechanic_work_credits_v1 WHERE business_id='shop' AND employee_id='a' AND task_id=?",
      variables:[Variable(task('inherited'))]).getSingle()).data;
    for(final state in ['In Progress','Done']){
      final row=(await db.customSelect('SELECT revision FROM local_mechanic_work_credits_v1 WHERE allocation_id=?',variables:[Variable(old['allocation_id'] as String)]).getSingle()).data;
      await repo.updateMechanicWork(job:'job',employee:'a',id:old['allocation_id'] as String,state:state,minutes:60,date:'2026-11-05',
        expectedRevision:row['revision'] as int,assertSession:()=>grant.assertValid('shop','owner'));
    }
    final changed=(await repo.work(employee:'a')).singleWhere((r)=>r['id']==old['allocation_id']);
    expect(changed['state'],'Done');expect(changed['assignment_conflict'],1);
    await expectLater(payer.verify(operation:'conflict',employee:'a',week:'2026-11-02',date:'2026-11-05',method:'Cash',selected:[changed],
      base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:0,confirmedNet:4000),throwsStateError);
    expect((await CompletedTaskHistory(db).read('shop',job:'job')).where((r)=>r['employee_id']=='a'),isEmpty);
    await repo.acceptChangedAssignment(old['allocation_id'] as String);
    expect((await repo.work(employee:'a')).singleWhere((r)=>r['id']==old['allocation_id'])['assignment_conflict'],0);
    expect((await CompletedTaskHistory(db).read('shop',job:'job')).where((r)=>r['employee_id']=='a'),hasLength(1));
    expect(await payer.verify(operation:'second',employee:'b',week:'2026-11-02',date:'2026-11-05',method:'Cash',selected:[remaining],
      base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:0,confirmedNet:8000),isTrue);
    final fullyPaid=(await repo.work(employee:'b')).singleWhere((r)=>r['id']==turbo['id']);
    expect(fullyPaid['paid'],1);expect(fullyPaid['remaining_minutes'],0);expect(await repo.history('b'),hasLength(2));
    // Simulate the phone's partially indexed, still-unsynced invoice. Existing
    // paid credits/payment payloads must survive recovery byte for byte.
    final paymentsBefore=(await db.customSelect('SELECT * FROM regular_payroll_payments ORDER BY operation_id').get()).map((r)=>r.data).toList();
    final coverageBefore=(await db.customSelect('SELECT * FROM regular_payroll_work_coverage ORDER BY operation_id').get()).map((r)=>r.data).toList();
    final paidCreditBefore=(await db.customSelect('SELECT * FROM local_mechanic_work_credits_v1 WHERE allocation_id=?',variables:[Variable(turbo['id'] as String)]).getSingle()).data;
    final secondId=task('second');
    await db.customStatement("DELETE FROM regular_payroll_task_sources WHERE invoice_id='invoice' AND line_id='second'");
    final detail=invoice(quantity:7,more:true);
    (detail['lines'] as List).add({'id':'missing-labor','line_kind':'labor','description':'Previously unindexed labor','quantity':1});
    await LocalDocumentSqlStore.write(db,LocalDocumentDetailCache.key('shop','invoice'),jsonEncode(detail));
    await db.customStatement("INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,state) VALUES('shop','document_draft_create','invoice','create','{}','pending')");
    await db.customStatement("INSERT INTO local_documents(document_date,id,business_id,job_id,kind,document_number) VALUES('2026-11-09','unavailable','shop','job','invoice','SYNTHETIC-NO-CACHE')");
    await db.customStatement("UPDATE local_documents SET document_date='2026-11-09' WHERE id IN ('invoice','unavailable')");
    final outboxBefore=(await db.customSelect('SELECT * FROM sync_outbox').get()).map((r)=>r.data).toList();
    var recovered=0,unavailable=0;
    await repo.backfillInvoiceTasks(onProgress:(checked,added,unknown){recovered=added;unavailable=unknown;});
    expect(recovered,2);expect(unavailable,1);
    final indexed=await repo.tasks();
    expect(indexed.singleWhere((r)=>r['source_line_id']=='second')['id'],secondId);
    expect(indexed.where((r)=>r['source_line_id']=='missing-labor'),hasLength(1));
    await repo.backfillInvoiceTasks();
    expect(await repo.tasks(),hasLength(indexed.length));
    expect((await db.customSelect('SELECT * FROM regular_payroll_payments ORDER BY operation_id').get()).map((r)=>r.data).toList(),paymentsBefore);
    expect((await db.customSelect('SELECT * FROM regular_payroll_work_coverage ORDER BY operation_id').get()).map((r)=>r.data).toList(),coverageBefore);
    expect((await db.customSelect('SELECT * FROM local_mechanic_work_credits_v1 WHERE allocation_id=?',variables:[Variable(turbo['id'] as String)]).getSingle()).data,paidCreditBefore);
    expect((await db.customSelect('SELECT * FROM sync_outbox').get()).map((r)=>r.data).toList(),outboxBefore);
    expect((await repo.work(employee:'b')).singleWhere((r)=>r['id']==turbo['id'])['remaining_minutes'],0);
    // Removing a line deactivates only its source, never its earned/paid work.
    (detail['lines'] as List).removeWhere((r)=>r['id']=='missing-labor');
    await LocalDocumentSqlStore.write(db,LocalDocumentDetailCache.key('shop','invoice'),jsonEncode(detail));
    await repo.backfillInvoiceTasks();
    expect((await repo.tasks()).singleWhere((r)=>r['source_line_id']=='missing-labor')['source_active'],0);
    await db.customStatement("UPDATE local_documents SET status='voided' WHERE id='invoice'");
    await LocalDocumentDetailCache(database:db).load('shop','invoice');
    expect((await repo.tasks()).where((r)=>r['source_kind']=='invoice').every((r)=>r['source_active']==0),isTrue);
    expect(await repo.history('b'),hasLength(2));

    await repo.saveEmployeeCompensation(employee:'d',name:'Synthetic new mechanic',rate:0,weeklyBase:false);
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status) VALUES('rate-job','shop','owner','Synthetic rate confirmation','open')");
    await db.customStatement("INSERT INTO local_documents(document_date,id,business_id,job_id,kind) VALUES('2026-11-09','rate-invoice','shop','rate-job','invoice')");
    await LocalDocumentDetailCache(database:db).save('shop','rate-invoice',{'id':'rate-invoice','kind':'invoice','job_id':'rate-job',
      'lines':[{'id':'labor','line_kind':'labor','description':'Confirm missing hourly rate','quantity':1}]});
    await repo.setMainMechanic('rate-job','d','Synthetic new mechanic');
    final inherited=(await repo.work(employee:'d')).single;
    expect(inherited['rate_cents'],0);
    await repo.registerAssignedLabor(jobId:'rate-job',invoiceId:'rate-invoice',lineId:'labor',employeeId:'d',employeeName:'Synthetic new mechanic',rateCents:3500);
    var confirmed=(await repo.work(employee:'d')).single;
    expect(confirmed['id'],inherited['id']);expect(confirmed['rate_cents'],3500);
    await repo.setMainMechanic('rate-job','c','Mechanic c');
    expect((await repo.work(job:'rate-job')).single['employee_id'],'d');
    await repo.updateWork(confirmed['id'] as String,'In Progress',0,'2026-11-05');
    await repo.updateWork(confirmed['id'] as String,'Done',100,'2026-11-05');
    confirmed=(await repo.work(employee:'d')).single;
    expect(await payer.verify(operation:'confirmed-rate-pay',employee:'d',week:'2026-11-02',date:'2026-11-05',method:'Cash',selected:[confirmed],
      base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:0,confirmedNet:3500),isTrue);
    await repo.registerAssignedLabor(jobId:'rate-job',invoiceId:'rate-invoice',lineId:'labor',employeeId:'d',employeeName:'Synthetic new mechanic',rateCents:9999);
    final frozen=(await repo.work(employee:'d')).single;
    expect(frozen['rate_cents'],3500);expect(frozen['remaining_minutes'],0);expect(await repo.history('d'),hasLength(1));


  });
}
