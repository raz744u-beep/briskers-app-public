import 'package:briskers_app/screens/expenses/receipt_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const extraction = <String, dynamic>{
    'vendor_name': 'Worldpac',
    'vendor_invoice_number': '00123',
    'receipt_date': '2026-10-27',
    'receipt_total': 191.35,
    'items': <Map<String, dynamic>>[],
  };

  Future<void> open(
    WidgetTester tester,
    ValueChanged<Map<String, dynamic>?> result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result(
                    await showModalBottomSheet<Map<String, dynamic>>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) =>
                          const ReceiptReviewSheet(extraction: extraction),
                    ),
                  );
                },
                child: const Text('Review'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'review returns editable fields and preserves zero-prefixed invoice',
    (tester) async {
      Map<String, dynamic>? reviewed;
      await open(tester, (value) => reviewed = value);
      expect(reviewed, isNull);
      expect(find.text('Review receipt'), findsOneWidget);
      await tester.tap(find.text('Use reviewed fields'));
      await tester.pumpAndSettle();
      expect(reviewed?['review_confirmed'], true);
      expect(reviewed?['vendor_invoice_number'], '00123');
      expect(reviewed?['receipt_total'], 191.35);
    },
  );

  testWidgets('cancel retains draft without applying suggestions', (
    tester,
  ) async {
    Map<String, dynamic>? reviewed;
    await open(tester, (value) => reviewed = value);
    await tester.tap(find.byTooltip('Keep photo only'));
    await tester.pumpAndSettle();
    expect(reviewed, isNull);
  });

  testWidgets('nonfinite totals are rejected before applying fields', (
    tester,
  ) async {
    Map<String, dynamic>? reviewed;
    await open(tester, (value) => reviewed = value);
    final total = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Receipt total',
    );
    await tester.ensureVisible(total);
    await tester.enterText(total, 'NaN');
    await tester.tap(find.text('Use reviewed fields'));
    await tester.pumpAndSettle();
    expect(reviewed, isNull);
    expect(find.text('Use reviewed fields'), findsOneWidget);
  });
}
