import 'dart:io';

import 'package:briskers_app/widgets/customer_identity_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'flag sits below the customer icon and left of the name at narrow widths',
    (tester) async {
      for (final width in [180.0, 320.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: width,
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomerIdentityMarker(
                      icon: Icon(
                        Icons.person_outline,
                        key: Key('customer-icon'),
                      ),
                      flagged: true,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Charmaine Rini', key: Key('customer-name')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final icon = tester.getRect(find.byKey(const Key('customer-icon')));
        final flag = tester.getRect(
          find.byKey(const ValueKey('customer-identity-flag')),
        );
        final name = tester.getRect(find.byKey(const Key('customer-name')));
        expect(flag.top, greaterThan(icon.bottom));
        expect(flag.center.dx, icon.center.dx);
        expect(flag.right, lessThan(name.left));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(
        const MaterialApp(
          home: CustomerIdentityMarker(
            icon: Icon(Icons.person_outline),
            flagged: false,
          ),
        ),
      );
      expect(find.byIcon(Icons.flag), findsNothing);
    },
  );

  test('document and job customer headers share the icon-column marker', () {
    for (final path in [
      'lib/screens/jobs/job_document_screen.dart',
      'lib/screens/jobs/job_detail_screen.dart',
    ]) {
      final text = File(path).readAsStringSync();
      expect(text, contains('CustomerIdentityMarker('));
    }
  });
}
