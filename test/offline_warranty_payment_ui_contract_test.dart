import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final screen = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();

  test('warranty shortcut persists before success and uses retry-safe replay', () {
    final start = screen.indexOf('Future<void> _enterWarrantyPayment()');
    final end = screen.indexOf('Future<void> _showPaymentContextMenu(', start);
    final action = screen.substring(start, end);
    expect(action, contains('final recorded = await _run('));
    expect(action, contains('await _offlinePayments.recordReceivedPayment('));
    expect(action, contains('expectedQueuedOperationIds: _queuedPaymentOperationIds'));
    expect(action, contains('await _offlinePayments.flush(widget.businessId)'));
    expect(action, isNot(contains('_api.addPendingInvoicePayment(')));
    expect(action, contains('if (!mounted || !recorded) return;'));
    expect(action, contains('Warranty payment recorded locally. Pending sync.'));
    expect(action, isNot(contains("tr('warrantyPaymentApplied')")));
    expect(action.indexOf('if (!mounted || !recorded) return;'),
        lessThan(action.indexOf('showSnackBar(')));
  });

  test('all four invoice load paths restore pending local payments', () {
    final start = screen.indexOf('Future<void> _load({');
    final end = screen.indexOf('int get _version', start);
    final load = screen.substring(start, end);
    expect('_withLocalPayments('.allMatches(load), hasLength(4));
    expect(load, contains('_warrantyDetail = _cachedWarrantyDetail(recovered)'));
    expect(load, contains('_warrantyDetail = _cachedWarrantyDetail(datedCached)'));
  });

  test('PDF refresh preserves local payment totals on the screen', () {
    final start = screen.indexOf('Future<Map<String, dynamic>?> _preparePdf()');
    final end = screen.indexOf('Future<void> _previewPdf()', start);
    final prepare = screen.substring(start, end);
    expect(prepare, isNot(contains('_detail = detail')));
    expect(prepare, contains('await _withLocalPayments(detail)'));
    expect(prepare, contains('return await _withPdfUnits(detail)'));
  });

  test('unreconciled local payments cannot be finalized or edited on server', () {
    final start = screen.indexOf('Future<void> _finalizeEnteredPayments()');
    final end = screen.indexOf('Future<void> _enterWarrantyPayment()', start);
    final finalize = screen.substring(start, end);
    expect(finalize, contains('_queuedPaymentOperationIds.isNotEmpty'));
    expect(screen, contains("_detail?['_payment_reconciliation_required']"));
    expect(finalize, contains('Connect and sync recorded payments before finalizing'));
    expect(screen, contains("payment['pending_sync'] == true ||"));
    expect(screen, contains("label: 'Pending sync'"));
    expect(screen, contains('paymentPendingLabel: _warrantyPaymentProcessed(pendingOnly: true)'));
    final panel = File('lib/screens/jobs/invoice_warranty_panel.dart').readAsStringSync();
    expect(panel, contains("widget.paymentPendingLabel ?? (widget.paymentProcessed"));
  });
}
