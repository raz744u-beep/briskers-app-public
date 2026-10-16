import 'dart:async';

import 'package:briskers_app/widgets/work_performed_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    String initial = '',
    required Future<String?> Function() load,
    ValueChanged<String?>? saved,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () async {
                final result = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => WorkPerformedEditorSheet(
                    initialValue: initial,
                    loadInvoiceLabor: load,
                  ),
                );
                saved?.call(result);
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('filled labor remains editable and only saves on Save', (
    tester,
  ) async {
    String? saved;
    await open(
      tester,
      load: () async => 'Replace brakes',
      saved: (value) => saved = value,
    );
    await tester.tap(find.text('Fill from Invoice Labor'));
    await tester.pumpAndSettle();
    expect(find.text('Add invoice labor?'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Replace brakes',
    );
    expect(saved, isNull);
    await tester.enterText(
      find.byType(TextField),
      'Replace brakes and road test',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 'Replace brakes and road test');
  });
  testWidgets('manual text is kept unless overwrite is confirmed', (
    tester,
  ) async {
    await open(
      tester,
      initial: 'My manual work',
      load: () async => 'Invoice labor',
    );
    await tester.tap(find.text('Fill from Invoice Labor'));
    await tester.pumpAndSettle();
    expect(find.text('Add invoice labor?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'My manual work',
    );
    await tester.tap(find.text('Fill from Invoice Labor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace text'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Invoice labor',
    );
  });
  testWidgets(
    'loading cannot overwrite text typed while waiting without confirmation',
    (tester) async {
      final complete = Completer<String?>();
      await open(tester, load: () => complete.future);
      await tester.tap(find.text('Fill from Invoice Labor'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Typed while loading');
      complete.complete('Invoice labor');
      await tester.pumpAndSettle();
      expect(find.text('Add invoice labor?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Typed while loading',
      );
    },
  );
  testWidgets('cancelled chooser and failed load preserve manual text', (
    tester,
  ) async {
    var count = 0;
    await open(
      tester,
      initial: 'Keep this',
      load: () async {
        if (count++ == 0) return null;
        throw StateError('Offline');
      },
    );
    await tester.tap(find.text('Fill from Invoice Labor'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep this',
    );
    await tester.tap(find.text('Fill from Invoice Labor'));
    await tester.pumpAndSettle();
    expect(
      find.text('Invoice labor could not be loaded. Your text has been kept.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep this',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('dismissing during load never reopens or saves an editor', (
    tester,
  ) async {
    final complete = Completer<String?>();
    String? saved;
    await open(
      tester,
      initial: 'Manual text',
      load: () => complete.future,
      saved: (value) => saved = value,
    );
    await tester.tap(find.text('Fill from Invoice Labor'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    complete.complete('Late invoice text');
    await tester.pumpAndSettle();
    expect(find.byType(WorkPerformedEditorSheet), findsNothing);
    expect(find.text('Add invoice labor?'), findsNothing);
    expect(saved, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Append keeps manual text and does not duplicate labor', (
    tester,
  ) async {
    await open(
      tester,
      initial: 'Manual findings\nReplace brakes',
      load: () async => 'Replace brakes\nRoad test',
    );
    await tester.tap(find.text('Fill from Invoice Labor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Append'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Manual findings\nReplace brakes\nRoad test',
    );
    await tester.tap(find.text('Fill from Invoice Labor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Append'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Manual findings\nReplace brakes\nRoad test',
    );
  });
}
