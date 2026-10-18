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
        child: Scaffold(
          body: Column(children: [
            TextField(focusNode: focusNode),
            Builder(builder: (context) =>
              Text('bottom inset: ${MediaQuery.viewInsetsOf(context).bottom.toInt()}')),
          ]),
        ),
      ),
    ),
  );

  testWidgets('false IME inset is suppressed after keyboard focus leaves', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(scene(focus));
    await tester.pumpAndSettle();
    expect(find.text('bottom inset: 0'), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(find.text('bottom inset: 290'), findsOneWidget);
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('bottom inset: 0'), findsOneWidget);
  });
}
