import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/document_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Offline receipt number', () {
    test('uses full collision-resistant local invoice ID in the existing number field', () async {
      const id = 'local-invoice-12345678-1234-4234-9234-123456789abc';
      final detail = <String, dynamic>{
        'id': id,
        'kind': 'invoice',
        'document_number': null,
        'total_amount': 500,
        'paid_amount': 0,
        'pending_payment': 500,
        'lines': <Map<String, dynamic>>[],
      };
      expect(
        DocumentPdfService.fileName(detail),
        'Briskers-Invoice-TMP-12345678-1234-4234-9234-123456789abc.pdf',
      );
      final bytes = await DocumentPdfService.build(detail);
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('permanent number supersedes temporary ID on the PDF', () {
      expect(DocumentPdfService.fileName({
        'id': 'local-invoice-12345678-1234-4234-9234-123456789abc',
        'kind': 'invoice',
        'document_number': '6332',
      }), 'Briskers-Invoice-6332.pdf');
    });

    test('unrelated missing-number documents do not get invented references', () {
      expect(DocumentPdfService.fileName({
        'kind': 'invoice', 'document_number': null,
      }), 'Briskers-Invoice.pdf');
    });
  });

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

    test('fully entered debit-card payment is recorded but not yet finalized', () {
      final amounts = DocumentPdfService.invoicePaymentAmounts({
        'total_amount': '317.49',
        'paid_amount': '0.00',
        'pending_payment': '317.49',
      });
      expect(amounts['paid'], 0);
      expect(amounts['pending'], 317.49);
      expect(amounts['paid']! + amounts['pending']!, 317.49);
      expect(amounts['remaining'], 0);
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

  group('PDF-001 individual payment methods and presentation math', () {
    test('customer-facing PDF has no unapproved pending text', () async {
      final source = await File('lib/services/document_pdf_service.dart')
          .readAsString();
      expect(source, isNot(contains('Pending entries are not yet finalized')));
      expect(source, isNot(contains('Method not recorded (Pending)')));
      final rows = DocumentPdfService.invoicePaymentLines({
        'total_amount': 100,
        'paid_amount': 0,
        'pending_payment': 40,
        'payments': [
          {
            'amount': 40,
            'state': 'pending',
            'payment_method_name': 'Debit card',
          },
        ],
      });
      expect(rows.single['label'], 'Payment - Debit card');
      expect(rows.single['pending'], isTrue);
      expect(rows.single['amount'], 40);
    });

    test('two finalized methods plus one pending card stay itemized', () {
      final detail = <String, dynamic>{
        'total_amount': 972,
        'paid_amount': 500,
        'pending_payment': 150,
        'payments': [
          {'amount': 250, 'state': 'finalized',
            'payment_method_name': 'Cash'},
          {'amount': 250, 'state': 'posted',
            'payment_method_name': 'Check'},
          {'amount': 150, 'state': 'pending',
            'payment_method_name': 'Credit card'},
        ],
      };
      final lines = DocumentPdfService.invoicePaymentLines(detail);
      expect(lines.map((row) => row['label']), [
        'Payment - Cash',
        'Payment - Check',
        'Payment - Credit card',
      ]);
      expect(lines.map((row) => row['amount']), [250, 250, 150]);
      expect(lines.last['pending'], isTrue);
      final summary = DocumentPdfService.invoicePaymentAmounts(detail);
      expect(summary['remaining'], 322);
      expect(lines.fold<num>(0, (sum, row) => sum + (row['amount'] as num)),
          summary['paid']! + summary['pending']!);
    });

    test('missing or stale breakdown uses aggregates without guessing method', () {
      final detail = <String, dynamic>{
        'total_amount': 1000,
        'paid_amount': 600,
        'pending_payment': 100,
        'payments': [
          {'amount': 200, 'state': 'posted',
            'payment_method_name': 'Credit card'},
        ],
      };
      final lines = DocumentPdfService.invoicePaymentLines(detail);
      expect(lines.map((row) => row['label']), [
        'Payment - Method not recorded',
        'Payment - Method not recorded',
      ]);
      expect(lines.map((row) => row['amount']), [600, 100]);
      expect(DocumentPdfService.invoicePaymentAmounts(detail)['remaining'],
          300);
    });

    test('voided/reversed items never inflate the received total', () {
      final lines = DocumentPdfService.invoicePaymentLines({
        'total_amount': 100,
        'paid_amount': 35.25,
        'pending_payment': 0,
        'payments': [
          {'amount': 35.25, 'state': 'posted',
            'payment_method_name': 'Debit card'},
          {'amount': 40, 'state': 'reversed',
            'payment_method_name': 'Check'},
        ],
      });
      expect(lines.length, 1);
      expect(lines.single['label'], 'Payment - Debit card');
      expect(lines.single['amount'], 35.25);
    });

    test('zero and fully paid invoices have correct payment lines', () {
      expect(DocumentPdfService.invoicePaymentLines({
        'total_amount': 200,
        'paid_amount': 0,
        'pending_payment': 0,
      }), isEmpty);
      final fullyPaid = {
        'total_amount': 200,
        'paid_amount': 200,
        'pending_payment': 0,
        'payments': [
          {'amount': 200, 'state': 'finalized',
            'payment_method_name': 'Warranty check'},
        ],
      };
      expect(DocumentPdfService.invoicePaymentLines(fullyPaid).single['label'],
          'Payment - Warranty check');
      expect(DocumentPdfService.invoicePaymentAmounts(fullyPaid)['remaining'],
          0);
    });

    test('a multi-payment invoice and a plain estimate both render', () async {
      final detail = <String, dynamic>{
        'kind': 'invoice',
        'document_number': '6330',
        'customer_name': 'PDF Test',
        'total_amount': 500,
        'net_amount': 500,
        'tax_amount': 0,
        'paid_amount': 400,
        'pending_payment': 100,
        'payments': [
          {'amount': 200, 'state': 'posted',
            'payment_method_name': 'Cash'},
          {'amount': 200, 'state': 'posted',
            'payment_method_name': 'Check'},
          {'amount': 100, 'state': 'pending',
            'payment_method_name': 'Credit card'},
        ],
        'lines': <Map<String, dynamic>>[],
      };
      final invoiceBytes = await DocumentPdfService.build(detail);
      expect(utf8.decode(invoiceBytes.sublist(0, 5)), '%PDF-');
      final estimateBytes = await DocumentPdfService.build({
        ...detail,
        'kind': 'estimate',
      });
      expect(utf8.decode(estimateBytes.sublist(0, 5)), '%PDF-');
    });
  });
}
