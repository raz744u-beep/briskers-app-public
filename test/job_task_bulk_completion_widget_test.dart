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
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _NoInternet extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Assignments must work offline');
}

void main() {
  testWidgets(
    'Mark All Done confirms six tasks once below job header, supports cancel and offline completion',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'briskers_job_employees_shop': jsonEncode([
          {
            'id': 'kam',
            'name': 'Kam',
            'nickname': 'Kam',
            'position': 'Mechanic',
          },
        ]),
      });
      FlutterSecureStorage.setMockInitialValues({});
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.offline,
      );
      final previous = HttpOverrides.current;
      HttpOverrides.global = _NoInternet();
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      const who = OwnerSessionIdentity('owner', 'fixture');
      final auth = LocalOwnerAuthorization(
        store: _Unused(),
        currentIdentity: () => who,
        verifyOwner: (_) async => throw StateError('No cloud'),
        authenticateDevice: () async => throw StateError('No extra unlock'),
        verifyLocalOwner: (s) async => VerifiedOwnerEnrollment(who, s),
      );
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
      await lease.migrate(await auth.authorizeSession('shop'));
      final network = PayrollOwnerLan(
        lease: lease,
        database: db,
        actor: 'owner',
        approve: (_) async => null,
      );
      addTearDown(() async {
        await network.close();
        await db.close();
        LocalDocumentDetailCache.sqliteWritesEnabled = false;
        HttpOverrides.global = previous;
        await BriskersConnectionModeController.instance.setMode(
          BriskersConnectionMode.auto,
        );
      });
      final repo = LocalPayrollRepository(db, business: 'shop', owner: true);
      final detail = <String, dynamic>{
        'id': 'invoice',
        'kind': 'invoice',
        'job_id': 'job',
        'total_amount': 100,
        'paid_amount': 100,
        'pending_payment': 0,
        'status': 'paid',
        'lines': [
          for (var i = 0; i < 6; i++)
            {
              'id': 'labor-$i',
              'line_kind': 'labor',
              'description': 'Repair $i',
              'quantity': i == 5 ? 1.5 : 2,
            },
        ],
      };
      await tester.runAsync(() async {
        await repo.prepare();
        await LocalDocumentDetailCache.initialize(db);
        await db.customStatement(
          "INSERT INTO local_jobs(id,business_id,access_scope,title,customer_name,status,job_number,assigned_employee_id,assigned_employee_name) VALUES('job','shop','owner','Damien Hester','Damien Hester','open','J-53','kam','Kam')",
        );
        await db.customStatement(
          "INSERT INTO local_documents(document_date,id,business_id,job_id,kind,document_number) VALUES('2026-11-11','invoice','shop','job','invoice','6370')",
        );
        await LocalDocumentDetailCache(
          database: db,
        ).save('shop', 'invoice', detail);
        await repo.saveEmployeeCompensation(
          employee: 'kam',
          name: 'Kam',
          rate: 3500,
          weeklyBase: false,
        );
        await repo.setMainMechanic('job', 'kam', 'Kam');
      });
      await tester.pumpWidget(
        PayrollUiScope(
          database: db,
          unlock: auth.authorizeSession,
          connection: network,
          debugAllowOwnerView: true,
          child: MaterialApp(
            home: OwnerPayrollScreen(
              businessId: 'shop',
              jobId: 'job',
              database: db,
            ),
          ),
        ),
      );
      Future<void> until(Finder f) async {
        for (var i = 0; i < 150; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (f.evaluate().isNotEmpty) return;
        }
        expect(
          f,
          findsWidgets,
          reason: tester.allWidgets
              .whereType<Text>()
              .map((w) => w.data)
              .join(' | '),
        );
      }

      Future<void> click(Finder f) async {
        await until(f);
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      final button = find.byKey(const Key('job-mark-all-done'));
      await until(button);
      expect(
        tester.getTopLeft(button).dy,
        greaterThan(tester.getBottomLeft(find.text('J-53 · Damien Hester')).dy),
      );
      await click(button);
      await until(find.textContaining('Complete 6 tasks for this job?'));
      expect(find.byType(AlertDialog), findsOneWidget);
      await click(find.text('Cancel'));
      await tester.runAsync(() async {
        expect(
          (await repo.work(job: 'job')).every((r) => r['state'] == 'Open'),
          isTrue,
        );
      });
      await click(button);
      await until(find.byType(AlertDialog));
      await click(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Mark All Done'),
        ),
      );
      await until(find.text('6 tasks marked Done.'));
      await tester.runAsync(() async {
        final rows = await repo.work(job: 'job');
        expect(
          rows.every((r) => r['state'] == 'Done' && r['paid_minutes'] == 0),
          isTrue,
        );
        expect(
          rows.fold<int>(0, (n, r) => n + (r['actual_minutes'] as int)),
          690,
        );
        expect(await repo.historyWithWork('kam'), isEmpty);
      });
      for (var i = 0; i < 50 && button.evaluate().isNotEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(button, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
