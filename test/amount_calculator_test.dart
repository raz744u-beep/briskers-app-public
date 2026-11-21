import 'package:briskers_app/core/amount_calculator.dart';
import 'package:briskers_app/widgets/amount_calculator_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arithmetic, contextual percent and cent rounding', () {
    for (final item in {'12.34+5.66':1800, '20-4.50':1550, '2.5×4':1000,
      '10÷4':250, '100+9.75%':10975, '100-10%':9000, '200*10%':2000,
      '1.005':101, '.1+.2':30, '2+3*4':1400}.entries) {
      expect(AmountCalculator.cents(item.key), item.value, reason: item.key);
    }
    expect(AmountCalculator.cents('+300', balanceCents:160000),190000);
    expect(AmountCalculator.cents('-140', balanceCents:160000),146000);
    for (final invalid in ['', '10/0', '1..2', '5+', '100-101', '1e100', 'abc']) {
      expect(() => AmountCalculator.cents(invalid), throwsFormatException, reason: invalid);
    }
  });
  testWidgets('small phone calculator returns amount only after Use Amount', (tester) async {
    tester.view.physicalSize = const Size(320,640); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    int? chosen;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () async { chosen = await showAmountCalculator(context); }, child: const Text('Calculate'))))));
    await tester.tap(find.text('Calculate')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'100+9.75%');
    expect(chosen,isNull);
    await tester.tap(find.text('Use Amount')); await tester.pumpAndSettle();
    expect(chosen,10975); expect(tester.takeException(),isNull);
  });
  testWidgets('compact keypad and relative expression work with keyboard insets', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    int? chosen;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          chosen = await showAmountCalculator(context, balanceCents: 160000);
        },
        child: const Text('Calculate'),
      ))),
    ));
    await tester.tap(find.text('Calculate'));
    await tester.pumpAndSettle();
    for (final label in ['−', '1', '4', '1', '⌫', '0', '=']) {
      await tester.tap(find.widgetWithText(FilledButton, label));
      await tester.pump();
    }
    final input = find.byType(TextField);
    expect(tester.widget<TextField>(input).controller!.text, '1460.00');
    expect(chosen, isNull);
    await tester.enterText(input, '+300');
    tester.view.viewInsets = const FakeViewPadding(bottom: 270);
    await tester.pumpAndSettle();
    final useAmount = find.text('Use Amount');
    await tester.ensureVisible(useAmount);
    await tester.pumpAndSettle();
    expect(useAmount.hitTestable(), findsOneWidget);
    await tester.tap(useAmount);
    await tester.pumpAndSettle();
    expect(chosen, 190000);
    expect(tester.takeException(), isNull);
  });

}
