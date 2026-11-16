import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/screens/settings/catalog_settings_screen.dart';

void main() {
  testWidgets('new invoice catalog item allows selecting an existing category',
      (tester) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              saved = await showModalBottomSheet<Map<String, dynamic>>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => const CatalogItemDialog(
                  initialName: 'Oil Filter',
                  categories: [
                    {'name': 'Engine', 'active': true},
                    {'name': 'Historical', 'active': false},
                  ],
                ),
              );
            },
            child: const Text('New item'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('New item'));
    await tester.pumpAndSettle();

    final dropdown = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    expect(find.text('No category'), findsWidgets);
    expect(find.text('Engine'), findsWidgets);
    expect(find.text('Historical (inactive)'), findsWidgets);

    await tester.tap(find.text('Engine').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Item'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!['category'], 'Engine');
    expect(saved!['name'], 'Oil Filter');
  });
}
