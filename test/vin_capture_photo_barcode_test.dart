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
