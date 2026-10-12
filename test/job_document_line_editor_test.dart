import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/jobs/job_document_screen.dart';

void main() {
  const line = <String, dynamic>{
    'name': 'Labor',
    'quantity': 1,
    'unit_price': 0,
    'tax_rate': 0.095,
    'line_kind': 'labor',
  };

  Future<void> openEditor(
    WidgetTester tester, {
    bool replaceDefaults = true,
    ValueChanged<Map<String, dynamic>?>? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showModalBottomSheet<Map<String, dynamic>>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (_) => JobDocumentScreen.lineEditorForTesting(
                    line: line,
                    clearNumericOnFirstTap: replaceDefaults,
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  Finder field(int index) => find.byType(TextField).at(index);

  testWidgets(
    'each custom numeric value is selected every tap and saves replacement',
    (tester) async {
      Map<String, dynamic>? saved;
      await openEditor(tester, onResult: (value) => saved = value);
      for (final entry in <int, String>{2: '2', 3: '75', 4: '5'}.entries) {
        await tester.ensureVisible(field(entry.key));
        await tester.tap(field(entry.key));
        await tester.pumpAndSettle();
        final controller = tester
            .widget<TextField>(field(entry.key))
            .controller!;
        expect(
          controller.selection,
          TextSelection(baseOffset: 0, extentOffset: controller.text.length),
        );
        await tester.enterText(field(entry.key), entry.value);
        await tester.ensureVisible(field(0));
        await tester.tap(field(0));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.ensureVisible(field(entry.key));
        await tester.tap(field(entry.key));
        await tester.pumpAndSettle();
        expect(controller.text, entry.value);
        expect(controller.selection,
          TextSelection(baseOffset: 0, extentOffset: controller.text.length));
      }
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?['quantity'], 2);
      expect(saved?['unit_price'], 75);
      expect(saved?['tax_rate'], 0.05);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'close and cancel preserve the original and reopening resets selection',
    (tester) async {
      Map<String, dynamic>? saved;
      await openEditor(tester, onResult: (value) => saved = value);
      await tester.ensureVisible(field(3));
      await tester.tap(field(3));
      await tester.pumpAndSettle();
      await tester.enterText(field(3), '99');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field(3));
      await tester.tap(field(3));
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(field(3)).controller!;
      expect(controller.text, '0');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(line['unit_price'], 0);
    },
  );

  testWidgets(
    'compact screen keeps actions above keyboard and system safe area',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      Map<String, dynamic>? saved;
      await openEditor(tester, onResult: (value) => saved = value);
      expect(
        tester.getRect(find.byType(FilledButton)).bottom,
        lessThanOrEqualTo(616),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      tester.view.padding = const FakeViewPadding(top: 24);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byType(FilledButton)).bottom,
        lessThanOrEqualTo(360),
      );
      await tester.ensureVisible(field(4));
      await tester.tap(field(4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?['unit_price'], 0);
      expect(find.text('Open editor'), findsOneWidget);
    },
  );
}
