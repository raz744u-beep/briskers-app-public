import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/screens/jobs/invoice_warranty_panel.dart';

void main() {
  testWidgets('one Warranty Job check expands once, saves once, and does not launch a second editor', (tester) async {
    var saves = 0;
    Map<String, dynamic> last = const {};
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InvoiceWarrantyPanel(
          businessId: 'fixture-shop',
          documentId: 'fixture-invoice',
          expectedVersion: 1,
          invoiceTotal: 100,
          detail: const {'extended_warranty': false},
          paymentProcessed: false,
          onChanged: () async {},
          onLocalWarrantyChanged: (values) async {
            saves++;
            last = values;
          },
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('warranty-job-expand')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('warranty-job-checkbox')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(last['extended_warranty'], true);
    expect(tester.widget<Checkbox>(find.byKey(
        const ValueKey('warranty-job-checkbox'))).value, true);
    expect(find.byKey(const ValueKey('warranty-job-expand')), findsOneWidget);
    expect(find.text('Enter warranty details'), findsOneWidget);
    // A one-tap toggle cannot automatically open a second bottom sheet.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('warranty-job-expand')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
    expect(saves, 1);
    await tester.tap(find.byKey(const ValueKey('warranty-job-expand')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    expect(saves, 1);
  });

  test('Invoice mileage lives under vehicle and uses existing typed mileage workflows', () {
    final src = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final header = src.substring(src.indexOf('Widget _customerHeader()'));
    expect(src, contains("final mileage = _visibleInvoiceMileage;"));
    expect(src, contains("final mileageName = _usesInvoiceMileageOut ? 'Mileage Out' : 'Mileage';"));
    expect(src, contains("key: const ValueKey('invoice-header-mileage')"));
    expect(src, contains("if (!_estimate) mileageLine()"));
    expect(src, contains('Future<void> _editInvoiceMileage() async'));
    expect(src, contains('await _invoiceMileage.queue('));
    expect(src, contains('await _offlineDocumentDraft.updatePendingInvoiceDetails('));
    expect(src, contains('await _api.updateDocumentMileage('));
    expect(src, contains("if (BriskersConnectionModeController.instance.forceOffline) {"));
    expect(src, contains('MileageWorkflow.parse(changed)'));
    expect(header, contains('Widget mileageLine()'));
  });
}
