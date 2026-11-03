import 'package:briskers_app/screens/expenses/receipt_scan_test_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  testWidgets('camera and gallery buttons navigate from inside MaterialApp',
      (tester) async {
    final opened = <ImageSource>[];
    await tester.pumpWidget(
      ReceiptScanTestHarness(
        testOnlySkipDatabase: true,
        testEditorBuilder: (source) {
          opened.add(source);
          return Scaffold(
            appBar: AppBar(title: const Text('TEST receipt editor')),
            body: Center(child: Text('Source: ${source.name}')),
          );
        },
      ),
    );

    await tester.tap(find.text('AI Scan Receipt'));
    await tester.pump();
    expect(find.text('Take receipt photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);

    await tester.tap(find.text('Take receipt photo'));
    await tester.pumpAndSettle();
    expect(opened, contains(ImageSource.camera));
    expect(find.text('Source: camera'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    // Navigator may rebuild an earlier route during transitions. Assert the
    // actual destination selected, not the number of widget builds.
    expect(opened.last, ImageSource.gallery);
    expect(opened, containsAll(<ImageSource>[
      ImageSource.camera, ImageSource.gallery,
    ]));
    expect(find.text('Source: gallery'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('Navigator operation requested'), findsNothing);
    expect(find.textContaining('Could not open receipt editor'), findsNothing);
    expect(find.textContaining('Scanner status:'), findsOneWidget);
  });
}
