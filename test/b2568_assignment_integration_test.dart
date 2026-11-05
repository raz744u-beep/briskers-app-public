import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
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
    await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,kind,document_number) VALUES('invoice','shop','job','invoice','6363')");
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
  });
}
