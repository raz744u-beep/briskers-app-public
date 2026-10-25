import 'package:briskers_app/tasks_lab/weekly_hours_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping existing weekly hours selects the whole number',
      (tester) async {
    String savedHours = '1.50';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WeeklyHoursTextField(
        initialHours: savedHours,
        enabled: true,
        onChanged: (value) => savedHours = value,
      )),
    ));

    final field = find.byType(TextFormField);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, '1.50');
    expect(savedHours, '1.50'); // Simply opening does not modify hours.

    await tester.tap(field);
    await tester.pump();
    expect(editable.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4));

    await tester.enterText(field, '0.75');
    await tester.pump();
    expect(savedHours, '0.75');
    expect(editable.controller.text, '0.75');
  });

  testWidgets('locked approved hours remain read-only', (tester) async {
    var changed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WeeklyHoursTextField(
        initialHours: '2.25',
        enabled: false,
        onChanged: (_) => changed = true,
      )),
    ));
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.enabled, isFalse);
    expect(tester.widget<EditableText>(find.byType(EditableText))
      .controller.text, '2.25');
    expect(changed, isFalse);
  });
}
