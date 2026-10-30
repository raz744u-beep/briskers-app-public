import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/vin_capture_parser.dart';
import 'package:briskers_app/screens/customers/vin_scanner_screen.dart';

void main() {
  const vin = '1HGCM82633A004352';

  test('full 17-character VIN is accepted, short/long random codes rejected', () {
    expect(VinCaptureParser.isValid(vin), true);
    expect(VinCaptureParser.isValid('1HGCM82633A00435'), false);
    expect(VinCaptureParser.isValid('${vin}9'), false);
    expect(VinCaptureParser.isValid('1HGCM82633A00435O'), false);
    expect(VinCaptureParser.isValid('1HGCM82633A00435I'), false);
    expect(VinCaptureParser.isValid('1HGCM82633A00435Q'), false);
  });

  test('US VIN check digit detects photographed character substitution', () {
    const validAudi = 'WAU34AFD0GN013309';
    const misreadAudi = '6BU34AFD0GN013309';
    expect(VinCaptureParser.isValid(validAudi), true);
    expect(VinCaptureParser.isValid(misreadAudi), true);
    expect(VinCaptureParser.hasValidCheckDigit(validAudi), true);
    expect(VinCaptureParser.hasValidCheckDigit(misreadAudi), false);
    expect(VinCaptureParser.hasValidCheckDigit('1234'), false);
    expect(VinCaptureParser.preferVerified([misreadAudi, validAudi]),
        [validAudi, misreadAudi]);
  });

  testWidgets('manual review field is limited to 17 characters', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VinScannerScreen()));
    await tester.tap(find.text('Enter manually'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLength, 17);
    await tester.enterText(find.byType(TextField), '1HGCM82633A0043521234');
    expect(find.text('1HGCM82633A004352'), findsOneWidget);
  });

  testWidgets('check-digit mismatch requires explicit second confirmation',
      (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.push<String>(
                context,
                MaterialPageRoute(builder: (_) => const VinScannerScreen()),
              );
            },
            child: const Text('Open VIN'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open VIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter manually'));
    await tester.pumpAndSettle();
    const invalidCheckDigit = '6BU34AFD0GN013309';
    await tester.enterText(find.byType(TextField), invalidCheckDigit);
    await tester.tap(find.text('Use this VIN'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('does not match'), findsOneWidget);
    expect(find.text('Use unverified VIN'), findsOneWidget);
    await tester.tap(find.text('Use unverified VIN'));
    await tester.pumpAndSettle();
    expect(result, invalidCheckDigit);
  });

  test('barcode strips harmless Code39 wrapping without truncating long codes', () {
    expect(VinCaptureParser.fromBarcodeValues([
      'PART-AB-000004940493',
      'VIN: $vin',
      '*$vin*',
      '${vin}98765',
      '123456',
    ]), [vin]);
    expect(
      VinCaptureParser.fromBarcodeValues(['1234567890123456789']),
      isEmpty,
    );
  });

  test('printed VIN OCR accepts labeled or spaced lines only when complete', () {
    expect(VinCaptureParser.fromTextLines([
      'Manufacturer: Honda',
      'VIN: $vin',
      'Other number: 12345',
    ]), [vin]);
    expect(VinCaptureParser.fromTextLines([
      'VIN: 1HG CM8 2633 A004352',
      'Tire 225 / 45 R 17',
    ]), [vin]);
    expect(VinCaptureParser.fromTextLines(['VIN: 1HGCM82633A00435']), isEmpty);
  });

  testWidgets('capture menu offers simple printed VIN, barcode, and manual options', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VinScannerScreen()));
    expect(find.text('VIN Capture'), findsOneWidget);
    expect(find.text('Take a VIN photo'), findsOneWidget);
    expect(find.text('Scan a VIN barcode'), findsOneWidget);
    expect(find.text('Choose an existing photo'), findsOneWidget);
    expect(find.text('Enter manually'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not send'), findsOneWidget);
  });

  testWidgets('manual VIN returns only a fully confirmed result', (tester) async {
    String? captured;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            captured = await Navigator.push<String>(
              context,
              MaterialPageRoute(builder: (_) => const VinScannerScreen()),
            );
          },
          child: const Text('Open VIN'),
        ),
      )),
    ));
    await tester.tap(find.text('Open VIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter manually'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    await tester.enterText(field, '1HGCM82633A00435');
    await tester.tap(find.text('Use this VIN'));
    await tester.pumpAndSettle();
    expect(find.textContaining('exactly 17'), findsOneWidget);
    expect(captured, isNull);
    await tester.enterText(field, vin);
    await tester.tap(find.text('Use this VIN'));
    await tester.pumpAndSettle();
    expect(captured, vin);
  });

  test('release R8 suppresses only unavailable optional OCR languages', () {
    // CI executes tests inside a generated Flutter project whose workflow
    // files remain in the parent checkout. Local root tests use the first path.
    final workflowFile = File('.github/workflows/android-debug.yml');
    final workflow = (workflowFile.existsSync()
            ? workflowFile
            : File('../.github/workflows/android-debug.yml'))
        .readAsStringSync();
    for (final language in ['chinese', 'devanagari', 'japanese', 'korean']) {
      expect(workflow,
          contains('-dontwarn com.google.mlkit.vision.text.$language.**'));
    }
    expect(workflow,
        isNot(contains('-dontwarn com.google.mlkit.vision.text.latin.**')));
    expect(workflow, contains('proguardFiles(getDefaultProguardFile('));
    final scanner = File('lib/screens/customers/vin_scanner_screen.dart')
        .readAsStringSync();
    expect(scanner, contains('TextRecognitionScript.latin'));
  });

  test('camera never cuts or auto-applies unverified barcode values', () {
    final screen=File('lib/screens/customers/vin_scanner_screen.dart')
        .readAsStringSync();
    expect(screen, contains('VinCaptureParser.fromBarcodeValues('));
    expect(screen, contains('VinCaptureParser.fromTextLines(lines)'));
    expect(screen, contains('TextRecognizer(script: TextRecognitionScript.latin)'));
    expect(screen, contains('Navigator.of(context).pop(candidate)'));
    expect(screen, isNot(contains('cleaned.substring(0, 17)')));
    expect(screen, contains('Only camera images created by this capture flow'));
  });
}
