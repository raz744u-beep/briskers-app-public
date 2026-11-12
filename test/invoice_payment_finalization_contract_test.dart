import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PAY-001 entered payments are not auto-finalized from invoice screen', () async {
    final screen=await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    expect(screen,contains('Finalize received payment?'));
    expect(screen,contains('Confirm that'));
    expect(screen,contains('Finalize Payment'));
    final method=screen.indexOf('Future<void> _finalizeEnteredPayments()');
    final end=screen.indexOf('Future<void> _enterWarrantyPayment()',method);
    final code=screen.substring(method,end);
    final consent=code.indexOf('if (!confirmed || !mounted) return;');
    final save=code.indexOf('OfflineInvoiceFinalization().save(');
    expect(code.indexOf('stateForDetail('),lessThan(consent));
    expect(consent,greaterThan(0));
    expect(save,greaterThan(consent));
    expect(code.indexOf('OfflineInvoiceFinalization().flush('),greaterThan(save));
    expect(code,isNot(contains('finalizePendingInvoicePayment(')));
    expect(code,contains('close:false'));
  });
}
