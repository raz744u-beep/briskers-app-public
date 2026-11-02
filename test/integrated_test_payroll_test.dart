import 'dart:io';
import 'package:briskers_app/payroll_native_acceptance_main.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/integrated_test_payroll.dart';

void main() {
  late BriskersLocalDatabase db;
  late IntegratedTestPayroll r;
  setUp(()async{db=BriskersLocalDatabase(NativeDatabase.memory());r=IntegratedTestPayroll(db);await r.initializeEmployees();await r.createJob('job','TEST car');await r.addLabor('job','line','Repair',250);await r.assign('job/line','chris');await r.assign('job/line','kam');});
  tearDown(()async{await db.close();});
  Future<void> done([String employee='chris',int hours=250]) async {await r.updateWork('job/line/$employee','In Progress',hours,'2026-11-02');await r.updateWork('job/line/$employee','Done',hours,'2026-11-02');}
  Future<bool> pay({String operation='op',String employee='chris',int repayment=0,int base=0,int adjustment=0,int net=10000,List<Map<String,dynamic>>? selected,Future<void> Function()? fault})async => r.verify(operation:operation,employee:employee,week:'2026-11-02',date:'2026-11-02',method:'Zelle',selected:selected??(await r.work(employee:employee)),base:base,hourlyAdjustment:adjustment,adjustmentReason:adjustment!=0?'Owner test override':'',repayment:repayment,confirmedNet:net,beforeCommit:fault);
  Future<int> count(String table)async=>(await db.customSelect('SELECT count(*) n FROM $table').getSingle()).read<int>('n');
  test('labor creates tasks idempotently, independent mechanic completion and automatic job progress',()async{
    await r.addLabor('job','line','Repair',250);expect(await r.tasks(),hasLength(1));
    await expectLater(r.addLabor('job','line','Changed',250),throwsStateError);
    await expectLater(r.assign('job/line','chris'),throwsA(isA<Exception>()));
    await done();final work=await r.work();expect(work.firstWhere((w)=>w['employee_id']=='chris')['state'],'Done');expect(work.firstWhere((w)=>w['employee_id']=='kam')['state'],'Open');expect((await r.jobs()).single['done'],0);
    await pay();expect((await r.history('chris')).single['gross'],10000);
    expect((await r.jobs()).single['done'],0);
    await done('kam',100);expect((await r.jobs()).single['done'],1);
    await r.addLabor('job','line-2','Second labor',100);expect((await r.jobs()).single['total'],2);expect((await r.jobs()).single['done'],1);
  });
  test('hours credited only after completion; time edits and stale versions rejected',()async{
    await expectLater(pay(),throwsStateError);await done();final stale=await r.work(employee:'chris');
    await r.updateWork('job/line/chris','Done',150,'2026-11-02');
    await expectLater(pay(selected:stale),throwsStateError);await pay(net:6000);expect((await r.history('chris')).single['gross'],6000);
  });
  test('same payload replay, conflicting replay and new operation duplicates',()async{
    await done();final snapshot=await r.work(employee:'chris');expect(await pay(selected:snapshot),true);expect(await pay(selected:snapshot),false);
    await expectLater(pay(selected:snapshot,repayment:1),throwsStateError);await expectLater(pay(selected:snapshot,operation:'second'),throwsStateError);expect(await count('it_payments'),1);expect(await count('it_paid_work'),1);expect(await count('it_sync_outbox'),1);
  });
  test('concurrent verification commits exactly once',()async{
    await done();final snapshot=await r.work(employee:'chris');final results=await Future.wait([for(final op in ['a','b'])pay(operation:op,selected:snapshot).then((v)=>v,onError:(Object e)=>false)]);expect(results.where((v)=>v),hasLength(1));expect(await count('it_payments'),1);
  });
  test('advance deducted once, gross frozen; paid work and historical snapshots immutable',()async{
    await done();await r.addAdvance('chris',5000);final snapshot=await r.work(employee:'chris');await pay(selected:snapshot,repayment:2000,net:8000);await pay(selected:snapshot,repayment:2000,net:8000);expect(await r.advance('chris'),3000);expect((await r.history('chris')).single['gross'],10000);
    await expectLater(r.updateWork('job/line/chris','In Progress',50,'2026-11-02'),throwsStateError);
    await expectLater(db.customStatement('UPDATE it_paid_work SET snapshot=\'{}\''),throwsA(isA<Exception>()));
    await expectLater(db.customStatement('DELETE FROM it_payments'),throwsA(isA<Exception>()));
    await r.addLabor('job','recheck','Recheck',100);await r.assign('job/recheck','chris');await r.updateWork('job/recheck/chris','In Progress',100,'2026-11-02');await r.updateWork('job/recheck/chris','Done',100,'2026-11-02');
    await pay(operation:'recheck-pay',selected:(await r.work(employee:'chris')).where((w)=>w['paid']==0).toList(),net:4000);expect((await r.history('chris')).length,2);
  });
  test('transaction failure rolls back credits, base, payment, repayment, audit and outbox',()async{
    await done();await r.addAdvance('chris',5000);final auditBefore=await count('it_audit');
    await expectLater(pay(repayment:2000,net:8000,fault:()async{throw StateError('Interrupted write');}),throwsStateError);
    expect(await r.advance('chris'),5000);expect(await count('it_payments'),0);expect(await count('it_paid_work'),0);expect(await count('it_sync_outbox'),0);expect(await count('it_audit'),auditBefore);expect((await r.work(employee:'chris')).single['paid'],0);expect(await pay(),true);
  });
  test('weekly base and hourly component independently adjustable; base once per week',()async{
    await r.assign('job/line','base');await done('base',100);
    await pay(employee:'base',base:10000,adjustment:500,net:13000);expect((await r.history('base')).single['gross'],13000);
    await expectLater(pay(operation:'base-again',employee:'base',selected:[],base:10000,net:10000),throwsA(isA<Exception>()));
    await done();await expectLater(pay(base:10000,net:20000),throwsStateError);
  });
  test('non Owner and cross business cannot read or finalize another payroll',()async{
    final denied=IntegratedTestPayroll(db,owner:false);await expectLater(denied.work(),throwsStateError);await expectLater(denied.history('chris'),throwsStateError);
    await done();final other=IntegratedTestPayroll(db,business:'other-shop');await other.initializeEmployees();expect(await other.work(),isEmpty);
    await expectLater(other.verify(operation:'op',employee:'chris',week:'2026-11-02',date:'2026-11-02',method:'Cash',selected:await r.work(employee:'chris'),base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:0,confirmedNet:10000),throwsStateError);
    expect(await count('it_payments'),0);
  });
  test('file database survives connection restart with history and outbox intact',()async{
    final dir=await Directory.systemTemp.createTemp('payroll-persist-');final file=File('${dir.path}/test.sqlite');
    var disk=BriskersLocalDatabase(NativeDatabase(file));
    try {
      var repo=IntegratedTestPayroll(disk);await repo.initializeEmployees();await repo.createJob('j','Car');await repo.addLabor('j','l','Labor',250);await repo.assign('j/l','chris');await repo.updateWork('j/l/chris','In Progress',250,'2026-11-02');await repo.updateWork('j/l/chris','Done',250,'2026-11-02');await repo.addAdvance('chris',3000);
      final work=await repo.work(employee:'chris');
      Future<bool> commit()=>repo.verify(operation:'durable',employee:'chris',week:'2026-11-02',date:'2026-11-02',method:'Cash',selected:work,base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:2000,confirmedNet:8000);
      await commit();await disk.close();disk=BriskersLocalDatabase(NativeDatabase(file));repo=IntegratedTestPayroll(disk);
      expect((await repo.history('chris')).single['net'],8000);expect((await repo.work()).single['paid'],1);expect(await repo.advance('chris'),1000);expect(await commit(),false);
      await disk.customStatement("UPDATE it_sync_outbox SET attempts=attempts+1,state='failed'");expect(await commit(),false);expect((await repo.history('chris')).length,1);
    } finally {await disk.close();await dir.delete(recursive:true);}
  });

  test('outside-week work requires audited override; invalid deductions and amount fail',()async{
    await done();final work=await r.work(employee:'chris');
    Future<bool> outside(String reason)=>r.verify(operation:'outside',employee:'chris',week:'2026-10-26',date:'2026-11-02',method:'Cash',selected:work,base:0,hourlyAdjustment:0,adjustmentReason:reason,repayment:0,confirmedNet:10000);
    await expectLater(outside(''),throwsStateError);
    await expectLater(pay(repayment:1,net:9999),throwsStateError);
    await expectLater(pay(net:9999),throwsStateError);
    await outside('Owner includes late completed work');expect((await r.history('chris')).single['gross'],10000);
    await expectLater(db.customStatement('UPDATE local_mechanic_work_credits_v1 SET actual_minutes=0 WHERE paid_operation_id IS NOT NULL'),throwsA(isA<Exception>()));
  });
  test('base payment also rolls back and non Owner cannot verify',()async{
    await expectLater(pay(employee:'base',base:10000,selected:[],net:10000,fault:()async{throw StateError('Abort');}),throwsStateError);
    expect(await count('it_paid_base'),0);expect(await count('it_payments'),0);
    final denied=IntegratedTestPayroll(db,owner:false);
    await expectLater(denied.verify(operation:'forbidden',employee:'base',week:'2026-11-02',date:'2026-11-02',method:'Cash',selected:[],base:10000,hourlyAdjustment:0,adjustmentReason:'',repayment:0,confirmedNet:10000),throwsStateError);
  });
  test('minute work credit is authoritative for cents rounding',()async{
    await done('chris',1);
    final work=(await r.work(employee:'chris')).single;
    expect(work['actual_minutes'],1);expect(work['gross_cents'],67);
    await pay(net:67);expect((await r.history('chris')).single['gross'],67);
  });
  test('authoritative unfinished repository credit cannot be paid through stale task state',()async{
    await done();
    await db.customStatement('UPDATE local_mechanic_work_credits_v1 SET completed=0,revision=revision+1 WHERE employee_id=?',['chris']);
    await expectLater(pay(),throwsStateError);expect(await count('it_payments'),0);
  });
  test('native acceptance entry point detects first and persisted launches',()async{
    expect(await verifyNativePayrollPersistence(db),'created');
    expect(await verifyNativePayrollPersistence(db),'reopened');
  });
}
