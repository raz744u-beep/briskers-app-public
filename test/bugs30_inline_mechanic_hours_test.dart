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

  testWidgets('invoice labor shows per-mechanic nickname and independent hours without changing billed quantity', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      LocalDocumentDetailCache.sqliteWritesEnabled=false;
    });
    await LocalDocumentDetailCache.initialize(db);
    final repo=LocalPayrollRepository(db,business:'shop',owner:true);
    await repo.prepare();
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) "
      "VALUES('job','shop','owner','Rear differential','open','J-24')");
    await db.customStatement(
      "INSERT INTO local_documents(document_date,id,business_id,job_id,kind,document_number) "
      "VALUES('2026-11-07','invoice','shop','job','invoice','6342')");
    final source={
      'id':'invoice','kind':'invoice','job_id':'job',
      'lines':[{'id':'rear','line_kind':'labor','description':'Replace rear differential fluid',
        'quantity':0.8,'unit_price':100}],
    };
    await LocalDocumentDetailCache(database:db).save('shop','invoice',source);
    await repo.saveEmployeeCompensation(employee:'a',name:'Mechanic Adam',
      rate:3500,weeklyBase:false);
    await repo.saveEmployeeCompensation(employee:'b',name:'Mechanic Chris',
      rate:4000,weeklyBase:false);
    await repo.setMainMechanic('job','a','Mechanic Adam');
    final task=(await repo.tasks()).singleWhere((r)=>r['source_line_id']=='rear')['id'] as String;
    // Convert inherited lead to an explicit allocation before adding Chris;
    // a per-line override must never silently reassign the original lead.
    await repo.assignTask(task,'a','Mechanic Adam',rate:3500);
    await repo.assignTask(task,'b','Mechanic Chris',rate:4000);
    await repo.setEstimatedMinutes(task,'a',180);
    await repo.setEstimatedMinutes(task,'b',60);
    final nicknames=EmployeeNicknameStore(database:db);
    await nicknames.save('shop','a','Adam');
    await nicknames.save('shop','b','Chris');

    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Center(
      child:SizedBox(width:350,child:JobTasksAccess(
        business:'shop',job:'job',invoice:'invoice',line:'rear',database:db))))));
    for(var i=0;i<30;i++){
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));
      await tester.pump(const Duration(milliseconds:20));
      if(find.textContaining('Adam 3.0h').evaluate().isNotEmpty &&
          find.textContaining('Chris 1.0h').evaluate().isNotEmpty){
        break;
      }
    }
    expect(find.textContaining('Adam 3.0h'),findsOneWidget,
      reason:tester.allWidgets.whereType<Text>().map((t)=>t.data).join(' | '));
    expect(find.textContaining('Chris 1.0h'),findsOneWidget);
    // The approved TEST presents one compact combined nickname/hour badge
    // and one pencil. Both per-employee allocations still exist in Payroll.
    expect(find.textContaining('Adam 3.0h · Chris 1.0h'),findsOneWidget);
    expect(find.byTooltip('Edit or split mechanic labor'),findsOneWidget);
    expect(find.byTooltip('Edit Adam estimated mechanic hours'),findsNothing);
    expect(find.byTooltip('Edit Chris estimated mechanic hours'),findsNothing);

    final document=await LocalDocumentDetailCache(database:db).load('shop','invoice');
    expect((document!['lines'] as List).first['quantity'],0.8);
    expect((await repo.work()).map((r)=>r['estimated_minutes']).toSet(),{60,180});
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
