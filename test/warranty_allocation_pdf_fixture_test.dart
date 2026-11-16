import 'dart:io';

import 'package:briskers_app/services/document_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render synthetic saved allocation and actual invoice balance separately', () async {
    final output = Directory('build/pdf-qa')..createSync(recursive: true);
    for (final stage in ['before', 'pending', 'finalized', 'paid-history']) {
      final historical = stage == 'paid-history';
      final received = stage != 'before';
      final pending = stage == 'pending';
      final total = historical ? 3972.97 : 1000;
      final gross = historical ? 684.97 : 103;
      final invoice = <String, dynamic>{
        'kind': 'invoice',
        'document_number': 'QA-W-${historical ? "paid" : stage}',
        'document_date': '2026-10-14',
        'customer_name': 'Synthetic Allocation Customer',
        'net_amount': total,
        'tax_amount': 0,
        'total_amount': total,
        'paid_amount': historical ? total : received && !pending ? gross : 0,
        'pending_payment': pending ? gross : 0,
        'lines': [
          {'name': 'Synthetic repair', 'line_kind': 'item', 'quantity': 1,
            'unit_price': total, 'net_amount': total, 'tax_rate': 0},
        ],
        'extended_warranty': true,
        'warranty_company_name': 'Synthetic Warranty Co',
        'approved_amount': gross,
        'terminal_amount': historical ? gross : 100,
        'net_applied': historical ? 665.02 : 100,
        'processor_fee': historical ? 19.95 : 3,
        'surcharge_rate': 0.03,
        'customer_responsibility': historical ? 3307.95 : 900,
        'payments': [
          if (received)
            {'id': 'synthetic-card', 'state': pending ? 'pending' : 'finalized',
              'payment_method_name': 'Credit card', 'amount': gross},
          if (historical)
            {'id': 'synthetic-cash', 'state': 'finalized',
              'payment_method_name': 'Cash', 'amount': 3288},
        ],
      };
      final balance = DocumentPdfService.invoicePaymentAmounts(invoice)['remaining'];
      expect(balance, historical ? 0 : received ? 897 : 1000);
      final bytes = await DocumentPdfService.build(invoice);
      expect(bytes.length, greaterThan(1000));
      await File('${output.path}/warranty-allocation-$stage.pdf').writeAsBytes(bytes);
    }
  });

  test('approved PDF row labels and final-total-only row emphasis are retained', () {
    final source = File('lib/services/document_pdf_service.dart').readAsStringSync();
    final box = source.substring(source.indexOf('static pw.Widget _warrantyAllocationBox('),
      source.indexOf('static pw.Widget _fullWidthSection('));
    for (final label in [
      'Approved warranty amount',
      'Warranty Card Payment Amount',
      r'Credit Card Processing Fee\n(Customer Responsibility)',
      'Customer Responsibility',
      'Total Customer Responsibility',
    ]) {
      expect(box, contains(label));
    }
    expect('bold: true'.allMatches(box), hasLength(1));
    expect(box, contains('Saved payment allocation.'));
    expect(box, contains('see invoice balance for amount due.'));
  });
}
