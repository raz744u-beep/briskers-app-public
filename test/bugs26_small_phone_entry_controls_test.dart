import 'package:briskers_app/screens/customers/new_customer_screen.dart';
import 'package:briskers_app/screens/customers/new_vehicle_screen.dart';
import 'package:briskers_app/screens/customers/vin_scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Customer, Vehicle and manual VIN controls remain reachable above Samsung navigation and keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 740);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final keyboard in [0.0, 300.0]) {
        Widget app(Widget screen) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(bottom: 48),
              viewPadding: const EdgeInsets.only(bottom: 48),
              viewInsets: EdgeInsets.only(bottom: keyboard),
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: screen,
        );
        for (final row in <(Widget, String)>[
          (
            const NewCustomerScreen(businessId: 'synthetic-shop'),
            'Save customer & add vehicle',
          ),
          (
            const NewVehicleScreen(
              businessId: 'synthetic-shop',
              customerId: 'synthetic-customer',
            ),
            'Save vehicle',
          ),
        ]) {
          await tester.pumpWidget(app(row.$1));
          await tester.pumpAndSettle();
          final save = find.text(row.$2);
          await tester.ensureVisible(save);
          await tester.pumpAndSettle();
          expect(save.hitTestable(), findsOneWidget);
          expect(
            tester.getBottomRight(save).dy,
            lessThanOrEqualTo(740 - (keyboard > 0 ? keyboard : 48)),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        await tester.pumpWidget(app(const VinScannerScreen()));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Enter manually'));
        await tester.tap(find.text('Enter manually'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '1HGCM82633A004352');
        final use = find.text('Use this VIN');
        await tester.ensureVisible(use);
        await tester.pumpAndSettle();
        expect(use.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
