import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/screens/documents_screen.dart';
import 'package:briskers_app/screens/shell_screen.dart';

// Header and route tests intentionally do not wait for document loading.
// The production loading indicator may animate while local storage is pending.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.offline,
    );
  });

  testWidgets(
    'Estimates returns to each existing primary tab without new shells',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DocumentsScreen(
                      businessId: 'navigation-test',
                      kind: 'estimate',
                      isOwner: true,
                      roleCode: 'owner',
                      onPrimaryDestinationSelected: (index) {
                        selected = index;
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ),
                child: const Text('Open Estimates'),
              ),
            ),
          ),
        ),
      );
      for (var index = 0; index < 6; index++) {
        await tester.tap(find.text('Open Estimates'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('OWNER'), findsOneWidget);
        final pill = find.ancestor(
          of: find.text('OWNER'),
          matching: find.byType(DecoratedBox),
        );
        expect(pill, findsOneWidget);
        expect(
          tester.widget<DecoratedBox>(pill).decoration,
          const BoxDecoration(
            color: Color(0xFFF6EAD5),
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
        );
        await tester.tap(find.byType(NavigationDestination).at(index));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(selected, index);
        expect(find.byType(DocumentsScreen), findsNothing);
        expect(find.byType(ShellScreen), findsNothing);
        expect(find.text('Open Estimates'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'non-owner Estimates keeps its actual role and has no owner pill',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DocumentsScreen(
            businessId: 'navigation-test',
            kind: 'estimate',
            isOwner: false,
            roleCode: 'technician',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('OWNER'), findsNothing);
      expect(
        tester.widget<DocumentsScreen>(find.byType(DocumentsScreen)).roleCode,
        'technician',
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
