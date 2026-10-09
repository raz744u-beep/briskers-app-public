import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/document_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Invoice PDF payment balance', () {
    test('unpaid invoice owes the full amount', () {
      final amounts = DocumentPdfService.invoicePaymentAmounts({
        'total_amount': 972,
        'paid_amount': 0,
        'pending_payment': 0,
      });
      expect(amounts['total'], 972);
      expect(amounts['paid'], 0);
      expect(amounts['pending'], 0);
      expect(amounts['remaining'], 972);
    });

    test('partial finalized payment is applied once', () {
      final amounts = DocumentPdfService.invoicePaymentAmounts({
        'total_amount': 972,
        'paid_amount': 400,
        'pending_payment': 0,
      });
      expect(amounts['paid'], 400);
      expect(amounts['remaining'], 572);
    });

    test('entered pending payment is separate from confirmed paid', () {
      final amounts = DocumentPdfService.invoicePaymentAmounts({
        'total_amount': '972.00',
        'paid_amount': '250.00',
        'pending_payment': '150.00',
      });
      expect(amounts['paid'], 250);
      expect(amounts['pending'], 150);
      expect(amounts['remaining'], 572);
    });

    test('fully paid invoice has no remaining balance', () {
      final amounts = DocumentPdfService.invoicePaymentAmounts({
        'total_amount': 972,
        'paid_amount': 972,
        'pending_payment': 0,
      });
      expect(amounts['remaining'], 0);
    });

    test('overpaid and zero invoices never show a negative balance', () {
      final overpaid = DocumentPdfService.invoicePaymentAmounts({
        'total_amount': 100,
        'paid_amount': 120,
      });
      expect(overpaid['remaining'], 0);
      final zero = DocumentPdfService.invoicePaymentAmounts({});
      expect(zero['remaining'], 0);
    });

    test('decimal cents are preserved', () {
      final amounts = DocumentPdfService.invoicePaymentAmounts({
        'total_amount': '100.25',
        'paid_amount': '50.10',
        'pending_payment': '25.05',
      });
      expect((amounts['remaining']! - 25.10).abs() < 0.001, isTrue);
    });

    test('partial invoice PDF can render with payment breakdown', () async {
      final bytes = await DocumentPdfService.build({
        'kind': 'invoice',
        'document_number': '6330',
        'document_date': '2026-10-09',
        'customer_name': 'Test Customer',
        'net_amount': 900,
        'tax_amount': 72,
        'total_amount': 972,
        'paid_amount': 250,
        'pending_payment': 150,
        'lines': <Map<String, dynamic>>[],
      });
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    });
  });
}
