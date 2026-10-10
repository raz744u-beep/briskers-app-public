import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/document_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only PDF labor quantities include hrs, preserving decimals', () {
    expect(
      DocumentPdfService.pdfLineQuantity({
        'line_kind': 'labor',
        'quantity': 4.40,
      }),
      '4.4 hrs',
    );
    expect(
      DocumentPdfService.pdfLineQuantity({
        'line_kind': 'labor',
        'quantity': 0.75,
      }),
      '0.75 hrs',
    );
    expect(
      DocumentPdfService.pdfLineQuantity({
        'line_kind': 'item',
        'quantity': 4.4,
        'pricing_unit': 'pc',
      }),
      '4.4 pc.',
    );
    expect(
      DocumentPdfService.pdfLineQuantity({
        'line_kind': 'item',
        'quantity': 2,
      }),
      '2 pc.',
    );
    expect(
      DocumentPdfService.pdfLineQuantity({
        'line_kind': 'item',
        'quantity': 2,
        'pricing_unit': 'set',
      }),
      '2 set',
    );
    expect(
      DocumentPdfService.pdfLineQuantity({
        'line_kind': 'supply',
        'quantity': 2,
      }),
      '2',
    );
  });

  test('invoice PDF with labor and parts renders', () async {
    final bytes = await DocumentPdfService.build({
      'kind': 'invoice',
      'document_number': 'test-labor-unit',
      'customer_name': 'Test Customer',
      'net_amount': 250,
      'tax_amount': 0,
      'total_amount': 250,
      'lines': [
        {
          'name': 'Diagnosis',
          'line_kind': 'labor',
          'quantity': 4.4,
          'unit_price': 50,
          'net_amount': 220,
          'tax_rate': 0,
        },
        {
          'name': 'Part',
          'line_kind': 'item',
          'quantity': 1,
          'unit_price': 30,
          'net_amount': 30,
          'tax_rate': 0,
        },
      ],
    });
    expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
  });
}
