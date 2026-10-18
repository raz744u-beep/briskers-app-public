import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending-sync receipts open same-ID edit; never use legacy write API', () {
    final code = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final menuStart = code.indexOf('Future<void> _showPaymentContextMenu(');
    final editStart = code.indexOf('Future<void> _editPayment(', menuStart);
    final deleteStart = code.indexOf('Future<void> _deletePayment(', editStart);
    expect(menuStart, greaterThan(0));
    expect(editStart, greaterThan(menuStart));
    expect(deleteStart, greaterThan(editStart));

    final menu = code.substring(menuStart, editStart);
    final edit = code.substring(editStart, deleteStart);
    expect(menu, isNot(contains("payment['pending_sync'] == true ||")));
    expect(menu, contains('await _editPayment(payment)'));
    expect(menu, contains('!BriskersConnectionModeController.instance.forceOffline'));
    expect(menu, contains("payment['pending_sync'] != true"));
    expect(edit, contains("payment['_local_pending_payment'] == true"));
    expect(edit, contains("payment['_local_pending_edit'] == true"));
    expect(edit, contains('editNeverSubmittedPayment('));
    expect(edit, contains('queueServerPendingEdit('));
    expect(edit, contains('updatePendingInvoicePaymentV2('));
    expect(edit, isNot(contains('updatePendingInvoicePayment(')));
    expect(edit, contains('initialPaymentDate: initialDate'));
    expect(edit, contains('editDate: true'));
  });

  test('pending corrections prevent finalizing an invoice', () {
    final code = File('lib/services/invoice_finalization_guard.dart')
        .readAsStringSync();
    expect(code, contains("'invoice_pending_payment_edit'"));
    expect(code, contains("'invoice_payment_received'"));
  });

  test('date editing is present and displayed as calendar date', () {
    final code = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    expect(code, contains('Future<void> _pickPaymentDate() async'));
    expect(code, contains('Payment date:'));
    expect(code, contains("_paymentDate(payment['payment_date'] ?? payment['entered_at'])"));
  });
}
