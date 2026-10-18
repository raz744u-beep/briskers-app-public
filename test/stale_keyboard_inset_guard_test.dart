import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/stale_keyboard_inset_guard.dart';

void main() {
  Widget scene(FocusNode focusNode) => MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(400, 850),
        viewInsets: EdgeInsets.only(bottom: 290),
      ),
      child: StaleKeyboardInsetGuard(
        // Scaffold normally consumes the bottom keyboard inset before it
        // reaches Scaffold.body. Inspect the MediaQuery at Scaffold's input,
        // and measure the body viewport to prove that layout also recovers.
        child: Builder(builder: (viewportContext) => Scaffold(
          body: SizedBox(
            key: const ValueKey('guard-scaffold-body'),
            width: double.infinity,
            child: Column(children: [
              TextField(focusNode: focusNode),
              Text('bottom inset: ${MediaQuery.viewInsetsOf(viewportContext).bottom.toInt()}'),
            ]),
          ),
        )),
      ),
    ),
  );

  testWidgets('false IME inset is suppressed after keyboard focus leaves',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(scene(focus));
    await tester.pumpAndSettle();
    expect(find.text('bottom inset: 0'), findsOneWidget);
    final fullHeight =
        tester.getSize(find.byKey(const ValueKey('guard-scaffold-body'))).height;

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(StaleKeyboardInsetGuard.editableTextHasFocus, isTrue);
    expect(find.text('bottom inset: 290'), findsOneWidget);
    final editingHeight =
        tester.getSize(find.byKey(const ValueKey('guard-scaffold-body'))).height;
    expect(editingHeight, lessThan(fullHeight));

    focus.unfocus();
    await tester.pumpAndSettle();
    expect(StaleKeyboardInsetGuard.editableTextHasFocus, isFalse);
    expect(find.text('bottom inset: 0'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('guard-scaffold-body'))).height,
      fullHeight,
    );
  });
}
