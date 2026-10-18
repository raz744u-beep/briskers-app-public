import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/briskers_module_dock.dart';

void main() {
  Widget buildDock({required Widget body}) {
    return MaterialApp(
      home: MediaQuery(
        // Reproduces a Samsung Android IME inset left behind after keyboard
        // focus is gone. It must not strand the app without navigation.
        data: const MediaQueryData(
          size: Size(400, 850),
          viewInsets: EdgeInsets.only(bottom: 290),
        ),
        child: Scaffold(
          body: body,
          bottomNavigationBar: BriskersModuleDock(
            selectedIndex: 0,
            onSelected: (_) {},
            destinations: const [
              BriskersDockDestination(
                label: 'Home',
                icon: Icons.home_outlined,
                color: Colors.teal,
              ),
              BriskersDockDestination(
                label: 'Invoices',
                icon: Icons.receipt_outlined,
                color: Colors.green,
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('stale reported keyboard height cannot hide module navigation',
      (tester) async {
    await tester.pumpWidget(buildDock(body: const Center(child: Text('Ready'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dock-Home')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-Invoices')), findsOneWidget);
  });

  testWidgets('dock hides during real text editing and restores on unfocus',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(buildDock(body: TextField(focusNode: focus)));
    await tester.pumpAndSettle();
    debugPrint('IME-DOCK-INITIAL focus=${focus.hasFocus} primary=${FocusManager.instance.primaryFocus?.debugLabel} primaryWidget=${FocusManager.instance.primaryFocus?.context?.widget.runtimeType} dockExists=${find.byType(BriskersModuleDock).evaluate().length} keyedOffstage=${find.byKey(const ValueKey('dock-Home'), skipOffstage: false).evaluate().length} labels=${tester.widgetList<Text>(find.byType(Text, skipOffstage: false)).map((t) => t.data).toList()}');
    expect(find.byKey(const ValueKey('dock-Home')), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(find.byKey(const ValueKey('dock-Home')), findsNothing);
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dock-Home')), findsOneWidget);
  });
}
