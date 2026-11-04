import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/screens/expenses/expense_receipt_attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('receipt preview works before intl date locale initialization', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('es');
    final root = await Directory.systemTemp.createTemp('receipt-locale-');
    final image = File('${root.path}/receipt.png');
    await image.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
      ),
    );
    try {
      // Deliberately omit GlobalMaterialLocalizations and initializeDateFormatting.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExpenseReceiptAttachments(
              receipts: [XFile(image.path)],
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      await BriskersLanguageController.instance.setLanguage('en');
      await root.delete(recursive: true);
    }
  });
}
