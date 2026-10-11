import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PAY-001 entered payments are not auto-finalized from invoice screen', () async {
    final screen=await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    expect(screen,contains('Finalize received payment?'));
    expect(screen,contains('Confirm that'));
    expect(screen,contains('Finalize Payment'));
    expect(screen,contains('finalizePendingInvoicePayment('));
    final method=screen.indexOf('Future<void> _finalizeEnteredPayments()');
    final end=screen.indexOf('Future<void> _enterWarrantyPayment()',method);
    expect(method,greaterThanOrEqualTo(0));
    expect(end,greaterThan(method));
    final code=screen.substring(method,end);
    expect(code,contains('forceOffline'));
    expect(code,contains('if (!confirmed || !mounted) return;'));
    expect(code,contains('await _api.finalizePendingInvoicePayment('));
  });
}
