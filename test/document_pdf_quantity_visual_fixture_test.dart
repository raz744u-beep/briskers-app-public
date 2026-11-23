import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/core/repair_group.dart';
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
        'paid_amount': kind == 'invoice' ? 2525 : 0,
        'pending_payment': 0,
        'lines': lines,
        if (kind == 'invoice') ...{
          'extended_warranty': true,
          'warranty_company_name': 'Synthetic Warranty Co',
          'approved_amount': 515,
          'terminal_amount': 515,
          'net_applied': 500,
          'processor_fee': 15,
          'surcharge_rate': 0.03,
          'customer_responsibility': 2025,
          'payments': [
            {'id': 'qa-cash', 'state': 'posted', 'payment_method_name': 'Cash', 'amount': 2010},
            {'id': 'qa-card', 'state': 'posted', 'payment_method_name': 'Credit card', 'amount': 515},
          ],
        },
      });
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
      await File('${directory.path}/$kind-quantity-alignment.pdf')
          .writeAsBytes(bytes);
    }
  });

  test('render grouped estimate with mixed labor and parts', () async {
    final part = <String, dynamic>{
      'name': 'Valve cover gasket',
      'line_kind': 'item',
      'quantity': 1,
      'unit_price': 70,
      'net_amount': 70,
    };
    final labor = <String, dynamic>{
      'name': 'Gasket replacement',
      'line_kind': 'labor',
      'quantity': 2,
      'unit_price': 100,
      'net_amount': 200,
    };
    final ungrouped = <String, dynamic>{
      'name': 'Engine oil',
      'line_kind': 'item',
      'quantity': 1,
      'unit_price': 50,
      'net_amount': 50,
    };
    final supplies = <String, dynamic>{
      'name': 'Shop supplies',
      'line_kind': 'item',
      'quantity': 1,
      'unit_price': 10,
      'net_amount': 10,
    };
    final bytes = await DocumentPdfService.build({
      'kind': 'estimate',
      'document_number': 'QA-GROUP-001',
      'net_amount': 330,
      'total_amount': 330,
      'lines': [part, labor, ungrouped, supplies],
    }, repairGroups: [
      RepairGroup(
        id: 'gasket',
        name: 'Oil leaks',
        description: 'Replace the leaking gasket',
        lines: [part, labor],
      ),
      RepairGroup(
        id: RepairGroup.otherId,
        name: 'Other Items',
        lines: [ungrouped],
      ),
    ]);
    expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    final directory = Directory('build/pdf-qa')..createSync(recursive: true);
    await File('${directory.path}/grouped-estimate.pdf').writeAsBytes(bytes);
  });

}
