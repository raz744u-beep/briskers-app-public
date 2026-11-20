import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/employee_nickname_store.dart';
import 'package:briskers_app/screens/payroll/job_tasks_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('paid Chris allocation keeps manager accessible and permits additive Kam assignment', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(() async { await db.close(); LocalDocumentDetailCache.sqliteWritesEnabled=false; });
    await LocalDocumentDetailCache.initialize(db);
    final repo=LocalPayrollRepository(db,business:'shop',owner:true);
    await repo.prepare();
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) VALUES('job','shop','owner','Engine','open','J-56')");
    await db.customStatement("INSERT INTO local_documents(document_date,id,business_id,job_id,kind,document_number) VALUES('2026-11-09','invoice','shop','job','invoice','6376')");
    await LocalDocumentDetailCache(database:db).save('shop','invoice',{
      'id':'invoice','kind':'invoice','job_id':'job','lines':[
        {'id':'engine','name':'Labor','line_kind':'item','description':'Replace engine','quantity':18,'unit_price':150},
      ]});
    await repo.saveEmployeeCompensation(employee:'chris',name:'Chris Rideaux',rate:4000,weeklyBase:false);
    await repo.saveEmployeeCompensation(employee:'kam',name:'Kamerron Smith',rate:3500,weeklyBase:false);
    await repo.setMainMechanic('job','chris','Chris Rideaux');
    final task=(await repo.tasks()).singleWhere((r)=>r['source_line_id']=='engine')['id'] as String;
    await repo.assignTask(task,'chris','Chris Rideaux',rate:4000);
    await repo.setEstimatedMinutes(task,'chris',1200);
    await db.customStatement("UPDATE local_mechanic_work_credits_v1 SET paid_operation_id='recorded-payment' WHERE business_id='shop' AND employee_id='chris'");
    await EmployeeNicknameStore(database:db).save('shop','chris','Chris');
    final before=(await db.customSelect("SELECT * FROM local_mechanic_work_credits_v1 WHERE employee_id='chris'").get()).single.data;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:350,
      child:JobTasksAccess(business:'shop',job:'job',invoice:'invoice',line:'engine',database:db)))));
    for(var i=0;i<40;i++) {
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));
      await tester.pump(const Duration(milliseconds:20));
      if(find.text('Chris 20.0h').evaluate().isNotEmpty) break;
    }
    expect(find.text('Chris 20.0h'),findsOneWidget);
    final pencil=tester.widget<IconButton>(find.byTooltip('Edit or split mechanic labor'));
    expect(pencil.onPressed,isNotNull,reason:'Paid work must not disable the whole manager');
    expect(tester.widget<InkWell>(find.byKey(const ValueKey('manage-line-mechanics-engine'))).onTap,isNotNull);
    // The same additive operation used by Add mechanic keeps paid Chris intact.
    await tester.runAsync(() async {
      await repo.assignExistingService(job:'job',invoice:'invoice',line:'engine',
        employee:'kam',name:'Kamerron Smith',rate:3500,minutes:60);
      await expectLater(repo.setEstimatedMinutes(task,'chris',1080),throwsStateError);
      final after=(await db.customSelect("SELECT * FROM local_mechanic_work_credits_v1 WHERE employee_id='chris'").get()).single.data;
      expect(after,before);
      final document=await LocalDocumentDetailCache(database:db).load('shop','invoice');
      expect((document!['lines'] as List).single,containsPair('quantity',18));
      final rows=await repo.work();
      expect(rows.singleWhere((r)=>r['employee_id']=='chris')['estimated_minutes'],1200);
      expect(rows.singleWhere((r)=>r['employee_id']=='kam')['estimated_minutes'],60);
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
