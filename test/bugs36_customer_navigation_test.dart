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
import 'package:briskers_app/screens/jobs/job_detail_screen.dart';
import 'package:briskers_app/screens/customers/customer_detail_screen.dart';
import 'bugs35_shared_design_test.dart' show capture;

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Navigation must remain offline');
}

void main() {
  setUp(loadHandoffFonts);
  testWidgets(
    'Job to customer tabs and back preserves vehicle and all saved rows without Save',
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
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      debugUseLocalDatabase(db);
      addTearDown(() async {
        debugUseLocalDatabase(null);
        await db.close();
        HttpOverrides.global = old;
        await BriskersConnectionModeController.instance.setMode(
          BriskersConnectionMode.auto,
        );
      });
      await tester.runAsync(() async {
        await db.customStatement(
          "INSERT INTO local_customers(id,business_id,display_name) VALUES('c','shop','Terrance Sanders')",
        );
        await db.customStatement(
          "INSERT INTO local_vehicles(id,business_id,year,make,model) VALUES('v','shop',2016,'Mercedes','C300')",
        );
        await db.customStatement(
          "INSERT INTO local_customer_vehicles(business_id,customer_id,vehicle_id) VALUES('shop','c','v')",
        );
        await db.customStatement(
          "INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,status,customer_id,customer_name,vehicle_id,vehicle_label,capabilities_json) VALUES('j','shop','full','J-56','Oil control valve','in_progress','c','Terrance Sanders','v','2016 Mercedes C300','{\"manage_job\":true,\"view_financial\":true}')",
        );
      });
      final before = (await tester.runAsync(
        () => db.customSelect('SELECT * FROM local_jobs').getSingle(),
      ))!.data;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: BriskersApp.applicationTheme,
          home: RepaintBoundary(
            key: key,
            child: const JobDetailScreen(
              businessId: 'shop',
              jobId: 'j',
              roleCode: 'owner',
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await settle();
      for (var repeat = 0; repeat < 2; repeat++) {
        await tester.tap(find.text('Terrance Sanders').first);
        await settle();
        expect(find.byType(CustomerDetailScreen), findsOneWidget);
        for (final tab in ['Overview', 'Info', 'Vehicles', 'Notes']) {
          await tester.tap(find.text(tab).first);
          await settle();
          expect(find.byType(FloatingActionButton), findsOneWidget);
          expect(find.text('New'), findsOneWidget);
          expect(find.textContaining('Coming Soon'), findsNothing);
          if (repeat == 0 && tab == 'Overview') {
            await tester.tap(find.text('New'));
            await settle();
            for (final action in [
              'Create job',
              'Create estimate',
              'Schedule appointment',
              'Add vehicle',
              'Add note',
            ]) {
              expect(find.text(action), findsOneWidget);
            }
            await tester.pageBack();
            await settle();
          }
        }
        await tester.pageBack();
        await settle();
        expect(find.text('2016 Mercedes C300'), findsOneWidget);
        expect(find.text('No vehicle'), findsNothing);
      }
      final after = (await tester.runAsync(
        () => db.customSelect('SELECT * FROM local_jobs').getSingle(),
      ))!.data;
      expect(after, before);
      expect(
        (await tester.runAsync(
          () => db.customSelect('SELECT * FROM sync_outbox').get(),
        ))!,
        isEmpty,
      );
      expect(
        (await tester.runAsync(
          () => db.customSelect('SELECT * FROM local_vehicles').get(),
        ))!.length,
        1,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'bugs36-handoff-job-navigation');
      await tester.pumpWidget(const SizedBox.shrink());
      await settle();
    },
  );
}
