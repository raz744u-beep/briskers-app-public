import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/warranty_received_payment_dialog.dart';

void main() {
  testWidgets('gross receipt confirmation shows retained value without a second fee charge', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      WarrantyReceivedPaymentDialog(initialGross: 515, processorFee: 15, remaining: 515, check: false))));
    expect(find.textContaining('500.00'), findsOneWidget);
    expect(find.textContaining('Do not charge it again'), findsOneWidget);
    final field = find.byType(TextField);
    await tester.enterText(field, '516');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.enterText(field, '515');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });
  testWidgets('check uses zero fee on narrow keyboard-open display', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(viewInsets: const EdgeInsets.only(bottom: 270)), child: child!),
      home: const Scaffold(body: WarrantyReceivedPaymentDialog(
        initialGross: 515, processorFee: 15, remaining: 515, check: true))));
    expect(find.textContaining('515.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
