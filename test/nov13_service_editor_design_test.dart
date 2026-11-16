import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/service_task_editor.dart';
import 'bugs35_shared_design_test.dart' show capture;

const _jobs = [
  {
    'id': 'j53',
    'job_number': 'J-53',
    'customer_name': 'Damien Hester',
    'vehicle_label': '2014 Mercedes C250',
    'title': 'Invoice',
    'status': 'closed',
  },
];
const _staff = [
  {'id': 'kam', 'name': 'Kam'},
];
ServiceTaskDraft _draft({bool paid = false}) => ServiceTaskDraft(
  job: 'j53',
  description: 'Replace valve cover',
  mechanics: [
    TaskMechanicDraft('kam', 120, originalEmployee: 'kam', locked: paid),
  ],
  start: '2026-11-02',
  end: '2026-11-05',
  priority: 'Normal',
  status: paid ? 'Done' : 'Open',
  treatment: paid ? 'preserve' : 'unpaid',
);

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final entry in {
      'Roboto': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      'MaterialIcons':
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final file = File(entry.value);
      if (await file.exists()) {
        await (FontLoader(entry.key)..addFont(
              Future.value(ByteData.sublistView(await file.readAsBytes())),
            ))
            .load();
      }
    }
  });
  Future<void> mount(
    WidgetTester t,
    Widget child,
    GlobalKey captureKey, {
    double width = 390,
    double height = 844,
    double scale = 1,
    double keyboard = 0,
  }) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        initialRoute: '/editor',
        routes: {
          '/': (_) => const Scaffold(),
          '/editor': (_) => RepaintBoundary(
            key: captureKey,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(width, height),
                padding: const EdgeInsets.only(bottom: 32),
                viewPadding: const EdgeInsets.only(bottom: 32),
                viewInsets: EdgeInsets.only(bottom: keyboard),
                textScaler: TextScaler.linear(scale),
              ),
              child: child,
            ),
          ),
        },
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'approved paid editor pairs fields, opens job independently and preserves paid labor on date save',
    (t) async {
      final key = GlobalKey();
      ServiceTaskDraft? saved;
      String? opened;
      await mount(
        t,
        ServiceTaskEditor(
          jobs: _jobs,
          employees: _staff,
          editing: true,
          payrollLocked: true,
          statusLocked: true,
          initial: _draft(paid: true),
          onOpenJob: (id) => opened = id,
          save: (v) async => saved = v,
        ),
        key,
      );
      expect(
        t.getTopLeft(find.byKey(const ValueKey('mechanic-0-kam'))).dy,
        t.getTopLeft(find.byKey(const ValueKey('hours-0'))).dy,
      );
      expect(
        t.getTopLeft(find.byKey(const ValueKey('task-start-date'))).dy,
        t.getTopLeft(find.byKey(const ValueKey('task-end-date'))).dy,
      );
      expect(
        t.getTopLeft(find.byKey(const ValueKey('task-priority'))).dy,
        t.getTopLeft(find.byKey(const ValueKey('task-status'))).dy,
      );
      expect(find.text('Invoice'), findsNothing);
      expect(find.text('2014 Mercedes C250'), findsOneWidget);
      final saveTheme = Theme.of(
        t.element(find.widgetWithText(FilledButton, 'Save Task')),
      ).filledButtonTheme;
      expect(
        saveTheme.style?.backgroundColor?.resolve({}),
        const Color(0xFF08752B),
      );
      expect(
        find.byKey(const ValueKey('service-task-job')).hitTestable(),
        findsOneWidget,
      );
      await capture(t, key, 'service-editor-approved-paid');
      await t.tap(find.byKey(const ValueKey('service-task-job')));
      expect(opened, 'j53');
      expect(saved, isNull);
      await t.ensureVisible(find.byKey(const ValueKey('task-start-date')));
      await t.tap(find.byKey(const ValueKey('task-start-date')));
      await t.pumpAndSettle();
      await t.tap(find.text('3').last);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Paid labor: retain existing status'));
      await t.pumpAndSettle();
      await capture(t, key, 'service-editor-paid-protection');
      expect(
        find.byKey(const ValueKey('task-payroll-treatment')),
        findsNothing,
      );
      await t.tap(find.text('Save Task'));
      await t.pumpAndSettle();
      expect(saved!.start, '2026-11-03');
      expect(saved!.end, '2026-11-05');
      expect(saved!.status, 'Done');
      expect(saved!.treatment, 'preserve');
      expect(saved!.mechanics.single.minutes, 120);
      expect(saved!.mechanics.single.originalEmployee, 'kam');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'unpaid editor retains user input and prevents duplicate save while pending',
    (t) async {
      final key = GlobalKey();
      final pending = Completer<void>();
      var saves = 0;
      ServiceTaskDraft? saved;
      await mount(
        t,
        ServiceTaskEditor(
          jobs: _jobs,
          employees: _staff,
          editing: true,
          initial: _draft(),
          save: (v) async {
            saves++;
            saved = v;
            await pending.future;
          },
        ),
        key,
      );
      await t.enterText(find.byKey(const ValueKey('hours-0')), '3.5');
      await t.ensureVisible(find.byKey(const ValueKey('task-priority')));
      await t.tap(find.byKey(const ValueKey('task-priority')));
      await t.pumpAndSettle();
      await t.tap(find.text('High').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('task-status')));
      await t.tap(find.byKey(const ValueKey('task-status')));
      await t.pumpAndSettle();
      await t.tap(find.text('In Progress').last);
      await t.pumpAndSettle();
      await capture(t, key, 'service-editor-unpaid');
      await t.tap(find.text('Save Task'));
      await t.pump();
      await t.tap(find.text('Saving…'));
      await t.pump();
      expect(saves, 1);
      expect(saved!.mechanics.single.minutes, 210);
      expect(saved!.priority, 'High');
      expect(saved!.status, 'In Progress');
      expect(saved!.treatment, 'unpaid');
      pending.complete();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'narrow large-text editor scrolls every control above keyboard and Android navigation',
    (t) async {
      final key = GlobalKey();
      await mount(
        t,
        ServiceTaskEditor(
          jobs: _jobs,
          employees: _staff,
          editing: true,
          initial: _draft(),
          save: (_) async {},
        ),
        key,
        width: 360,
        scale: 1.5,
        keyboard: 280,
      );
      expect(find.text('Save Task').hitTestable(), findsOneWidget);
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      expect(t.getBottomRight(find.text('Save Task')).dy, lessThan(564));
      for (final field in [
        'task-start-date',
        'task-end-date',
        'task-priority',
        'task-status',
        'task-payroll-treatment',
      ]) {
        await t.scrollUntilVisible(
          find.byKey(ValueKey(field)),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        expect(find.byKey(ValueKey(field)).hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
      }
      await capture(t, key, 'service-editor-accessible-keyboard');
    },
  );
}
