import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:briskers_app/app.dart';
import 'package:briskers_app/screens/home_screen.dart';
import 'package:drift/drift.dart' show Variable;
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
import 'package:briskers_app/screens/jobs/job_detail_screen.dart';
import 'package:briskers_app/screens/payroll/owner_payroll_screen.dart';
import 'package:briskers_app/screens/payroll/approved_task_details.dart';
import 'package:briskers_app/screens/payroll/weekly_labor_review_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:briskers_app/screens/payroll/payroll_overview.dart';
import 'package:briskers_app/screens/payroll/tasks_workspace.dart';
import 'package:briskers_app/screens/payroll/job_scoped_tasks.dart';
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
      if(root!=null){final icons=File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');if(await icons.exists()){final loader=FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await icons.readAsBytes())));await loader.load();}}
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
    var secondaryPrompts=0;
    final auth=LocalOwnerAuthorization(store:_Unused(),currentIdentity:()=>who,
      verifyOwner:(_)async=>throw StateError('No cloud verification'),
      authenticateDevice:()async{secondaryPrompts++;return true;},
      verifyLocalOwner:(s)async=>VerifiedOwnerEnrollment(who,s));
    final identity=await PayrollLanIdentity.fromSeed(List.filled(32,3));
    final values=<String,String>{};
    final lease=PayrollOwnerLease(identity:identity,business:'shop',anchor:identity.deviceId,read:(k)async=>values[k],write:(k,v)async{values[k]=v;});
    await lease.migrate(await auth.authorizeSession('shop'));
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
        vehicleId:'vehicle',vehicleLabel:'2021 Synthetic SUV',initialLines:[{'name':'Labor','description':'Replace turbocharger and gaskets','line_kind':'labor','quantity':6,'unit_price':100},
          {'name':'Labor','description':'Shared diagnostic labor','line_kind':'labor','quantity':3,'unit_price':100}]);
    });
    final boundary=GlobalKey();final navigator=GlobalKey<NavigatorState>();
    await tester.pumpWidget(PayrollUiScope(database:db,unlock:auth.authorizeSession,connection:network,debugAllowOwnerView:true,
      child:RepaintBoundary(key:boundary,child:MaterialApp(debugShowCheckedModeBanner:false,theme:BriskersApp.applicationTheme,navigatorKey:navigator,home:JobDocumentScreen(businessId:'shop',documentId:invoice,isOwner:true,roleCode:'owner')))));
    Future<void> until(Finder f)async{
      for(var i=0;i<180;i++){
        await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await tester.pump(const Duration(milliseconds:20));
        if(f.evaluate().isNotEmpty)return;
      }
      expect(f,findsWidgets,reason:tester.allWidgets.whereType<Text>().map((t)=>t.data).join(' | '));
    }
    Future<void> click(Finder f)async{await until(f);await tester.ensureVisible(f);await tester.pumpAndSettle();await tester.tap(f);await tester.pumpAndSettle();}
    Future<void> capture(String name)async{
      await tester.pumpAndSettle();
      await tester.runAsync(()async{
        final shot=await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:1);
        final bytes=await shot.toByteData(format:ui.ImageByteFormat.png);
        final file=File('build/payroll-qa/$name.png');await file.parent.create(recursive:true);await file.writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    Future<Finder> creditCard(String employee,String description) async {
      final work=(await tester.runAsync(()=>LocalPayrollRepository(
        db,business:'shop',owner:true).work(employee:employee)))!;
      final credit=work.singleWhere((r)=>r['description']==description);
      return find.byKey(ValueKey('mechanic-work-${credit['id']}'));
    }

    // Both tooltip states use the same approved single-pencil labor control.
    // Before an allocation is loaded it says Assign; afterward it says Edit.
    Finder laborPencils() => find.byWidgetPredicate((widget) =>
      widget is IconButton &&
      (widget.tooltip == 'Edit or split mechanic labor' ||
       widget.tooltip == 'Assign or split mechanic labor'));

    // The same job-wide Main Mechanic selector is now mirrored on Job
    // Details and Invoice Items. Both edit one saved job lead identity;
    // individual invoice labor still uses the existing pencil.
    final jobId=(await tester.runAsync(()async{
      final row=await db.customSelect(
        'SELECT job_id FROM local_documents WHERE business_id=? AND id=?',
        variables:[const Variable<String>('shop'),Variable<String>(invoice)],
      ).getSingle();
      return row.read<String>('job_id');
    }))!;
    // Use the real invoice link so returning exercises its refresh callback.
    await click(find.text('Job J-1'));
    await until(find.text('Main Mechanic'));
    expect(find.text('Job Tasks'),findsNothing,reason:'One task navigation control remains on Job Details.');
    expect(find.textContaining('View Tasks'),findsOneWidget);
    await capture('job-detail-main-mechanic');
    await click(find.byType(DropdownButton<String>).first);
    await click(find.text('Alpha').last);
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:150)));
    await tester.pump();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await until(find.text('Main Mechanic'));
    expect(find.text('Main Mechanic'),findsOneWidget,
      reason:'Invoice mirrors the same saved Job Main Mechanic selector.');
    await until(laborPencils());
    await until(find.text('Total 9.0 hrs'));
    await capture('bugs35-invoice-details-main-mechanic');
    await click(laborPencils().first);
    
    await click(find.text('Add mechanic'));
    await click(find.text('Beta'));
    await click(find.text('Continue'));
    // The second mechanic starts at zero allocated hours. The Owner sets
    // the approved credit once, before completing the task.
    final turboCard=await creditCard('b','Replace turbocharger and gaskets');
    final edit = find.descendant(of:turboCard,matching:find.byTooltip('Edit Assignment'));
    await click(edit);
    var field = find.descendant(of:find.byKey(const ValueKey('hours-1')),matching:find.byType(TextField));
    await click(field);
    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.selection.textInside(controller.text),controller.text);
    expect(tester.widget<TextField>(field).keyboardType.decimal,true);
    await tester.enterText(field,'7.5');
    await click(find.text('Cancel'));
    await click(edit);
    field = find.descendant(of:find.byKey(const ValueKey('hours-1')),matching:find.byType(TextField));
    expect(tester.widget<TextField>(field).controller!.text,'0.00');
    await tester.enterText(field,'3');
    await click(find.widgetWithText(FilledButton,'Save Task'));
    await until(turboCard);
    await click(find.descendant(of:turboCard,matching:
      find.widgetWithText(TextButton,'Start')));
    await until(find.descendant(of:turboCard,matching:find.text('In Progress')));
    await click(find.descendant(of:turboCard,matching:
      find.widgetWithText(OutlinedButton,'Mark Done')));
    await until(find.textContaining('Actual: 3.00h · Credited: 3.00h'));
    await tester.runAsync(()async{
      final repo=LocalPayrollRepository(db,business:'shop',owner:true);
      final work=await repo.work(employee:'b');expect(work.single['actual_minutes'],180);expect(work.single['recorded_actual_minutes'],180);
      final saved=await LocalDocumentDetailCache(database:db).load('shop',invoice);expect((saved!['lines'] as List).first['quantity'],6);
    });
    navigator.currentState!.pop();await tester.pumpAndSettle();
    await until(laborPencils());
    await click(laborPencils().last);
    
    // Keep Alpha explicitly assigned, then add Beta to the same task identity.
    for(final name in ['Alpha','Beta']){
      await click(find.text('Add mechanic').last);await click(find.text(name).last);await click(find.text('Continue'));
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:400)));await tester.pump();
    }
    // Two independent assigned-hours choices on the shared labor line.
    await tester.runAsync(() async {
      final repo=LocalPayrollRepository(db,business:'shop',owner:true);
      final split=(await repo.work()).where(
        (r)=>r['description']=='Shared diagnostic labor').toList();
      final task=split.first['task_id'] as String;
      await repo.setEstimatedMinutes(task,'a',60);
      await repo.setEstimatedMinutes(task,'b',120);
    });
    await tester.pumpAndSettle();
    for(final name in ['Alpha','Beta']){
      final card=await creditCard(name=='Alpha'?'a':'b','Shared diagnostic labor');
      await until(card);
      await click(find.descendant(of:card,matching:
        find.widgetWithText(TextButton,'Start')));
      await until(find.descendant(of:card,matching:find.text('In Progress')));
      await click(find.descendant(of:card,matching:
        find.widgetWithText(OutlinedButton,'Mark Done')));
      await until(find.descendant(of:card,matching:find.text('Done')));
    }
    await tester.runAsync(()async{
      final all=await LocalPayrollRepository(db,business:'shop',owner:true).work();
      final split=all.where((r)=>r['description']=='Shared diagnostic labor').toList();
      expect(split,hasLength(2));expect(split.map((r)=>r['task_id']).toSet(),hasLength(1));
      expect(split.map((r)=>r['actual_minutes']).toSet(),{60,120});
    });
    // The test happens to run on a Sunday. Work completed by the synthetic
    // UI must be dated inside the Mon–Fri shop week for the payroll review.
    // This updates fixture-only timestamps, not paid credits or app behavior.
    await tester.runAsync(() async {
      final now=DateTime.now();
      final finished=now.weekday<=DateTime.friday
          ? now : now.subtract(Duration(days:now.weekday-DateTime.friday));
      final savedDate=finished.toIso8601String().split('T').first;
      await db.customStatement(
        "UPDATE regular_payroll_portions SET completed_date=? "
        "WHERE business_id='shop' AND state='Done'",
        [savedDate],
      );
    });
    const payrollDock = Key('shared-payroll-dock');
    navigator.currentState!.push(MaterialPageRoute<void>(builder:(_)=>const OwnerPayrollScreen(
      businessId:'shop', sharedBottomNavigationBar: SizedBox(key: payrollDock, height: 60),
    )));
    await tester.pumpAndSettle();
    await until(find.text('Review Weekly Labor (2 tasks)'));
    expect(find.byType(PayrollOverview),findsOneWidget);
    expect(find.byKey(payrollDock),findsOneWidget);
    expect(find.text('Alpha'),findsOneWidget);expect(find.text('Beta'),findsOneWidget);
    expect(find.text('Paid'),findsNWidgets(2));expect(find.text('Total Paid'),findsOneWidget);
    await tester.runAsync(()async{
      final folder=Directory('build/payroll-qa');await folder.create(recursive:true);
      final render=boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final shot=await render.toImage(pixelRatio:1);final bytes=await shot.toByteData(format:ui.ImageByteFormat.png);
      await File('${folder.path}/bugs30-payroll-roster.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await click(find.text('Review Weekly Labor (2 tasks)'));
    await until(find.text('Employee Profile'));
    expect(find.byKey(payrollDock),findsOneWidget);
    
    expect(find.text('Work'),findsOneWidget);expect(find.text('General Tasks'),findsNothing);
    expect(find.textContaining('Currently Assigned Tasks'),findsOneWidget);
    expect(find.widgetWithText(OutlinedButton,'Details'),findsOneWidget);
    await capture('bugs30-employee-unpaid-tasks');

    await click(find.text('Payroll'));
    await capture('nov12-employee-payroll');
    final payroll=find.byType(WeeklyLaborReview);
    final expectedTask=tester.widget<WeeklyLaborReview>(payroll).tasks.firstWhere((r)=>r['state']=='Done'&&r['paid']!=1);
    await click(find.text(expectedTask['description'] as String).first);
    await click(find.byKey(ValueKey('view-payable-task-${expectedTask['id']}')));
    await until(find.byType(ApprovedTaskDetails));
    expect(tester.widget<ApprovedTaskDetails>(find.byType(ApprovedTaskDetails)).initialTask['line_id'],expectedTask['task_id']);
    final exactAllocations=(await tester.runAsync(()=>LocalPayrollRepository(db,business:'shop',owner:true).work()))!.where((r)=>r['task_id']==expectedTask['task_id']).toList();
    expect(tester.widget<ApprovedTaskDetails>(find.byType(ApprovedTaskDetails)).allocations.map((r)=>r['id']).toSet(),exactAllocations.map((r)=>r['id']).toSet());
    navigator.currentState!.pop();await tester.pumpAndSettle();
    expect(tester.widget<WeeklyLaborReview>(find.byType(WeeklyLaborReview)).employeeId,'b');
    expect(tester.widgetList<Checkbox>(find.byType(Checkbox)).every((c)=>c.value==true),isTrue);

    await tester.scrollUntilVisible(find.byKey(const Key('verify-weekly-payment')),150,scrollable:find.descendant(of:find.byKey(const Key('employee-payroll-preparation')),matching:find.byType(Scrollable)).first);
    await click(find.byKey(const Key('verify-weekly-payment')));
    await until(find.text(r'Calculated labor: $200.00'));
    await click(find.widgetWithText(FilledButton,'Record payment'));
    await until(find.text('Payment Recorded'));await click(find.widgetWithText(FilledButton,'Done'));
    await click(find.text('Reports'));await until(find.text('Payroll History'));
    await tester.runAsync(()async{
      final rows=await LocalPayrollRepository(db,business:'shop',owner:true).history('b');expect(rows,hasLength(1));expect(rows.single['net'],20000);
      final alpha=(await LocalPayrollRepository(db,business:'shop',owner:true).work(employee:'a')).where((r)=>r['state']=='Done').single;
      expect(alpha['remaining_cents'],4000);expect(await LocalPayrollRepository(db,business:'shop',owner:true).history('a'),isEmpty);
    });
    // Render the actual regular widgets, not a separately designed mockup.
    await tester.runAsync(()async{
      final image=await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:1);
      final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
      final out=File('build/payroll-qa/regular-reports-source.png');await out.parent.create(recursive:true);await out.writeAsBytes(bytes!.buffer.asUint8List());
    });
    navigator.currentState!.push(MaterialPageRoute<void>(builder:(_)=>Scaffold(body:HomeScreen(
      businessId:'shop',roleCode:'owner',jobsCount:1,onCustomersTap:(){},onAppointmentsTap:(){},
      onJobsTap:(){},onInvoicesTap:(){},onMoreTap:(){}))));
    await tester.pumpAndSettle();
    // The full application supplies the Material host. No Supabase session is
    // enrolled in this isolated fixture; dismiss its caught recurring notice.
    ScaffoldMessenger.of(tester.element(find.byType(HomeScreen))).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Payroll'),150,scrollable:find.descendant(of:find.byType(HomeScreen),matching:find.byType(Scrollable)).first);
    await click(find.text('Payroll'));
    await until(find.text('Review Weekly Labor (0 tasks)'));
    expect(find.text('Payroll reports'),findsNothing);
    expect(find.text('Review Weekly Labor (0 tasks)'),findsOneWidget);
    expect(find.text('Review Weekly Labor (1 tasks)'),findsOneWidget);
    await click(find.text('Review Weekly Labor (0 tasks)'));
    await until(find.textContaining('Currently Assigned Tasks'));
    await click(find.text('Payroll'));
    await until(find.text('No verified unpaid labor for this week.'));
    expect(find.byKey(const Key('verify-weekly-payment')),findsNothing);
    expect(find.text('Weekly Payment Summary'),findsOneWidget);
    await capture('bugs30-employee-paid-tasks');
    await click(find.text('Reports'));await until(find.text('Payroll History'));
    navigator.currentState!.pop();await tester.pumpAndSettle();
    navigator.currentState!.pop();await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tasks'),-100,scrollable:find.descendant(of:find.byType(HomeScreen),matching:find.byType(Scrollable)).first);
    await click(find.text('Tasks'));
    await until(find.byType(TasksWorkspace));
    await click(find.byKey(const Key('toggle-task-filters')));
    await tester.tap(find.byKey(const ValueKey('Status:Active')));await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);await tester.pumpAndSettle();
    await click(find.text('Apply Filters'));
    await until(find.text('Tasks · 2 (All)'));
    expect(find.text('Shared diagnostic labor'),findsOneWidget);
    await capture('bugs30-global-completed-tasks');
    // Reuse the Job identity already verified when navigating from Invoice.
    navigator.currentState!.push(MaterialPageRoute<void>(builder:(_)=>
      JobDetailScreen(businessId:'shop',jobId:jobId,roleCode:'owner')));
    final jobPage = find.byType(JobDetailScreen);
    final chip = find.descendant(of:jobPage,matching:find.widgetWithIcon(ActionChip,Icons.receipt_long_outlined));
    await until(chip);
    await until(find.text('Job Progress'));
    await capture('bugs32-owner-job-details');
    final list = find.descendant(of:jobPage,matching:find.byType(RefreshIndicator)).first;
    final add = find.descendant(of:jobPage,matching:find.widgetWithText(FloatingActionButton,'New'));
    // A floating New action intentionally overlays the scrollable viewport;
    // it must be visible inside the Job page, not reserve an opaque bottom row.
    expect(tester.getRect(add).top, greaterThanOrEqualTo(tester.getRect(jobPage).top));
    expect(tester.getRect(add).bottom, lessThanOrEqualTo(tester.getRect(jobPage).bottom));
    expect(tester.getRect(list).bottom, greaterThan(tester.getRect(add).top));
    await click(chip);
    expect(tester.widget<JobDocumentScreen>(find.byType(JobDocumentScreen)).documentId,invoice);
    navigator.currentState!.pop();await tester.pumpAndSettle();
    await click(find.descendant(of:jobPage,matching:find.textContaining('View Tasks')));
    // Job-specific Tasks intentionally uses the approved compact view.
    // Global Tasks above retains its existing filterable workspace.
    await until(find.byType(JobScopedTasks));
    expect(tester.widget<JobScopedTasks>(find.byType(JobScopedTasks)).jobId,jobId);
    expect(find.text('Labor Task'),findsOneWidget);
    expect(find.text('General Task'),findsOneWidget);
    expect(find.byTooltip('Advanced task filters'),findsNothing);
    expect(find.byIcon(Icons.more_vert),findsOneWidget,reason:'Header retains invoice labor history; cards use long press.');
    await capture('job-tasks-collapsed');
    final scopedTask = find.descendant(of:find.byType(JobScopedTasks),
      matching:find.text('Shared diagnostic labor'));
    await click(scopedTask.first);
    await until(find.text('Task Details'));
    expect(find.text('Edit Task'),findsOneWidget);
    await capture('job-task-details');
    navigator.currentState!.pop();await tester.pumpAndSettle();
    // Saved General Task completion must refresh even if Android reminders fail.
    final generalId=(await tester.runAsync(()=>LocalPayrollRepository(db,business:'shop',owner:true).saveGeneralTask(operation:'quick-general',employee:'b',description:'Call customer after repair',category:'Office',job:jobId,due:DateTime.now().add(const Duration(days:1)),reminder:true)))!;
    navigator.currentState!.pop();await tester.pumpAndSettle();
    await click(find.descendant(of:jobPage,matching:find.textContaining('View Tasks')));
    await until(find.text('Call customer after repair'));await click(find.text('Call customer after repair'));
    const notifications=MethodChannel('dexterous.com/flutter/local_notifications');
    debugDefaultTargetPlatformOverride=TargetPlatform.android;AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(notifications,(call)async{throw PlatformException(code:'invalid_icon',message:'synthetic missing resource');});
    try{
      await click(find.text('Mark as Done'));
      await until(find.text('Done'));
      expect(find.textContaining('PlatformException'),findsNothing);
      expect(find.text('Mark as Done'),findsNothing);
      await capture('quick-general-done');
      final saved=(await tester.runAsync(()=>LocalPayrollRepository(db,business:'shop',owner:true).shopTasks()))!.singleWhere((r)=>r['id']==generalId);
      expect(saved['status'],'done');expect(saved['job_id'],jobId);expect(saved['reminder_enabled'],1);
      navigator.currentState!.pop();await tester.pumpAndSettle();await until(find.text('Call customer after repair'));
      expect(find.text('Call customer after repair'),findsOneWidget);
    }finally{debugDefaultTargetPlatformOverride=null;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(notifications,null);}
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds:500));
    expect(secondaryPrompts,0,
      reason:'The regular invoice-to-Payroll-to-Tasks flow must require only the initial Briskers login.');
    expect(tester.takeException(),isNull);
  },skip:!OwnerPayrollScreen.enabled,timeout:const Timeout(Duration(minutes:3)));
}
