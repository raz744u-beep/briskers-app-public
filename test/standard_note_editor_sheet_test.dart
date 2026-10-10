import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/briskers_colors.dart';
import 'package:briskers_app/screens/jobs/standard_note_editor_sheet.dart';

void main() {
  testWidgets('template editor disables save until name and text are entered',
      (tester) async {
    Map<String, String>? output;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => FilledButton(
          onPressed: () async {
            output = await showModalBottomSheet<Map<String, String>>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const StandardNoteEditorSheet(
                accent: BriskersColors.invoices,
                addToInvoice: true,
              ),
            );
          },
          child: const Text('Open standard note'),
        )),
      ),
    ));
    await tester.tap(find.text('Open standard note'));
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('standard-note-submit'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('standard-note-name')), 'Standard Warranty',
    );
    await tester.enterText(
      find.byKey(const ValueKey('standard-note-body')),
      'Warranty 12 months / 12000 miles',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(output, <String, String>{
      'name': 'Standard Warranty',
      'body': 'Warranty 12 months / 12000 miles',
    });
  });

  testWidgets('Save as Standard Note starts with existing typed text',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StandardNoteEditorSheet(
          accent: BriskersColors.invoices,
          initialBody: 'Already entered invoice memo',
        ),
      ),
    ));
    expect(find.text('Already entered invoice memo'), findsOneWidget);
    expect(tester.widget<FilledButton>(
      find.byKey(const ValueKey('standard-note-submit')),
    ).onPressed, isNull);
  });
}
