import 'support/handoff_qa_fonts.dart';
import 'package:briskers_app/widgets/vehicle_findings.dart';
import 'package:briskers_app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/customer_service_visit_card.dart';
import 'package:briskers_app/screens/payroll/service_task_editor.dart';
import 'bugs35_shared_design_test.dart' show capture;

void main() {
  setUp(loadHandoffFonts);
  testWidgets('Not Applicable dialog preserves explicit confirmation and optional note',(tester)async{
    String? saved;
    Future<void> noop(Map<String,dynamic> f)async{}
    await tester.pumpWidget(MaterialApp(theme:BriskersApp.applicationTheme,home:Scaffold(body:SingleChildScrollView(child:VehicleFindings(
      findings:const [{'id':'finding','status':'open','body':'Original concern'}],
      onEdit:noop,onAddPhotos:noop,onAddToJob:noop,onResolve:noop,onReopen:noop,onInvoiceChanged:(_,_)async{},
      onNotApplicable:(_,note)async{saved=note;})))));
    await tester.tap(find.text('Not Applicable'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'Repaired elsewhere');
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();expect(saved,isNull);
    await tester.tap(find.text('Not Applicable'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'Repaired elsewhere');
    await tester.tap(find.text('Confirm'));await tester.pumpAndSettle();expect(saved,'Repaired elsewhere');expect(tester.takeException(),isNull);
  });
  testWidgets(
    'two-line visit has independent neutral job and invoice links and expandable truthful bullets',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var jobs = 0, invoices = 0;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: BriskersApp.applicationTheme,
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CustomerServiceVisitCard(
                  date: 'Nov 12, 2026',
                  jobNumber: 'J-56',
                  vehicle: '2016 Mercedes C300',
                  status: 'in_progress',
                  completed: const ['Replace oil control valve'],
                  pending: const ['Inspect engine for oil leaks'],
                  invoices: [(number: '#6376', open: () => invoices++)],
                  onJob: () => jobs++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Replace oil control valve'), findsNothing);
      await tester.tap(find.text('J-56'));
      await tester.pump();
      expect(jobs, 1);
      expect(invoices, 0);
      expect(find.text('Replace oil control valve'), findsNothing);
      await tester.tap(find.text('#6376'));
      await tester.pump();
      expect(invoices, 1);
      expect(jobs, 1);
      await tester.tap(find.text('2016 Mercedes C300'));
      await tester.pump();
      expect(find.text('Completed work'), findsOneWidget);
      expect(
        find.text('Invoice work · completion not confirmed'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'bugs36-handoff-visit');
    },
  );
  testWidgets(
    'new labor defaults Open and unpaid without status or Needs Review selectors',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ServiceTaskDraft? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: BriskersApp.applicationTheme,
          home: ServiceTaskEditor(
            jobs: const [
              {
                'id': 'j',
                'job_number': 'J-56',
                'customer_name': 'Terrance',
                'vehicle_label': '2016 Mercedes C300',
              },
            ],
            employees: const [
              {'id': 'kam', 'name': 'Kam'},
            ],
            initial: ServiceTaskDraft(
              job: 'j',
              description: 'Repair',
              mechanics: [TaskMechanicDraft('kam', 300)],
              start: '2026-11-13',
              end: '2026-11-13',
              priority: 'Normal',
              status: 'Done',
              treatment: 'review',
            ),
            save: (v) async {
              saved = v;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-status')), findsNothing);
      expect(
        find.byKey(const ValueKey('task-payroll-treatment')),
        findsNothing,
      );
      await tester.tap(find.text('Save Task'));
      await tester.pumpAndSettle();
      expect(saved!.status, 'Open');
      expect(saved!.treatment, 'unpaid');
      expect(saved!.mechanics.single.minutes, 300);
    },
  );
}
