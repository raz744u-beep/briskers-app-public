import 'package:briskers_app/screens/expenses/receipt_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('review shows on-device OCR without any network action',
      (tester) async {
    const raw = 'WORLDPAC\nINVOICE\n74966713\nTOTAL\n191.35';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReceiptReviewSheet(
          extraction: <String, dynamic>{
            'vendor_name': 'Worldpac',
            'review_flags': <String>['Part lines need review'],
            'items': <Map<String, dynamic>>[],
            'raw_data': <String, dynamic>{
              'ocr_text': raw,
              'ocr_line_count': 5,
            },
          },
        ),
      ),
    ));
    expect(find.text('View text recognized on phone'), findsOneWidget);
    expect(find.text('5 recognized lines', findRichText: true), findsNothing);
    await tester.ensureVisible(find.byKey(
      const ValueKey('local-receipt-ocr-details')));
    await tester.tap(find.byKey(const ValueKey('local-receipt-ocr-details')));
    await tester.pumpAndSettle();
    expect(find.text(raw), findsOneWidget);
    expect(find.byKey(const ValueKey('copy-local-receipt-ocr')),
        findsOneWidget);
  });
}
