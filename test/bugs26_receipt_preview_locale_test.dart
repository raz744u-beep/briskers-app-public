import 'dart:convert';
import 'dart:typed_data';

import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/screens/expenses/expense_receipt_attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReceiptFile extends XFile {
  _ReceiptFile() : super('synthetic-receipt.png');

  @override
  Future<Uint8List> readAsBytes() async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
  );

  @override
  Future<DateTime> lastModified() async => DateTime(2026, 11, 3);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('es');
  });
  tearDown(() async {
    await BriskersLanguageController.instance.setLanguage('en');
  });

  testWidgets('receipt preview works before intl date locale initialization', (
    tester,
  ) async {
    // Deliberately omit GlobalMaterialLocalizations and initializeDateFormatting.
    // The fake file supplies both bytes and a modification date without OS I/O.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpenseReceiptAttachments(
            receipts: [_ReceiptFile()],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
