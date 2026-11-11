import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:briskers_app/services/payroll_owner_lease.dart';
import 'package:briskers_app/services/payroll_owner_lan.dart';
import 'package:briskers_app/screens/payroll/owner_payroll_screen.dart';
import 'package:briskers_app/screens/payroll/payroll_ui_scope.dart';
class _Unused implements OwnerEnrollmentStore {
  @override Future<String?> read() async => null;
  @override Future<void> write(String value) async {}
  @override Future<void> clear() async {}
}
class _NoInternet extends HttpOverrides {
  @override HttpClient createHttpClient(SecurityContext? context) => throw StateError('Assignments must work offline');
}
void main() {
  testWidgets('Labor Task assigns existing Oil Change through mechanic and hours UI offline', (tester) async {
    SharedPreferences.setMockInitialValues({'briskers_job_employees_shop':jsonEncode([{'id':'kam','name':'Kam','nickname':'Kam','position':'Mechanic'}])});
    FlutterSecureStorage.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
    final previous=HttpOverrides.current;HttpOverrides.global=_NoInternet();
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    const who=OwnerSessionIdentity('owner','fixture');
    final auth=LocalOwnerAuthorization(store:_Unused(),currentIdentity:()=>who,
      verifyOwner:(_)async=>throw StateError('No cloud'),authenticateDevice:()async=>throw StateError('No extra unlock'),
      verifyLocalOwner:(s)async=>VerifiedOwnerEnrollment(who,s));
    final identity=await PayrollLanIdentity.fromSeed(List.filled(32,3));
    final values=<String,String>{};
    final lease=PayrollOwnerLease(identity:identity,business:'shop',anchor:identity.deviceId,read:(k)async=>values[k],write:(k,v)async{values[k]=v;});
    await lease.migrate(await auth.authorizeSession('shop'));
    final network=PayrollOwnerLan(lease:lease,database:db,actor:'owner',approve:(_)async=>null);
    addTearDown(()async{await network.close();await db.close();LocalDocumentDetailCache.sqliteWritesEnabled=false;HttpOverrides.global=previous;await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);});
    final repo=LocalPayrollRepository(db,business:'shop',owner:true);
    final detail=<String,dynamic>{'id':'invoice','kind':'invoice','job_id':'job','total':192.06,'paid_amount':192.06,'payments':[{'id':'payment','amount':192.06}], 'lines':[{'id':'oil','name':'Oil Change','line_kind':'item','quantity':1,'unit_price':175}]};
    await tester.runAsync(()async{
      await repo.prepare();await LocalDocumentDetailCache.initialize(db);
      await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,customer_name,status,job_number,assigned_employee_id,assigned_employee_name) VALUES('job','shop','owner','Marzel Stafford','Marzel Stafford','open','J-50','kam','Kam')");
      await db.customStatement("INSERT INTO local_documents(document_date,id,business_id,job_id,kind,document_number) VALUES('2026-11-11','invoice','shop','job','invoice','6370')");
      await LocalDocumentDetailCache(database:db).save('shop','invoice',detail);
    });
    await tester.pumpWidget(PayrollUiScope(database:db,unlock:auth.authorizeSession,connection:network,debugAllowOwnerView:true,
      child:MaterialApp(home:OwnerPayrollScreen(businessId:'shop',jobId:'job',database:db))));
    Future<void> until(Finder f)async{
      for(var i=0;i<150;i++){
        await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));
        await tester.pump(const Duration(milliseconds:20));
        if(f.evaluate().isNotEmpty)return;
      }
      expect(f,findsWidgets,reason:tester.allWidgets.whereType<Text>().map((w)=>w.data).join(' | '));
    }
    Future<void> click(Finder f)async{await until(f);await tester.ensureVisible(f);await tester.tap(f);await tester.pumpAndSettle();}
    await click(find.text('Labor Task'));
    await until(find.text('Choose existing service'));
    expect(find.text('Add Labor Task'),findsNothing);
    await click(find.text('Oil Change'));
    await click(find.text('Continue'));
    await until(find.text('Add mechanic to invoice labor'));
    await click(find.descendant(of:find.byType(AlertDialog),matching:find.text('Kam')));
    await click(find.text('Continue'));
    await until(find.text('Mechanic hours'));
    await tester.enterText(find.byType(TextField),'1.0');
    await click(find.text('Continue'));
    for(var i=0;i<150;i++){
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await tester.pump(const Duration(milliseconds:20));
      final work=await tester.runAsync(()=>repo.work());
      if(work?.firstOrNull?['estimated_minutes']==60)break;
    }
    final work=(await tester.runAsync(()=>repo.work()))!;
    expect(work,hasLength(1));expect(work.single['employee_id'],'kam');expect(work.single['estimated_minutes'],60);
    expect(await tester.runAsync(()=>LocalDocumentDetailCache(database:db).load('shop','invoice')),detail);
    expect(find.textContaining('Oil Change'),findsWidgets);
    // J-50 equivalent: the customer paid, but Kam has not. Direct Done
    // must preserve the allocation and credit exactly one unpaid hour.
    await click(find.text('Oil Change').first);
    await click(find.text('Mark Done'));
    await until(find.text('Done').first);
    var earned=(await tester.runAsync(()=>repo.work()))!.single;
    expect(earned['id'],work.single['id']);
    expect(earned['estimated_minutes'],60);
    expect(earned['actual_minutes'],60);
    expect(earned['remaining_minutes'],60);
    expect(earned['paid_minutes'],0);
    await click(find.text('Edit Assignment'));
    await until(find.text('Manage Labor Assignments'));
    await click(find.byTooltip('Edit Assignment'));
    await tester.enterText(find.byType(TextField),'1.5');
    await click(find.text('Save'));
    for(var i=0;i<100;i++) {
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));
      await tester.pump(const Duration(milliseconds:20));
      earned=(await tester.runAsync(()=>repo.work()))!.single;
      if(earned['estimated_minutes']==90) break;
    }
    expect(earned['id'],work.single['id']);
    expect(earned['actual_minutes'],90);
    expect(earned['remaining_minutes'],90);
    expect(earned['paid_minutes'],0);
    expect(await tester.runAsync(()=>LocalDocumentDetailCache(database:db).load('shop','invoice')),detail);
    expect(await tester.runAsync(()=>db.customSelect('SELECT * FROM regular_payroll_payments').get()),isEmpty);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
