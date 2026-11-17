import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/screens/jobs/job_create_screen.dart';
import 'package:briskers_app/screens/jobs/job_edit_screen.dart';
import 'package:briskers_app/services/local_job_work_date.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:briskers_app/widgets/job_compact_card.dart';
import 'package:briskers_app/widgets/job_date_field.dart';
import 'bugs35_shared_design_test.dart' show capture;

void main() {
  late BriskersLocalDatabase db;
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.offline,
    );
    db = BriskersLocalDatabase(NativeDatabase.memory());
    debugUseLocalDatabase(db);
    await db.customStatement(
      "INSERT INTO local_customers(id,business_id,display_name) VALUES('customer','shop','Nathan Hogue')",
    );
    final font = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (await font.exists()) {
      await (FontLoader('Roboto')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
    final icons = File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(await icons.readAsBytes())),
          ))
          .load();
    }
  });
  tearDown(() async {
    debugUseLocalDatabase(null);
    await db.close();
  });
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets(
    'Create Job shows shop-local Job Date and edits it in the existing form',
    (t) async {
      phone(t);
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: const JobCreateScreen(
              businessId: 'shop',
              customerId: 'customer',
              customerName: 'Nathan Hogue',
              vehicles: [],
              roleCode: 'owner',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Job Date'), findsOneWidget);
      expect(
        t.widget<JobDateField>(find.byType(JobDateField)).value,
        LocalJobWorkDate.today(),
      );
      await t.tap(find.byType(JobDateField));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Switch to input'));
      await t.pumpAndSettle();
      await t.enterText(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(TextField),
        ),
        '11/5/2026',
      );
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(
        t.widget<JobDateField>(find.byType(JobDateField)).value,
        DateTime(2026, 11, 5),
      );
      await capture(t, key, 'quick-job-create-date');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Edit closed job loads saved Job Date; title cards keep compact repair fallback',
    (t) async {
      phone(t);
      final key = GlobalKey();
      late String id;
      await t.runAsync(() async {
        id = await OfflineJobAdminService(database: db).queueJobCreate(
          'shop',
          customerId: 'customer',
          customerName: 'Nathan Hogue',
          title: 'Invoice',
          jobDate: DateTime(2026, 11, 5),
        );
      });
      await t.pumpWidget(
        MaterialApp(
          initialRoute: '/edit',
          routes: {
            '/': (_) => const Scaffold(),
            '/edit': (_) => RepaintBoundary(
              key: key,
              child: JobEditScreen(
                businessId: 'shop',
                job: {
                  'id': id,
                  'customer_id': 'customer',
                  'title': 'Invoice',
                  'status': 'closed',
                },
              ),
            ),
          },
        ),
      );
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(
        t.widget<JobDateField>(find.byType(JobDateField)).value,
        DateTime(2026, 11, 5),
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Invoice'),
        'Nathan scheduled maintenance',
      );
      await t.pumpAndSettle();
      await capture(t, key, 'quick-job-edit-date-title');
      await t.ensureVisible(find.text('Save changes'));
      await t.tap(find.text('Save changes'));
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      await t.runAsync(() async {
        expect(
          (await db.customSelect('SELECT title FROM local_jobs').get())
              .single
              .data['title'],
          'Nathan scheduled maintenance',
        );
        expect(
          await LocalJobWorkDate(db).read('shop', id),
          DateTime(2026, 11, 5),
        );
      });
      await t.pumpWidget(
        MaterialApp(
          key: const ValueKey('cards'),
          home: Scaffold(
            body: Column(
              children: [
                for (final title in ['Nathan scheduled maintenance', 'Invoice'])
                  JobCompactCard(
                    job: {
                      'job_number': 'J-54',
                      'customer_name': 'Nathan Hogue',
                      'title': title,
                      'work_summary': 'Oil Change · Brake Flush',
                    },
                    statusControl: const Text('Open'),
                    onOpen: () {},
                    approvedListDesign: true,
                  ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Nathan scheduled maintenance'), findsOneWidget);
      expect(find.text('Oil Change · Brake Flush'), findsOneWidget);
      expect(find.text('Invoice'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
