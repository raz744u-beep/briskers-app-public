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

  test('Owner finalization refreshes after auto-close without repeating payment', () {
    final code = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final begin = code.indexOf('Future<void> _finalizeEnteredPayments() async');
    final end = code.indexOf('Future<void> _enterWarrantyPayment() async', begin);
    expect(begin, greaterThan(0));
    expect(end, greaterThan(begin));
    final flow = code.substring(begin, end);
    final finalization = flow.indexOf('await _api.finalizePendingInvoicePayment(');
    final close = flow.indexOf('await _autoCloseOwnerInvoiceIfReady();');
    final refresh = flow.indexOf('await _load(fastAfterMutation: true);');
    expect(finalization, greaterThan(0));
    expect(close, greaterThan(finalization));
    expect(refresh, greaterThan(close));
    expect(flow.substring(close), isNot(contains('finalizePendingInvoicePayment(')));
  });

  test('status pill prioritizes confirmed close over final payment', () {
    final source = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final begin = source.indexOf('String _invoiceStatusCode({');
    final end = source.indexOf('String _statusLabel({', begin);
    expect(begin, greaterThan(0));
    expect(end, greaterThan(begin));
    final code = source.substring(begin, end);
    expect(code, contains("if (rawStatus == 'void') return 'void';"));
    expect(code, contains(".isClosed) return 'closed';"));
    expect(
      code.indexOf(".isClosed) return 'closed';"),
      lessThan(code.indexOf("if (total > 0 && finalizedPaid >= total - 0.005)")),
    );
  });
}
