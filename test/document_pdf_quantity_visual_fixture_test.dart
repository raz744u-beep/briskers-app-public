import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/services/document_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render invoice and estimate quantity alignment fixtures', () async {
    final directory = Directory('build/pdf-qa')..createSync(recursive: true);
    final quantities = <num>[2, 14, 1.5, 234, 1];
    final lines = <Map<String, dynamic>>[
      for (var index = 0; index < quantities.length; index++)
        {
          'name': 'Synthetic quantity sample ${index + 1}',
          'line_kind': index == 2 ? 'labor' : 'item',
          'quantity': quantities[index],
          'pricing_unit': index == 2 ? 'hrs' : 'pcs',
          'unit_price': 10,
          'net_amount': quantities[index] * 10,
          'tax_rate': 0,
        },
    ];
    final expected = ['2 pcs', '14 pcs', '1.5 hrs', '234 pcs', '1 pc'];
    expect(lines.map(DocumentPdfService.pdfLineQuantity), expected);
    for (final kind in ['invoice', 'estimate']) {
      final bytes = await DocumentPdfService.build({
        'kind': kind,
        'document_number': 'QA-QTY-001',
        'document_date': '2026-10-14',
        'customer_name': 'Synthetic QA Customer',
        'net_amount': 2525,
        'tax_amount': 0,
        'total_amount': 2525,
        'paid_amount': 0,
        'pending_payment': 0,
        'lines': lines,
      });
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
      await File('${directory.path}/$kind-quantity-alignment.pdf')
          .writeAsBytes(bytes);
    }
  });
}
