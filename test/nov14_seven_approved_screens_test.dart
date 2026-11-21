import 'package:briskers_app/screens/payroll/owner_payroll_screen.dart';
import 'package:briskers_app/screens/payroll/payroll_ui_scope.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:briskers_app/services/payroll_owner_lease.dart';
import 'package:briskers_app/services/payroll_owner_lan.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/app.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/secure_employee_details_cache.dart';
import 'package:briskers_app/services/local_employee_details.dart';
import 'package:briskers_app/services/employee_nickname_store.dart';
import 'package:briskers_app/screens/settings/local_employee_details_screen.dart';
import 'package:briskers_app/screens/payroll/approved_tasks_ui.dart';
import 'package:briskers_app/screens/payroll/employee_work_review.dart';
import 'package:briskers_app/screens/payroll/weekly_labor_review_screen.dart';
import 'package:briskers_app/screens/payroll/payroll_history_panel.dart';
import 'bugs35_shared_design_test.dart' as host;
import 'support/handoff_qa_fonts.dart';

class Store implements OwnerEnrollmentStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String v) async {}
  @override
  Future<void> clear() async {}
}

class Nicknames extends EmployeeNicknameStore {
  String value = 'Kam';
  @override
  Future<String?> get(String b, String e) async => value;
  @override
  Future<void> save(String b, String e, String v) async {
    value = v;
  }
}

Future<void> Function(WidgetTester, GlobalKey, String)? androidCapture;
Future<void> capture(WidgetTester tester, GlobalKey key, String name) =>
    (androidCapture ?? host.capture)(tester, key, name);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const who = OwnerSessionIdentity('synthetic-owner', 'test');
  late LocalOwnerAuthorization auth;
  late BriskersLocalDatabase database;
  const cache = SecureEmployeeDetailsCache();
  final week = DateTime(2026, 11, 9);
  final detail = <String, dynamic>{
    'id': 'm',
    'name': 'Synthetic Mechanic',
    'position': 'Mechanic',
    'position_id': 'p',
    'phone': '5045550100',
    'email': 'fixture@example.invalid',
    'address': 'Synthetic address',
    'payment_type': 'hourly',
    'hourly_rate': 35,
    'weekly_rate': null,
    'compensation_enabled': true,
    'active': true,
    'ssn_last4': '6789',
  };
  Map<String, dynamic> task() => {
    'id': 'credit',
    'task_id': 'original-task',
    'job_id': 'job',
    'invoice_id': 'invoice',
    'job_number': 'J-51',
    'customer_name': 'Synthetic Customer',
    'vehicle_label': '2011 BMW X6',
    'description': 'Oil change and service inspection',
    'state': 'Done',
    'estimated_minutes': 840,
    'actual_minutes': 840,
    'remaining_minutes': 840,
    'paid_minutes': 0,
    'rate_cents': 3500,
    'paid': 0,
    'source_active': 1,
    'completed_date': '2026-11-13',
  };
  setUp(() async {
    database = BriskersLocalDatabase(NativeDatabase.memory());
    debugUseLocalDatabase(database);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    auth = LocalOwnerAuthorization(
      store: Store(),
      currentIdentity: () => who,
      verifyOwner: (_) async => throw StateError('No network'),
      authenticateDevice: () async => true,
      verifyLocalOwner: (s) async => VerifiedOwnerEnrollment(who, s),
    );
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.offline,
    );
    await loadHandoffFonts();
  });
  tearDown(() async {
    await database.close();
    debugUseLocalDatabase(null);
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
  });
  Widget app(Widget child, GlobalKey key) => RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: BriskersApp.applicationTheme,
      home: child,
    ),
  );
  void size(WidgetTester t, {double width = 412, double height = 892}) {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  test(
    'encrypted profile preserves pending edits during refresh and in-flight acknowledgement',
    () async {
      final grant = await auth.authorizeSession('shop');
      await cache.save('shop', 'm', {...detail, 'ssn': '123456789'}, grant);
      await cache.edit('shop', 'm', {'phone': '5045550101'}, grant);
      await cache.save('shop', 'm', {
        ...detail,
        'email': 'new@example.invalid',
      }, grant);
      var saved = (await cache.read('shop', 'm', grant))!;
      expect((saved['details'] as Map)['phone'], '5045550101');
      expect((saved['details'] as Map)['email'], 'new@example.invalid');
      expect((saved['details'] as Map).containsKey('ssn'), false);
      await cache.edit('shop', 'm', {'phone': '5045550102'}, grant);
      await cache.acknowledge(
        'shop',
        'm',
        {'phone': '5045550101'},
        {...detail, 'phone': '5045550101'},
        grant,
      );
      saved = (await cache.read('shop', 'm', grant))!;
      expect((saved['pending'] as Map)['phone'], '5045550102');
      expect((saved['base'] as Map)['phone'], '5045550101');
      await expectLater(
        cache.edit('shop', 'm', {'ssn': '123456789'}, grant),
        throwsArgumentError,
      );
      await expectLater(
        cache.edit('shop', 'missing', {'name': 'Blank overwrite'}, grant),
        throwsStateError,
      );
      await cache.resolveConflict(
        'shop',
        'm',
        {...detail, 'phone': '5045550103'},
        {'phone': '5045550102'},
        true,
        grant,
      );
      saved = (await cache.read('shop', 'm', grant))!;
      expect((saved['pending'] as Map)['phone'], '5045550102');
      expect((saved['base'] as Map)['phone'], '5045550103');
      await expectLater(
        cache.resolveConflict(
          'shop',
          'm',
          detail,
          {'phone': 'stale edit'},
          false,
          grant,
        ),
        throwsStateError,
      );
      await cache.resolveConflict(
        'shop',
        'm',
        {...detail, 'phone': '5045550103'},
        {'phone': '5045550102'},
        false,
        grant,
      );
      saved = (await cache.read('shop', 'm', grant))!;
      expect(saved['pending'], isEmpty);
      expect((saved['details'] as Map)['phone'], '5045550103');
      await auth.revoke();
      await expectLater(cache.read('shop', 'm', grant), throwsStateError);
    },
  );
  test('existing server profile hydrates securely, edits survive restart and reach another device', () async {
    final grant = await auth.authorizeSession('shop');
    final aliasA = Nicknames()..value = 'Kam';
    final server = <String, dynamic>{...detail, 'phone': '5045550100'};
    final metadata = <String, dynamic>{
      'id': 'm', 'nickname': '', 'default_payment_method': null,
    };
    Future<Map<String, dynamic>> patch(
      Map<String, dynamic> target,
      Map<String, dynamic> base,
      Map<String, dynamic> changes,
    ) async {
      final conflict = [
        for (final key in changes.keys)
          if (!base.containsKey(key) ||
              (target[key] != base[key] && target[key] != changes[key])) key,
      ];
      if (conflict.isNotEmpty) return {'conflict': true, 'fields': conflict};
      target.addAll(changes);
      return {'conflict': false, 'details': {...target}};
    }
    LocalEmployeeDetails service(Nicknames aliases) => LocalEmployeeDetails(
      nicknameStore: aliases,
      readProfile: (_, _) async => {...server},
      readMetadata: (_, _) async => {...metadata},
      patchProfile: (_, _, base, changes) => patch(server, base, changes),
      patchMetadata: (_, _, base, changes) => patch(metadata, base, changes),
    );
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);
    await service(aliasA).sync('shop', 'm', grant);
    var saved = (await cache.read('shop', 'm', grant))!;
    expect((saved['details'] as Map)['email'], 'fixture@example.invalid');
    expect((saved['details'] as Map)['ssn_last4'], '6789');
    expect(metadata['nickname'], 'Kam'); // Upgrade the old device-only alias.
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
    await cache.edit('shop', 'm', {
      'phone': '5045550111',
      'default_payment_method': 'Zelle',
      'hourly_rate': 40,
    }, grant);
    // A new cache instance reads the platform-encrypted values after restart.
    saved = (await const SecureEmployeeDetailsCache().read('shop', 'm', grant))!;
    expect((saved['pending'] as Map).length, 3);
    expect((saved['details'] as Map)['address'], 'Synthetic address');
    await expectLater(service(aliasA).sync('shop', 'm', grant), throwsStateError);
    expect(server['phone'], '5045550100');
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);
    await service(aliasA).sync('shop', 'm', grant);
    expect(server['phone'], '5045550111');
    expect(server['hourly_rate'], 40);
    expect(metadata['default_payment_method'], 'Zelle');
    expect(server['email'], 'fixture@example.invalid');
    expect((await cache.read('shop', 'm', grant))!['pending'], isEmpty);

    // A different device starts with no encrypted profile and no SQLite alias.
    FlutterSecureStorage.setMockInitialValues({});
    final aliasB = Nicknames()..value = '';
    await service(aliasB).sync('shop', 'm', grant);
    saved = (await cache.read('shop', 'm', grant))!;
    expect((saved['details'] as Map)['phone'], '5045550111');
    expect((saved['details'] as Map)['default_payment_method'], 'Zelle');
    expect(aliasB.value, 'Kam');
    expect((saved['details'] as Map).containsKey('ssn'), false);
    metadata['nickname'] = '';
    await service(aliasB).sync('shop', 'm', grant);
    expect(aliasB.value, ''); // Another device's explicit clear is not resurrected.
    await cache.edit('shop', 'm', {'phone': '5045550112'}, grant);
    server['phone'] = '5045550199';
    await expectLater(service(aliasB).sync('shop', 'm', grant),
        throwsA(isA<EmployeeDetailsConflict>()));
    saved = (await cache.read('shop', 'm', grant))!;
    expect((saved['pending'] as Map)['phone'], '5045550112');
    expect(server['phone'], '5045550199');
    await cache.resolveConflict('shop', 'm', server,
        {'phone': '5045550112'}, true, grant);
    await service(aliasB).sync('shop', 'm', grant);
    expect(server['phone'], '5045550112');
    await auth.revoke();
    await expectLater(cache.read('shop', 'm', grant), throwsStateError);
  });
  testWidgets(
    'employee details render offline and edit only explicit fields; no invented payment method or W9',
    (t) async {
      size(t);
      final key = GlobalKey();
      final grant = await auth.authorizeSession('shop');
      await t.runAsync(() => cache.save('shop', 'm', detail, grant));
      await t.pumpWidget(
        app(
          LocalEmployeeDetailsScreen(
            businessId: 'shop',
            employeeId: 'm',
            rosterName: 'Synthetic Mechanic',
            rosterPosition: 'Mechanic',
            nicknameStore: Nicknames(),
            unlockOwner: auth.authorizeSession,
          ),
          key,
        ),
      );
      await settle(t);
      expect(find.text('Employment & Pay'), findsOneWidget);
      expect(find.text('Contact Information'), findsOneWidget);
      expect(find.text('Direct Deposit'), findsNothing);
      expect(find.text('On File'), findsNothing);
      expect(find.text('504-555-0100'), findsOneWidget);
      expect(find.text('***-**-6789'), findsOneWidget);
      expect(find.text('Show'), findsOneWidget);
      expect(find.text('123-45-6789'), findsNothing);
      final addressLink = find.ancestor(
        of: find.text('Synthetic address'), matching: find.byType(InkWell),
      );
      expect(t.widget<InkWell>(addressLink.first).onTap, isNotNull);
      await capture(t, key, 'next-employee-details');
      t.view.physicalSize = const Size(360, 780);
      await t.pumpAndSettle();
      await t.tap(find.text('Edit Details'));
      await t.pumpAndSettle();
      expect(t.widget<TextFormField>(find.widgetWithText(TextFormField, 'Phone'))
          .controller!.text, '504-555-0100');
      await capture(t, key, 'edit-full-details-top');
      await t.drag(find.byType(SingleChildScrollView).last, const Offset(0, -450));
      await t.pumpAndSettle();
      await capture(t, key, 'edit-full-details-bottom');
      await t.ensureVisible(find.widgetWithText(TextFormField, 'Phone'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Phone'),
        '5045550102',
      );
      expect(t.widget<TextFormField>(find.widgetWithText(TextFormField, 'Phone'))
          .controller!.text, '504-555-0102');
      await t.tap(find.text('Save'));
      await settle(t);
      final saved = (await t.runAsync(() => cache.read('shop', 'm', grant)))!;
      expect(saved['pending'], {'phone': '5045550102'});
      expect((saved['details'] as Map)['name'], 'Synthetic Mechanic');
      t.view.physicalSize = const Size(360, 640);
      await t.pumpAndSettle();
      await capture(t, key, 'next-employee-small');
      expect(t.takeException(), isNull);
      await t.runAsync(auth.revoke);
      await t.pump(const Duration(seconds: 3));
      expect(find.text('fixture@example.invalid'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('an empty local employee profile asks for an online load without opening a blank editor',
      (t) async {
    size(t, width: 360, height: 780);
    final key = GlobalKey();
    await t.pumpWidget(app(LocalEmployeeDetailsScreen(
      businessId: 'shop', employeeId: 'm', rosterName: 'Synthetic Mechanic',
      rosterPosition: 'Mechanic', nicknameStore: Nicknames(),
      unlockOwner: auth.authorizeSession,
    ), key));
    await settle(t);
    expect(find.text('Load existing employee details'), findsOneWidget);
    expect(find.textContaining('Turn off Force Offline first'), findsOneWidget);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Edit Details')).onPressed,
        isNull);
    await capture(t, key, 'empty-employee-first-load');
    await t.scrollUntilVisible(find.text('Nickname'), 250);
    await t.tap(find.text('Nickname'));
    await t.pumpAndSettle();
    expect(find.text('Edit Nickname'), findsOneWidget);
    expect(find.textContaining('Connect once'), findsNothing);
    await capture(t, key, 'edit-nickname-dialog');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'compact summary and real editable gross retain payment arithmetic',
    (t) async {
      size(t);
      final key = GlobalKey();
      var calls = 0;
      int? net, adjustment;
      await t.pumpWidget(
        app(
          Scaffold(
            appBar: const ApprovedTasksHeader(title: 'Employee Profile'),
            body: WeeklyLaborReview(
              employeeId: 'm',
              employeeName: 'Kam',
              tasks: [task()],
              week: week,
              profileLayout: true,
              savedRateCents: 3500,
              advanceBalance: () async => 0,
              recordPayment: (w, d, m, s, a, r, n, why, b) async {
                calls++;
                net = n;
                adjustment = a;
              },
              saveDraft: (w, s, a, r, why) async {},
            ),
          ),
          key,
        ),
      );
      await t.pumpAndSettle();
      await capture(t, key, 'next-payroll-tiles');
      await t.scrollUntilVisible(
        find.text('New Payment'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await t.pumpAndSettle();
      await capture(t, key, 'next-weekly-summary');
      await t.ensureVisible(find.byKey(const Key('verify-weekly-payment')));
      await t.tap(find.byKey(const Key('verify-weekly-payment')));
      await t.pumpAndSettle();
      final field = find.byKey(const Key('verify-final-gross'));
      expect(t.widget<TextField>(field).controller!.text, '490.00');
      await capture(t, key, 'next-verify-payment');
      await t.enterText(field, '560.00');
      await t.enterText(
        find.widgetWithText(TextField, 'Payment note or adjustment reason'),
        'Owner-approved bonus',
      );
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await t.pumpAndSettle();
      t.view.physicalSize = const Size(360, 640);
      await t.pumpAndSettle();
      await capture(t, key, 'next-verify-small');
      await t.ensureVisible(find.text('Record payment'));
      await t.tap(find.text('Record payment'));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(net, 56000);
      expect(adjustment, 7000);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'history customer-first cards use recorded amounts and three real links',
    (t) async {
      size(t);
      final key = GlobalKey();
      final unlocked = ValueNotifier(true);
      addTearDown(unlocked.dispose);
      String? job, invoice, openedTask;
      final row = {
        ...task(),
        'credit_id': 'credit',
        'gross_cents': 49000,
        'method': 'Zelle',
        'verified_date': '2026-11-13',
        'operation_id': 'saved-payment',
      };
      await t.pumpWidget(
        app(
          Scaffold(
            body: PayrollHistoryPanel(
              employeeName: 'Kam',
              unlocked: unlocked,
              onOpenJob: (v) => job = v,
              onOpenInvoice: (v) => invoice = v,
              onOpenTask: (v) => openedTask = v['task_id'] as String,
              payments: [
                {
                  'week': '2026-11-09',
                  'gross': 56000,
                  'repayment': 0,
                  'net': 56000,
                  'method': 'Zelle',
                  'verified_date': '2026-11-13',
                  'work': [row],
                },
              ],
            ),
          ),
          key,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Paid portion'));
      await t.pumpAndSettle();
      expect(find.text('Kam — Weekly Payroll Details'), findsOneWidget);
      expect(
        find.textContaining('Job J-51 · Synthetic Customer'),
        findsOneWidget,
      );
      expect(find.text('View Task'), findsNothing);
      expect(find.text(r'$560.00'), findsWidgets);
      await capture(t, key, 'next-history-collapsed');
      await t.tap(find.textContaining('Job J-51 · Synthetic Customer'));
      await t.pumpAndSettle();
      await capture(t, key, 'next-history-expanded');
      await t.tap(find.text('View Task'));
      await t.tap(find.text('Open Job'));
      await t.tap(find.text('Open Invoice'));
      expect(openedTask, 'original-task');
      expect(job, 'job');
      expect(invoice, 'invoice');
      t.view.physicalSize = const Size(360, 640);
      await t.pumpAndSettle();
      await capture(t, key, 'next-history-small');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'empty assignments collapse, manual choice works, employee and week reset defaults',
    (t) async {
      size(t);
      final key = GlobalKey();
      String id = 'adam';
      DateTime current = week;
      List<Map<String, dynamic>> rows = [];
      late StateSetter update;
      await t.pumpWidget(
        app(
          Scaffold(
            appBar: const ApprovedTasksHeader(title: 'Employee Profile'),
            body: StatefulBuilder(
              builder: (c, set) {
                update = set;
                return EmployeeWorkReview(
                  employeeId: id,
                  employeeName: 'Adam',
                  week: current,
                  rows: rows,
                  jobs: const [],
                  onWeekChanged: (w) => set(() => current = w),
                  onJob: (_) {},
                );
              },
            ),
          ),
          key,
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('No current assigned tasks.').hitTestable(),
        findsNothing,
      );
      await capture(t, key, 'next-empty-tasks');
      await t.tap(find.text('Currently Assigned Tasks (0)'));
      await t.pumpAndSettle();
      expect(
        find.text('No current assigned tasks.').hitTestable(),
        findsOneWidget,
      );
      update(() => current = current.add(const Duration(days: 7)));
      await t.pumpAndSettle();
      expect(
        find.text('No current assigned tasks.').hitTestable(),
        findsNothing,
      );
      update(() {
        id = 'kam';
        rows = [
          {...task(), 'state': 'In Progress'},
        ];
      });
      await t.pumpAndSettle();
      expect(
        find.text('Oil change and service inspection').hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'advances collapse at zero and retain editing, repayment history and gray Taxes',
    (t) async {
      size(t);
      final key = GlobalKey();
      final identity = await PayrollLanIdentity.fromSeed(List.filled(32, 3));
      final values = <String, String>{};
      final lease = PayrollOwnerLease(
        identity: identity,
        business: 'shop',
        anchor: identity.deviceId,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
      );
      final network = PayrollOwnerLan(
        lease: lease,
        database: database,
        actor: who.actorId,
        approve: (_) async => null,
      );
      addTearDown(network.close);
      await t.pumpWidget(
        app(
          PayrollUiScope(
            database: database,
            unlock: auth.authorizeSession,
            connection: network,
            debugAllowOwnerView: true,
            child: OwnerPayrollScreen(
              businessId: 'shop',
              employeeId: 'm',
              employeeName: 'Kam',
              employeeRole: 'Mechanic',
              initialWeek: week,
              initialTab: 1,
              database: database,
              unlockOwner: auth.authorizeSession,
              ownerConnection: network,
            ),
          ),
          key,
        ),
      );
      await settle(t);
      await t.scrollUntilVisible(
        find.text('Advances & Repayments'),
        350,
        scrollable: find.byType(Scrollable).last,
      );
      await t.pumpAndSettle();
      expect(find.text('Adjust Amount Owed'), findsNothing);
      await capture(t, key, 'next-advances-collapsed');
      await t.tap(find.text('Advances & Repayments'));
      await t.pumpAndSettle();
      expect(find.text('Adjust Amount Owed'), findsOneWidget);
      expect(find.text('Repayment History'), findsOneWidget);
      await capture(t, key, 'next-advances-expanded');
      await t.ensureVisible(find.text('Record Repayment'));
      await t.pumpAndSettle();
      await t.tap(find.text('Record Repayment'));
      await t.pumpAndSettle();
      expect(find.text('Repayment method'), findsOneWidget);
      await t.ensureVisible(find.text('Save Repayment'));
      await t.pumpAndSettle();
      expect(find.text('Notes (optional)'), findsOneWidget);
      await t.ensureVisible(find.text('Repayment History'));
      await t.pumpAndSettle();
      await t.tap(find.text('Repayment History'));
      await t.pumpAndSettle();
      await capture(t, key, 'next-advances-history');
      await t.tap(find.byKey(const ValueKey('profile-tab-Taxes')));
      await t.pumpAndSettle();
      expect(find.text('Taxes'), findsWidgets);
      expect(find.text('Taxes & 1099'), findsNothing);
      await capture(t, key, 'next-taxes');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('issue459: Work survives Payroll Reports Taxes round trip', (t) async {
    size(t);
    final identity = await PayrollLanIdentity.fromSeed(List.filled(32, 8));
    final values = <String, String>{};
    final lease = PayrollOwnerLease(
      identity: identity, business: 'shop', anchor: identity.deviceId,
      read: (k) async => values[k],
      write: (k, v) async { values[k] = v; },
    );
    final network = PayrollOwnerLan(
      lease: lease, database: database, actor: who.actorId,
      approve: (_) async => null,
    );
    addTearDown(network.close);
    await t.pumpWidget(app(PayrollUiScope(
      database: database, unlock: auth.authorizeSession,
      connection: network, debugAllowOwnerView: true,
      child: OwnerPayrollScreen(
        businessId: 'shop', employeeId: 'm',
        employeeName: 'Chris', employeeRole: 'Mechanic',
        initialWeek: week, initialTab: 0, database: database,
        unlockOwner: auth.authorizeSession, ownerConnection: network,
      ),
    ), GlobalKey()));
    await settle(t);
    expect(find.byKey(const Key('employee-work-review')), findsOneWidget);
    for (final tab in ['Payroll', 'Reports', 'Taxes', 'Work']) {
      await t.tap(find.byKey(ValueKey('profile-tab-$tab')));
      await t.pumpAndSettle();
    }
    expect(find.byKey(const Key('employee-work-review')), findsOneWidget);
    expect(find.textContaining('Currently Assigned Tasks'), findsWidgets);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

}
