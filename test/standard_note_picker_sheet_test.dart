import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/jobs/standard_note_picker_sheet.dart';

const _templates = <Map<String, dynamic>>[
  {'id': 'general', 'name': 'General', 'body': 'General note', 'sort_order': 0},
  {'id': 'a', 'name': 'First', 'body': 'First note', 'sort_order': 10, 'color_hex': '#C62828'},
  {'id': 'b', 'name': 'Second', 'body': 'Second note', 'sort_order': 20},
];

void main() {
  testWidgets('General is a footer with no drag handle and colored cards', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StandardNotePickerSheet(
      templates: _templates, canManage: true,
      onEdit: (_) async => _templates,
      onReorder: (_) async => _templates,
    ))));
    final list = tester.widget<ReorderableListView>(find.byKey(const ValueKey('standard-note-list')));
    expect(list.itemCount, 2);
    expect(find.byKey(const ValueKey('reorder-standard-note-general')), findsNothing);
    expect(find.byKey(const ValueKey('reorder-standard-note-a')), findsOneWidget);
    expect(tester.getTopLeft(find.text('General')).dy,
        greaterThan(tester.getTopLeft(find.text('Second')).dy));
    expect(tester.widget<Card>(find.byKey(const ValueKey('standard-note-a'))).color,
        const Color(0xFFC62828).withValues(alpha: 0.09));
  });

  testWidgets('non-owners can choose notes but cannot create edit or reorder', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StandardNotePickerSheet(
      templates: _templates, canManage: false,
      onEdit: (_) async => throw StateError('Must not edit'),
      onReorder: (_) async => throw StateError('Must not reorder'),
    ))));
    expect(find.byKey(const ValueKey('add-standard-note-template')), findsNothing);
    expect(find.byType(ReorderableDragStartListener), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('reorder emits all IDs with General last', (tester) async {
    List<String>? requested;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StandardNotePickerSheet(
      templates: _templates, canManage: true,
      onEdit: (_) async => _templates,
      onReorder: (ids) async {
        requested = ids;
        return [
          for (var i = 0; i < ids.length; i++)
            {..._templates.firstWhere((note) => note['id'] == ids[i]), 'sort_order': i},
        ];
      },
    ))));
    final list = tester.widget<ReorderableListView>(find.byKey(const ValueKey('standard-note-list')));
    list.onReorder(0, 2);
    await tester.pumpAndSettle();
    expect(requested, ['b', 'a', 'general']);
    expect(tester.getTopLeft(find.text('Second')).dy,
        lessThan(tester.getTopLeft(find.text('First')).dy));
  });

  testWidgets('editing reloads the picker without inserting the note', (tester) async {
    String? edited;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StandardNotePickerSheet(
      templates: _templates, canManage: true,
      onEdit: (note) async {
        edited = note['id'].toString();
        return [for (final template in _templates)
          {...template, if (template['id'] == edited) 'body': 'Edited template body'}];
      },
      onReorder: (_) async => _templates,
    ))));
    await tester.tap(find.byKey(const ValueKey('edit-standard-note-a')));
    await tester.pumpAndSettle();
    expect(edited, 'a');
    expect(find.text('Edited template body'), findsOneWidget);
    expect(find.byType(StandardNotePickerSheet), findsOneWidget);
  });
}
