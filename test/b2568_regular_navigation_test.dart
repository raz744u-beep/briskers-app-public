import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:briskers_app/app.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:briskers_app/services/payroll_owner_lease.dart';
import 'package:briskers_app/services/payroll_owner_lan.dart';
import 'package:briskers_app/screens/jobs/job_document_screen.dart';
import 'package:briskers_app/screens/payroll/owner_payroll_screen.dart';
import 'package:briskers_app/screens/payroll/payroll_ui_scope.dart';
class _Unused implements OwnerEnrollmentStore{
  @override Future<String?> read()async=>null;
  @override Future<void> write(String value)async{}
  @override Future<void> clear()async{}
}
class _NoInternet extends HttpOverrides{
  @override HttpClient createHttpClient(SecurityContext? context)=>throw StateError('This regular-app test must stay offline');
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('enabled regular invoice -> Main Mechanic -> line override -> task -> employee payroll -> Reports', (tester)async{
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(()async{
      final root=Platform.environment['FLUTTER_ROOT'];
      final candidates=[if(root!=null)'$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'];
      for(final path in candidates){final file=File(path);if(await file.exists()){
        final font=FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));await font.load();break;
      }}
    });
    SharedPreferences.setMockInitialValues({'briskers_job_employees_shop':jsonEncode([
      {'id':'a','name':'Mechanic Alpha','nickname':'Alpha','position':'Mechanic'},
      {'id':'b','name':'Mechanic Beta','nickname':'Beta','position':'Mechanic'}])});
    FlutterSecureStorage.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
    final previous=HttpOverrides.current;HttpOverrides.global=_NoInternet();
    final directory=(await tester.runAsync(()=>Directory.systemTemp.createTemp('regular-app429')))!;
    final db=BriskersLocalDatabase(NativeDatabase(File('${directory.path}/shop.sqlite')));
    debugUseLocalDatabase(db);
    const who=OwnerSessionIdentity('owner','local');
    final auth=LocalOwnerAuthorization(store:_Unused(),currentIdentity:()=>who,
      verifyOwner:(_)async=>throw StateError('No cloud verification'),authenticateDevice:()async=>true,
      verifyLocalOwner:(s)async=>VerifiedOwnerEnrollment(who,s));
    final identity=await PayrollLanIdentity.fromSeed(List.filled(32,3));
    final values=<String,String>{};
    final lease=PayrollOwnerLease(identity:identity,business:'shop',anchor:identity.deviceId,read:(k)async=>values[k],write:(k,v)async{values[k]=v;});
    await lease.migrate(await auth.authorizeLocal('shop'));
    final network=PayrollOwnerLan(lease:lease,database:db,actor:'owner',approve:(_)async=>null);
    addTearDown(()async{await network.close();await db.close();debugUseLocalDatabase(null);
      LocalDocumentDetailCache.sqliteWritesEnabled=false;HttpOverrides.global=previous;
      await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);await directory.delete(recursive:true);});
    late String invoice;
    await tester.runAsync(()async{
      await LocalDocumentDetailCache.initialize(db);
      await db.customStatement("INSERT INTO local_customers(id,business_id,display_name) VALUES('customer','shop','Synthetic Customer')");
      await db.customStatement("INSERT INTO local_vehicles(id,business_id,year,make,model) VALUES('vehicle','shop',2021,'Synthetic','SUV')");
      await db.customStatement("INSERT INTO local_customer_vehicles(business_id,customer_id,vehicle_id) VALUES('shop','customer','vehicle')");
      final repo=LocalPayrollRepository(db,business:'shop',owner:true);
      await repo.saveEmployeeCompensation(employee:'a',name:'Mechanic Alpha',rate:4000,weeklyBase:false);
      await repo.saveEmployeeCompensation(employee:'b',name:'Mechanic Beta',rate:4000,weeklyBase:false);
      invoice=await OfflineDocumentDraftService(database:db).createQuickInvoice('shop',customerId:'customer',customerName:'Synthetic Customer',
        vehicleId:'vehicle',vehicleLabel:'2021 Synthetic SUV',initialLines:[{'name':'Labor','description':'Replace turbocharger and gaskets','line_kind':'labor','quantity':6,'unit_price':100}]);
    });
    final boundary=GlobalKey();final navigator=GlobalKey<NavigatorState>();
    await tester.pumpWidget(PayrollUiScope(database:db,unlock:auth.authorizeLocal,connection:network,
      child:RepaintBoundary(key:boundary,child:MaterialApp(theme:BriskersApp.applicationTheme,navigatorKey:navigator,home:JobDocumentScreen(businessId:'shop',documentId:invoice,isOwner:true,roleCode:'owner')))));
    Future<void> until(Finder f)async{
      for(var i=0;i<180;i++){
        await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await tester.pump(const Duration(milliseconds:20));
        if(f.evaluate().isNotEmpty)return;
      }
      expect(f,findsWidgets,reason:tester.allWidgets.whereType<Text>().map((t)=>t.data).join(' | '));
    }
    Future<void> click(Finder f)async{await until(f);await tester.ensureVisible(f);await tester.pumpAndSettle();await tester.tap(f);await tester.pumpAndSettle();}
    await until(find.text('Main Mechanic'));
    await click(find.byType(DropdownButtonFormField<String>).first);
    await click(find.text('Alpha').last);
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:150)));await tester.pump();
    await click(find.text('Assign mechanics / task'));
    await click(find.text('Unlock Owner payroll'));
    await click(find.text('Assign / split'));
    await click(find.text('Beta'));
    await until(find.textContaining('Mechanic Beta · Open'));
    await click(find.widgetWithText(TextButton,'Start'));
    await until(find.widgetWithText(TextButton,'Complete'));
    await click(find.widgetWithText(TextButton,'Complete'));
    await until(find.byType(AlertDialog));await tester.enterText(find.descendant(of:find.byType(AlertDialog).last,matching:find.byType(TextField)),'2');await click(find.text('Continue'));
    await until(find.byType(AlertDialog));await tester.enterText(find.descendant(of:find.byType(AlertDialog).last,matching:find.byType(TextField)),'3');await click(find.text('Continue'));
    await until(find.textContaining('120 actual min · 180 credited min'));
    await tester.runAsync(()async{
      final repo=LocalPayrollRepository(db,business:'shop',owner:true);
      final work=await repo.work(employee:'b');expect(work.single['actual_minutes'],180);expect(work.single['recorded_actual_minutes'],120);
      final saved=await LocalDocumentDetailCache(database:db).load('shop',invoice);expect((saved!['lines'] as List).single['quantity'],6);
    });
    navigator.currentState!.push(MaterialPageRoute<void>(builder:(_)=>const OwnerPayrollScreen(businessId:'shop',employeeId:'b',employeeName:'Mechanic Beta',employeeRole:'Mechanic')));
    await tester.pumpAndSettle();await click(find.text('Unlock Owner payroll'));
    await click(find.widgetWithText(FilledButton,'Verify Payment'));
    await until(find.text(r'Calculated labor: $120.00'));
    await click(find.widgetWithText(FilledButton,'Record payment'));
    await until(find.text('Payment Recorded'));await click(find.widgetWithText(FilledButton,'Done'));
    await click(find.text('Reports'));await until(find.text('Payroll History'));
    await tester.runAsync(()async{
      final rows=await LocalPayrollRepository(db,business:'shop',owner:true).history('b');expect(rows,hasLength(1));expect(rows.single['net'],12000);
    });
    // Render the actual regular widgets, not a separately designed mockup.
    await tester.runAsync(()async{
      final image=await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:1);
      final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
      final out=File('build/payroll-qa/regular-reports-source.png');await out.parent.create(recursive:true);await out.writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox.shrink());await tester.pump(const Duration(milliseconds:500));expect(tester.takeException(),isNull);
  },skip:!OwnerPayrollScreen.enabled,timeout:const Timeout(Duration(minutes:3)));
}
