import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:briskers_app/screens/payroll/job_tasks_access.dart';
import 'package:briskers_app/screens/documents_screen.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/invoice_payment_feed.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/widgets/invoice_labor_summary.dart';
import 'package:briskers_app/widgets/job_list_approved_card.dart';
import 'package:briskers_app/screens/payroll/tasks_workspace.dart';
import 'package:briskers_app/screens/jobs/invoice_warranty_panel.dart';

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/payroll-qa/bugs35-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final icon = File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await icon.exists()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(await icon.readAsBytes())),
          ))
          .load();
    }
    final file = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (await file.exists()) {
      await (FontLoader('Roboto')..addFont(
            Future.value(ByteData.sublistView(await file.readAsBytes())),
          ))
          .load();
    }
  });
  testWidgets(
    'actual offline Invoices list shares cards with independent payment status',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.offline,
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: _CaptureBoundary(
            key: key,
            child: DocumentsScreen(
              businessId: 'fixture-shop',
              kind: 'invoice',
              roleCode: 'owner',
              isOwner: true,
              showAppBar: false,
              localDocuments: _FixtureInvoices(db),
              paymentFeed: _FixturePayments(db),
              blockedDocumentIds: (_) async => <String>{},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(JobListApprovedCard), findsNWidgets(2));
      expect(find.text('Total: \$100.00'), findsOneWidget);
      expect(find.text('Unpaid'), findsNothing);
      expect(find.text('Invoice #6372'), findsOneWidget);
      expect(find.text('Total: \$600.00'), findsOneWidget);
      expect(find.descendant(of:find.byType(JobListApprovedCard),matching:find.byIcon(Icons.chevron_right)), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'invoices');
    },
  );
  testWidgets(
    'Service Tasks uses shared card and retains expansion and exact invoice navigation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _CaptureBoundary(
              key: key,
              child: TasksWorkspace(
                serviceTasks: const [
                  {
                    'job_id': 'job',
                    'job_number': 'J-49',
                    'customer_name': 'Rick Francis',
                    'vehicle_label': '2016 Mercedes E350',
                    'invoice_number': '6368',
                    'invoice_id': 'invoice-id',
                    'line_id': 'line',
                    'source_description': 'Battery programming + oil change',
                    'status': 'in_progress',
                  },
                  {
                    'job_id': 'job',
                    'job_number': 'J-49',
                    'line_id': 'completed-line',
                    'source_description': 'Completed inspection',
                    'status': 'done',
                  },
                ],
                generalTasks: const [],
                allocationsByLine: const {
                  'line': [
                    {
                      'id': 'a',
                      'employee_id': 'chris',
                      'estimated_minutes': 120,
                    },
                  ],
                },
                employeeName: (_) => 'Chris',
                employeeIds: const ['chris'],
                serviceTaskCard: (_) =>
                    const Text('Existing Start/Finish controls'),
                onAddGeneral: () {},
                onGeneralStatus: (_, _) async {},
                onOpenJob: (_) {},
                onEmployeeTap: (_) {},
                onOpenInvoice: (id) => opened = id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(JobListApprovedCard), findsOneWidget);
      expect(find.text('Chris · 2.0 hrs'), findsOneWidget);
      expect(find.text('1 of 2 tasks completed'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(tester.widget<Card>(find.byType(Card).last).color, Colors.white);
      await capture(tester, key, 'service-tasks');
      await tester.tap(find.text('Invoice #6368'));
      expect(opened, 'invoice-id');
      await tester.tap(find.text('J-49  Rick Francis'));
      await tester.pumpAndSettle();
      expect(find.text('Existing Start/Finish controls'), findsNothing);
      await tester.tap(find.text('Battery programming + oil change').last);
      await tester.pumpAndSettle();
      expect(find.text('Existing Start/Finish controls'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Invoice mechanic row and summary use saved single and multiple assignments',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.runAsync(() async {
        await LocalPayrollRepository(
          db,
          business: 'shop',
          owner: true,
        ).prepare();
        await db.customStatement(
          "INSERT INTO local_jobs(id,business_id,access_scope,title,status,assigned_employee_id,assigned_employee_name) VALUES('job','shop','owner','Repair','open','Chris','Chris')",
        );
        await db.customStatement(
          "INSERT INTO regular_payroll_task_sources VALUES('shop','task','invoice','line','invoice',1)",
        );
        for (final e in ['Chris', 'Kam']) {
          await db.customStatement(
            "INSERT INTO regular_payroll_employees(business_id,id,name,rate) VALUES('shop',?,?,3500)",
            [e, e],
          );
          await db.customStatement(
            "INSERT INTO regular_payroll_portions(business_id,id,task_id,employee_id,state) VALUES('shop',?,'task',?,'Open')",
            [e, e],
          );
          await db.customStatement(
            "INSERT INTO regular_payroll_estimates VALUES('shop','task',?,?)",
            [e, e == 'Chris' ? 240 : 120],
          );
        }
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _CaptureBoundary(
              key: key,
              child: InvoiceWarrantyPanel(
                businessId: 'shop',
                documentId: 'invoice',
                expectedVersion: 1,
                invoiceTotal: 100,
                detail: const {'extended_warranty': false},
                onChanged: () async {},
                paymentProcessed: false,
                mainMechanic: SizedBox(
                  key: const Key('invoice-main-mechanic-selector'),
                  height: 50,
                  child: JobTasksAccess(
                    business: 'shop',
                    job: 'job',
                    invoice: 'invoice',
                    database: db,
                    selectorOnly: true,
                  ),
                ),
                laborSummary: InvoiceLaborSummary(
                  business: 'shop',
                  invoice: 'invoice',
                  database: db,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Chris 4.0 hrs'), findsOneWidget);
      expect(find.text('Kam 2.0 hrs'), findsOneWidget);
      expect(find.text('Total 6.0 hrs'), findsOneWidget);
      expect(
        tester.getCenter(find.byType(Checkbox)).dy,
        closeTo(
          tester
              .getCenter(
                find.byKey(const Key('invoice-main-mechanic-selector')),
              )
              .dy,
          3,
        ),
      );
      expect(
        tester
            .getTopLeft(find.byKey(const Key('invoice-assigned-labor-summary')))
            .dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.byKey(const Key('invoice-main-mechanic-selector')),
              )
              .dy,
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'invoice-mechanics');
      await tester.runAsync(() async {
        await db.customStatement(
          "DELETE FROM regular_payroll_portions WHERE id='Kam'",
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceLaborSummary(
            business: 'shop',
            invoice: 'invoice',
            revision: 1,
            database: db,
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Total 4.0 hrs'), findsOneWidget);
      expect(find.text('Kam 2.0 hrs'), findsNothing);
    },
  );
}

class _FixtureInvoices extends LocalDocumentRepository {
  _FixtureInvoices(BriskersLocalDatabase db) : super(database: db);
  @override
  Future<List<Map<String, dynamic>>> listByKind(
    String businessId, {
    required String kind,
  }) async => [
    {
      'id': 'invoice',
      'kind': 'invoice',
      'document_number': '6372',
      'job_number': 'J-52',
      'customer_name': 'Norman Louis',
      'vehicle': '2023 Audi Q3',
      'title': 'Front wheel liner repair',
      'total_amount': 600,
      'paid_amount': 200,
      'pending_payment': 0,
      'status': 'issued',
      'display_status': 'Open',
      '_local_snapshot': true,
    },
    {
      'id': 'historical',
      'kind': 'invoice',
      'document_number': '6373',
      'customer_name': 'Historical customer',
      'total_amount': 100,
      'status': 'closed',
      'display_status': 'Closed',
      '_local_snapshot': true,
    },
  ];
}

class _FixturePayments extends InvoicePaymentFeed {
  _FixturePayments(BriskersLocalDatabase db) : super(database: db);
  @override
  Future<List<Map<String, dynamic>>> load(String businessId) async => [
    {'invoice_id': 'invoice', 'amount': 200},
  ];
}

class _CaptureBoundary extends StatelessWidget {
  const _CaptureBoundary({required GlobalKey key, required this.child})
    : captureKey = key;
  final GlobalKey captureKey;
  final Widget child;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: captureKey,
    child: ColoredBox(color: const Color(0xFFF4F5FA), child: child),
  );
}
