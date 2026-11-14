import 'support/handoff_qa_fonts.dart';
import 'package:briskers_app/app.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/services/customer_detail_cache.dart';
import 'package:briskers_app/screens/customers/customer_service_history_section.dart';
import 'package:briskers_app/widgets/customer_service_visit_card.dart';
import 'bugs35_shared_design_test.dart' show capture;

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? c) =>
      throw StateError('History must work offline');
}

void main() {
  setUp(loadHandoffFonts);
  testWidgets(
    'offline history searches collapsed repairs/dates/invoices, filters vehicle and survives reopen',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.offline,
      );
      final old = HttpOverrides.current;
      HttpOverrides.global = _NoNetwork();
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('visit-history'),
      ))!;
      var db = BriskersLocalDatabase(
        NativeDatabase(File('${dir.path}/history.sqlite')),
      );
      debugUseLocalDatabase(db);
      addTearDown(() async {
        debugUseLocalDatabase(null);
        await db.close();
        await dir.delete(recursive: true);
        HttpOverrides.global = old;
        await BriskersConnectionModeController.instance.setMode(
          BriskersConnectionMode.auto,
        );
      });
      await tester.runAsync(() async {
        for (var i = 1; i <= 2; i++) {
          await db.customStatement(
            "INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,status,customer_id,customer_name,vehicle_id,vehicle_label,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            [
              'j$i',
              'shop',
              'full',
              'J-0$i',
              'Repair',
              i == 1 ? 'completed' : 'in_progress',
              'c',
              'Synthetic Customer',
              'v$i',
              '2016 Car $i',
              1794211200 + i * 86400,
            ],
          );
        }
        await const CustomerDetailCache().save('shop', 'c', 'service_history', {
          'jobs': [],
          'documents': [
            {
              'id': 'd1',
              'job_id': 'j1',
              'vehicle_id': 'v1',
              'kind': 'invoice',
              'document_number': '6011',
              'document_date': '2026-11-10',
              'status': 'closed',
              'lines': [
                {'description': 'Replace oil control valve'},
              ],
            },
            {
              'id': 'd2',
              'job_id': 'j2',
              'vehicle_id': 'v2',
              'kind': 'invoice',
              'document_number': '6012',
              'document_date': '2026-11-11',
              'status': 'open',
              'lines': [
                {'description': 'Inspect cooling system'},
              ],
            },
            {
              'id': 'orphan',
              'vehicle_id': 'v1',
              'kind': 'invoice',
              'document_number': '6009',
              'document_date': '2026-10-01',
              'status': 'paid',
              'lines': [
                {'description': 'Historic invoice-only repair'},
              ],
            },
          ],
        });
      });
      Future<void> settle() async {
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      final key = GlobalKey();
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: BriskersApp.applicationTheme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: RepaintBoundary(
                  key: key,
                  child: const CustomerServiceHistorySection(
                    businessId: 'shop',
                    customerId: 'c',
                    roleCode: 'owner',
                    initiallyExpanded: true,
                    vehicles: [
                      {'id': 'v1', 'year': 2016, 'make': 'Car', 'model': '1'},
                      {'id': 'v2', 'year': 2016, 'make': 'Car', 'model': '2'},
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await settle();
      }

      await open();
      expect(find.byType(CustomerServiceVisitCard), findsNWidgets(3));
      expect(
        tester
            .widgetList<CustomerServiceVisitCard>(
              find.byType(CustomerServiceVisitCard),
            )
            .first
            .jobNumber,
        'J-02',
      );
      expect(find.text('Replace oil control valve'), findsNothing);
      final search = find.byKey(
        const ValueKey('vehicle-repair-history-search'),
      );
      await tester.enterText(search, 'oil control');
      await tester.pump();
      expect(find.text('J-01'), findsOneWidget);
      expect(find.text('J-02'), findsNothing);
      await tester.tap(find.text('2016 Car 1'));
      await tester.pump();
      expect(find.text('Replace oil control valve'), findsOneWidget);
      expect(find.text('Completed work'), findsOneWidget);
      await tester.enterText(search, '6012');
      await tester.pump();
      expect(find.text('J-02'), findsOneWidget);
      expect(find.text('J-01'), findsNothing);
      await tester.tap(find.text('2016 Car 2'));
      await tester.pump();
      expect(
        find.text('Invoice work · completion not confirmed'),
        findsOneWidget,
      );
      await tester.enterText(search, '2026-10-01');
      await tester.pump();
      expect(find.text('#6009'), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pump();
      await tester.tap(find.text('All vehicles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2016 Car 2').last);
      await tester.pumpAndSettle();
      expect(find.text('J-01'), findsNothing);
      expect(find.text('J-02'), findsOneWidget);
      expect(find.textContaining('hours'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'bugs36-handoff-service-history');
      await tester.pumpWidget(const SizedBox.shrink());
      await settle();
      await tester.runAsync(() => db.close());
      db = BriskersLocalDatabase(
        NativeDatabase(File('${dir.path}/history.sqlite')),
      );
      debugUseLocalDatabase(db);
      await open();
      expect(find.byType(CustomerServiceVisitCard), findsNWidgets(3));
      expect(
        (await tester.runAsync(
          () => db.customSelect('SELECT * FROM sync_outbox').get(),
        ))!,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle();
    },
  );
}
