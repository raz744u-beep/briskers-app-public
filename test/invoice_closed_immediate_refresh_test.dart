import 'dart:io';

import 'package:briskers_app/core/document_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closed_at overrides legacy issued status and full paid amount', () {
    final invoice = {
      'kind': 'invoice',
      'document_number': '6347',
      'status': 'issued',
      'closed_at': '2026-10-21T17:49:33Z',
      'total_amount': 1597.80,
      'paid_amount': 1597.80,
      'pending_payment': 0,
    };
    final display = DocumentPresentation(invoice);
    expect(display.isClosed, isTrue);
    expect(display.statusLabel, 'Closed');
    expect(display.statusCode, 'closed');
  });

  test('Owner finalization refreshes the invoice without changing its lifecycle', () {
    final code = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final begin = code.indexOf('Future<void> _finalizeEnteredPayments() async');
    final end = code.indexOf('Future<void> _enterWarrantyPayment() async', begin);
    final flow = code.substring(begin, end);
    expect(flow, contains('await _run(() => OfflineInvoiceFinalization().finalizeLocally('));
    expect(flow, isNot(contains('closeInvoice(')));
    expect(flow, isNot(contains('finalizePendingInvoicePayment(')));
  });

  test('status pill prioritizes confirmed close over final payment', () {
    final source = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final begin = source.indexOf('String _invoiceStatusCode({');
    final end = source.indexOf('String _statusLabel({', begin);
    expect(begin, greaterThan(0));
    expect(end, greaterThan(begin));
    final code = source.substring(begin, end);
    expect(code, contains('DocumentPresentation('));
    expect(code, contains('.statusCode'));

  });
}
