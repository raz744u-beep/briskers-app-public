import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_task_assignment_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('splitting 3.6 billable hours never defaults both mechanics to 3.6',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
    });
    final repo = LocalPayrollRepository(db,business:'shop',owner:true);
    await repo.prepare();
    await LocalDocumentDetailCache.initialize(db);
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) "
      "VALUES('job','shop','owner','Synthetic split repair','open','J-SPLIT')");
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,kind,document_number) "
      "VALUES('invoice','shop','job','invoice','TEST-SPLIT')");
    await LocalDocumentDetailCache(database:db).save('shop','invoice',{
      'id':'invoice','kind':'invoice','job_id':'job',
      'lines':[{'id':'labor','name':'Labor','line_kind':'labor',
        'description':'Replace air struts','quantity':3.6,'unit_price':150}],
    });
    final assignment=LocalTaskAssignmentStore(db);
    for(final employee in ['a','b']){
      await assignment.linkEmployee('shop','job',employee,'Mechanic $employee');
      await repo.registerAssignedLabor(
        jobId:'job',invoiceId:'invoice',lineId:'labor',
        employeeId:employee,employeeName:'Mechanic $employee',rateCents:0);
    }
    final work=await repo.work();
    expect(work,hasLength(2));
    expect(work.map((w)=>w['task_id']).toSet(),hasLength(1));
    final estimates={for(final row in work)
      row['employee_id']:row['estimated_minutes']};
    expect(estimates['a'],216);
    expect(estimates['b'],0,
      reason:'second mechanic must not inherit the complete billable line again');
    expect(work.every((w)=>(w['actual_minutes'] as int)==0),isTrue);
    await repo.setEstimatedMinutes(work.first['task_id'] as String,'a',120);
    await repo.setEstimatedMinutes(work.first['task_id'] as String,'b',96);
    final split=await repo.work();
    expect(split.map((w)=>w['estimated_minutes']).toSet(),{120,96});
    final invoice=await LocalDocumentDetailCache(database:db)
        .load('shop','invoice');
    expect((invoice!['lines'] as List).single['quantity'],3.6);
    expect(split.every((w)=>w['paid_minutes']==0),isTrue);
  });
}
