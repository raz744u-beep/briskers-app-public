import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:briskers_app/services/payroll_owner_lease.dart';
import 'package:briskers_app/services/payroll_owner_ledger.dart';
import 'package:briskers_app/services/payroll_owner_lan.dart';
import 'package:briskers_app/screens/payroll/owner_payroll_screen.dart';
import 'package:briskers_app/screens/payroll/payroll_ui_scope.dart';

class _Unused implements OwnerEnrollmentStore {
  @override Future<String?> read() async => null;
  @override Future<void> write(String value) async {}
  @override Future<void> clear() async {}
}
class _NoInternet extends HttpOverrides {
  @override HttpClient createHttpClient(SecurityContext? context) => throw StateError('Internet must not be used');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final currentHolder in [true, false]) {
    testWidgets('regular employee payroll records or holds payment safely, currentHolder=$currentHolder', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final previous = HttpOverrides.current;
      HttpOverrides.global = _NoInternet();
      final folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('regular-payroll-ui')))!;
      final file = File('${folder.path}/shop.sqlite');
      var db = BriskersLocalDatabase(NativeDatabase(file));
      final values = <String, String>{};
      final root = await PayrollLanIdentity.fromSeed(List.filled(32, 1));
      final identity = currentHolder ? root : await PayrollLanIdentity.fromSeed(List.filled(32, 2));
      const who = OwnerSessionIdentity('owner', 'regular-app-session');
      var devicePromptCount = 0;
      final auth = LocalOwnerAuthorization(store: _Unused(), currentIdentity: () => who,
        verifyOwner: (_) async => throw StateError('No Supabase required'),
        authenticateDevice: () async { devicePromptCount++; return true; },
        verifyLocalOwner: (shop) async => VerifiedOwnerEnrollment(who, shop));
      Future<LocalOwnerGrant> unlock(String shop) => auth.authorizeSession(shop);
      PayrollOwnerLease lease() => PayrollOwnerLease(identity: identity, business: 'shop', anchor: root.deviceId,
        read: (key) async => values[key], write: (key, value) async { values[key] = value; });
      var authority = lease();
      if (currentHolder) await authority.migrate(await unlock('shop'));
      var network = PayrollOwnerLan(lease: authority, database: db, actor: 'owner', approve: (_) async => null);
      addTearDown(() async {
        await network.close(); await db.close();
        LocalDocumentDetailCache.sqliteWritesEnabled = false;
        HttpOverrides.global = previous; await folder.delete(recursive: true);
      });
      final fixture = LocalPayrollRepository(db, business: 'shop', owner: true);
      await tester.runAsync(() async {
      await LocalDocumentDetailCache.initialize(db);
      await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) VALUES('job','shop','owner','Synthetic repair','open','J-TEST')");
      await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,kind,document_number) VALUES('invoice','shop','job','invoice','TEST-100')");
      for (final employee in ['a', 'b']) {
        await db.customStatement('INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id,employee_name) VALUES(?,?,?,?,?)',
          [employee, 'shop', 'job', employee, employee == 'a' ? 'Alice' : 'Bob']);
      }
      await LocalDocumentDetailCache(database: db).save('shop', 'invoice', {'id': 'invoice', 'kind': 'invoice',
        'job_id': 'job', 'lines': [{'id': 'labor', 'line_kind': 'labor', 'description': 'Shared repair', 'quantity': 1}]});
      final today = DateTime.now().toIso8601String().split('T').first;
      for (final employee in ['a', 'b']) {
        await fixture.registerAssignedLabor(jobId: 'job', invoiceId: 'invoice', lineId: 'labor',
          employeeId: employee, employeeName: employee == 'a' ? 'Alice' : 'Bob', rateCents: 4000);
        final work = (await fixture.work(employee: employee)).single;
        await fixture.updateWork(work['id'] as String, 'In Progress', 0, today);
        await fixture.updateWork(work['id'] as String, 'Done', 100, today);
      }
      });
      Future<void> until(Finder finder) async {
        for (var i = 0; i < 150; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 20));
          if (finder.evaluate().isNotEmpty) return;
        }
        expect(finder, findsWidgets, reason: tester.allWidgets.whereType<Text>().map((w) => w.data).join(' | '));
      }
      Widget screen({int tab = 0}) => MaterialApp(home: PayrollUiScope(
        database: db, unlock: unlock, connection: network, debugAllowOwnerView: true,
        child: OwnerPayrollScreen(
          businessId: 'shop', employeeId: 'a', employeeName: 'Alice', employeeRole: 'mechanic',
          database: db, unlockOwner: unlock, ownerConnection: network, initialTab: tab)));
      await tester.pumpWidget(screen());
      await until(find.widgetWithText(FilledButton, 'Verify Payment'));
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Payroll'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      if (currentHolder) {
        // Owner bookkeeping must not require the employee to own a paired phone.
        await tester.tap(find.text('Payroll'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Advances & Repayments'), 220,
          scrollable: find.byType(Scrollable).last);
        await tester.ensureVisible(find.text('Advances & Repayments'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Advances & Repayments'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('Edit opening balance'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Edit opening balance'));
        await tester.pump();
        await tester.enterText(find.widgetWithText(TextField, 'Original amount owed'), '5.00');
        await tester.pump();
        await tester.ensureVisible(find.byTooltip('Save opening balance'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Save opening balance'));
        await until(find.text(r'Remaining balance: $5.00'));
        await tester.ensureVisible(find.widgetWithText(TextField, 'Amount'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Amount'), '5.00');
        await tester.pump();
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save Repayment'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Save Repayment'));
        await until(find.text(r'Remaining balance: $0.00'));
        await tester.tap(find.text('Tasks'));
        await tester.pumpAndSettle();
        await until(find.widgetWithText(FilledButton, 'Verify Payment'));
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Verify Payment'));
      await until(find.widgetWithText(FilledButton, 'Record payment'));
      expect(find.text(r'Calculated labor: $40.00'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      if (currentHolder) {
        await until(find.text('Payment Recorded'));
        await tester.tap(find.widgetWithText(FilledButton, 'Done'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(() async {
          expect(await fixture.history('a'), hasLength(1));
          expect(await fixture.history('b'), isEmpty);
          expect((await fixture.work(employee: 'b')).single['remaining_cents'], 4000);
        });
      } else {
        await until(find.textContaining('Payment pending, not recorded'));
        expect(find.text('Payment Recorded'), findsNothing);
        await tester.runAsync(() async {
          expect(await fixture.history('a'), isEmpty);
          expect(await PayrollOwnerLedger(db, 'shop').pending(), hasLength(1));
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        await network.close(); await db.close();
        db = BriskersLocalDatabase(NativeDatabase(file));
        authority = lease();
        network = PayrollOwnerLan(lease: authority, database: db, actor: 'owner', approve: (_) async => null);
      });
      await tester.pumpWidget(screen(tab: 2));
      await until(find.text(currentHolder ? 'Payroll History' : 'Connect'));
      if (currentHolder) {
        await tester.runAsync(() async {
          final saved = await LocalPayrollRepository(db, business: 'shop', owner: true).history('a');
          expect(saved, hasLength(1)); expect(saved.single['net'], 4000);
          final reopened = LocalPayrollRepository(db, business: 'shop', owner: true);
          expect(await reopened.openingAdvance('a'), 500);
          expect(await reopened.advance('a'), 0);
          expect(await reopened.repaymentHistory('a'), hasLength(1));
        });
      } else {
        expect(find.textContaining('payment request(s) pending'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
      expect(devicePromptCount, 0,
        reason: 'Payroll, advances, repayments, actual payment and restart should use only the existing Briskers Owner login');
      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
