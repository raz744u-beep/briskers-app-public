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
    expect(menu, contains('BriskersConnectionModeController.instance.forceOffline'));
    expect(menu, contains("payment['pending_sync'] != true"));
    expect(menu, contains('if (widget.isOwner)'));
    expect(menu, contains('enabled: canRemove'));
    expect(menu, contains("'edit'"));
    expect(menu, contains("'remove'"));
    expect(edit, contains("payment['_local_pending_payment'] == true"));
    expect(edit, contains("payment['_local_pending_edit'] == true"));
    expect(edit, contains('editNeverSubmittedPayment('));
    expect(edit, contains('queueServerPendingEdit('));
    expect(edit, contains('originalAmountCents:'));
    expect(edit, contains('originalEnteredAt:'));
    expect(edit, contains('expectedRowVersion: version'));
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
  test('pending payment offers visible edit action and role-safe owner remove', () {
    final code=File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final start=code.indexOf('Widget _paymentTab(');
    final end=code.indexOf('Widget _notesTab(',start);
    expect(start,greaterThan(0));
    expect(end,greaterThan(start));
    final tab=code.substring(start,end);
    expect(tab,contains('onTap: editable && !_busy && _canManageInvoiceExpenses'));
    expect(tab,contains('onLongPress: editable && !_busy && _canManageInvoiceExpenses'));
    expect(tab,contains("tooltip: widget.isOwner"));
    expect(tab,contains('Icons.edit_outlined'));
    final a=code.indexOf('Future<void> _deletePayment(');
    final b=code.indexOf('Future<Map<String, dynamic>?> _pickInvoiceCustomer(',a);
    final removal=code.substring(a,b);
    expect(removal,contains('if (!widget.isOwner'));
    expect(removal,contains('deleteNeverSubmittedPayment('));
    expect(removal,contains('deletePendingInvoicePayment('));
    expect(removal,contains('payment[\'pending_sync\'] == true'));
  });

  test('invoice detail dock owns the bottom inset exactly once', () {
    final code=File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final a=code.lastIndexOf('bottomNavigationBar: Column(');
    final b=code.indexOf('class _DocumentTabsHeaderDelegate',a);
    expect(a,greaterThan(0));
    final dock=code.substring(a,b);
    expect(dock,contains('bottom: widget.sharedBottomNavigationBar == null'));
    expect(dock,contains('widget.sharedBottomNavigationBar!'));
    expect(dock,isNot(contains('bottom: MediaQuery.viewPaddingOf(context).bottom')));
  });

  test('unresolved invoice tax blocks payment finalization action', () {
    final code=File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    expect(code,contains("_detail?['_local_pending_tax'] == true"));
  });

}
