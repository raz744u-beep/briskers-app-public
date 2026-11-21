import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/screens/jobs/standard_note_picker_sheet.dart';

const _templates = <Map<String, dynamic>>[
  {'id': 'general', 'name': 'General', 'body': 'General note', 'sort_order': 0},
  {
    'id': 'a',
    'name': 'First',
    'body': 'First note',
    'sort_order': 10,
    'color_hex': '#C62828',
  },
  {'id': 'b', 'name': 'Second', 'body': 'Second note', 'sort_order': 20},
];

void main() {
  testWidgets('category reordering moves groups but keeps General last', (
    tester,
  ) async {
    final templates = <Map<String, dynamic>>[
      {
        'id': 'g',
        'name': 'General',
        'body': 'Thank you',
        'sort_order': 0,
        'category_key': 'general',
      },
      {
        'id': 's',
        'name': 'Service A',
        'body': 'Service work',
        'sort_order': 10,
        'category_key': 'service',
      },
      {
        'id': 'w',
        'name': 'Standard Warranty',
        'body': 'Warranty coverage',
        'sort_order': 20,
        'category_key': 'warranty',
      },
    ];
    List<String>? requested;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StandardNotePickerSheet(
            templates: templates,
            canManage: true,
            onEdit: (_) async => templates,
            onReorder: (ids, categories) async {
              requested = ids;
              return [
                for (var i = 0; i < ids.length; i++)
                  {
                    ...templates.firstWhere((note) => note['id'] == ids[i]),
                    'sort_order': (i + 1) * 10,
                  },
              ];
            },
          ),
        ),
      ),
    );
    final groups = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('standard-note-categories')),
    );
    groups.onReorderItem!(0, 1);
    await tester.pumpAndSettle();
    expect(requested, ['w', 's', 'g']);
    expect(
      find.byKey(const ValueKey('standard-note-group-general')),
      findsOneWidget,
    );
  });

  testWidgets('General is a footer with no drag handle and colored cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StandardNotePickerSheet(
            templates: _templates,
            canManage: true,
            onEdit: (_) async => _templates,
            onReorder: (_, categories) async => _templates,
          ),
        ),
      ),
    );
    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('standard-note-list')),
    );
    expect(list.itemCount, 2);
    expect(
      find.byKey(const ValueKey('reorder-standard-note-general')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('reorder-standard-note-a')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('General')).dy,
      greaterThan(tester.getTopLeft(find.text('Second')).dy),
    );
    expect(
      tester.widget<Card>(find.byKey(const ValueKey('standard-note-a'))).color,
      const Color(0xFFC62828).withValues(alpha: 0.09),
    );
  });

  testWidgets(
    'colored category headers paint their ink on their own Material',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardNotePickerSheet(
              templates: _templates,
              canManage: true,
              onEdit: (_) async => _templates,
              onReorder: (_, categories) async => _templates,
            ),
          ),
        ),
      );
      const colors = {
        'service': Color(0xFF1565C0),
        'warranty': Color(0xFF2E7D32),
        'inspection': Color(0xFFEF6C00),
        'advisory': Color(0xFFC62828),
        'general': Color(0xFF6A1B9A),
      };
      for (final entry in colors.entries) {
        final surface = tester.widget<Material>(
          find.byKey(ValueKey('standard-note-group-surface-${entry.key}')),
        );
        final header = tester.element(
          find.byKey(ValueKey('toggle-standard-note-group-${entry.key}')),
        );
        expect(header.findAncestorWidgetOfExactType<Material>(), same(surface));
        expect(surface.color, entry.value.withValues(alpha: 0.045));
        expect(surface.borderRadius, BorderRadius.circular(12));
        expect(surface.clipBehavior, Clip.antiAlias);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('non-owners can choose notes but cannot create edit or reorder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StandardNotePickerSheet(
            templates: _templates,
            canManage: false,
            onEdit: (_) async => throw StateError('Must not edit'),
            onReorder: (_, categories) async =>
                throw StateError('Must not reorder'),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('add-standard-note-template')),
      findsNothing,
    );
    expect(find.byType(ReorderableDragStartListener), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('moves down and up use adjusted indexes with General last', (
    tester,
  ) async {
    List<String>? requested;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StandardNotePickerSheet(
            templates: _templates,
            canManage: true,
            onEdit: (_) async => _templates,
            onReorder: (ids, categories) async {
              requested = ids;
              return [
                for (var i = 0; i < ids.length; i++)
                  {
                    ..._templates.firstWhere((note) => note['id'] == ids[i]),
                    'sort_order': i,
                  },
              ];
            },
          ),
        ),
      ),
    );
    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('standard-note-list')),
    );
    expect(list.onReorderItem, isNotNull);
    list.onReorderItem!(0, 1);
    await tester.pumpAndSettle();
    expect(requested, ['b', 'a', 'general']);
    expect(
      tester.getTopLeft(find.text('Second')).dy,
      lessThan(tester.getTopLeft(find.text('First')).dy),
    );
    expect(
      tester.getTopLeft(find.text('General')).dy,
      greaterThan(tester.getTopLeft(find.text('First')).dy),
    );

    final reorderedList = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('standard-note-list')),
    );
    reorderedList.onReorderItem!(1, 0);
    await tester.pumpAndSettle();
    expect(requested, ['a', 'b', 'general']);
    expect(
      tester.getTopLeft(find.text('First')).dy,
      lessThan(tester.getTopLeft(find.text('Second')).dy),
    );
    expect(
      tester.getTopLeft(find.text('General')).dy,
      greaterThan(tester.getTopLeft(find.text('Second')).dy),
    );
  });

  testWidgets('editing reloads the picker without inserting the note', (
    tester,
  ) async {
    String? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StandardNotePickerSheet(
            templates: _templates,
            canManage: true,
            onEdit: (note) async {
              edited = note['id'].toString();
              return [
                for (final template in _templates)
                  {
                    ...template,
                    if (template['id'] == edited)
                      'body': 'Edited template body',
                  },
              ];
            },
            onReorder: (_, categories) async => _templates,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('edit-standard-note-a')));
    await tester.pumpAndSettle();
    expect(edited, 'a');
    expect(find.text('Edited template body'), findsOneWidget);
    expect(find.byType(StandardNotePickerSheet), findsOneWidget);
  });
  testWidgets('categories collapse and search reveals matching hidden notes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StandardNotePickerSheet(
            templates: _templates,
            canManage: false,
            onEdit: (_) async => throw StateError('Must not edit'),
            onReorder: (_, categories) async =>
                throw StateError('Must not reorder'),
          ),
        ),
      ),
    );
    final toggle = find.byKey(
      const ValueKey('toggle-standard-note-group-service'),
    );
    final firstNote = find.byKey(const ValueKey('standard-note-a'));
    final secondNote = find.byKey(const ValueKey('standard-note-b'));
    expect(firstNote, findsOneWidget);
    expect(secondNote, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(firstNote, findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('standard-note-search')),
      'First',
    );
    await tester.pumpAndSettle();
    expect(firstNote, findsOneWidget);
    expect(secondNote, findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('standard-note-search')),
      '',
    );
    await tester.pumpAndSettle();
    expect(firstNote, findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(firstNote, findsOneWidget);
  });

  testWidgets('Secretary selects exact template text from the Spanish picker', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('es');
    addTearDown(() => BriskersLanguageController.instance.setLanguage('en'));
    const body = 'Service A original text.\n\nWarranty terms stay unchanged.';
    Map<String, dynamic>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () async {
                selected = await showModalBottomSheet<Map<String, dynamic>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => StandardNotePickerSheet(
                    templates: const [
                      {'id': 'a', 'name': 'Service A', 'body': body},
                    ],
                    canManage: false,
                    onEdit: (_) async =>
                        throw StateError('Secretary cannot edit templates'),
                    onReorder: (_, categories) async =>
                        throw StateError('Secretary cannot reorder templates'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Notas estándar'), findsOneWidget);
    expect(find.text('Notas de servicio'), findsOneWidget);
    expect(find.text('Buscar notas'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    await tester.tap(find.text('Service A'));
    await tester.pumpAndSettle();
    expect(selected?['body'], body);
    expect(find.byType(StandardNotePickerSheet), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('cancel and reopen never selects or changes an invoice', (
    tester,
  ) async {
    Map<String, dynamic>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () async {
                selected = await showModalBottomSheet<Map<String, dynamic>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => StandardNotePickerSheet(
                    templates: _templates,
                    canManage: false,
                    onEdit: (_) async => _templates,
                    onReorder: (_, categories) async => _templates,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.byType(StandardNotePickerSheet), findsNothing);
    }
  });
}
