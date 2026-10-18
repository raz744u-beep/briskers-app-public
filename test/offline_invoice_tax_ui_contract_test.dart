import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice Tax Save branches to durable local queue in Force Offline', () {
    final source = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final start = source.indexOf('Future<void> _editInvoiceTax(');
    final end = source.indexOf('String _taxLabel(', start);
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final edit = source.substring(start, end);
    expect(edit, contains('BriskersConnectionModeController.instance.forceOffline'));
    expect(edit, contains('_offlineInvoiceTax.saveOffline('));
    expect(edit, contains('expectedVersion: currentVersion'));
    expect(edit, contains('oldRate: oldRate'));
    expect(edit, contains('newRate: selectedRate'));
    expect(edit, contains('Tax correction saved locally, pending sync'));
    expect(edit, contains('Existing payment unchanged'));
    expect(edit, isNot(contains('onPressed: offline || proposed == null')));
    expect(edit, contains('onPressed: proposed == null'));
  });

  test('offline tax operation integrates with early guarded replay', () {
    final gate = File('lib/screens/business_gate.dart').readAsStringSync();
    final edits = gate.indexOf('await _offlineDocumentEdit.flush(businessId)');
    final tax = gate.indexOf('await _offlineInvoiceTax.flush(businessId)');
    final payments = gate.indexOf('await _offlinePayments.flush(businessId)');
    expect(edits, greaterThan(0));
    expect(tax, greaterThan(edits));
    expect(payments, greaterThan(tax));

    final guard = File('lib/services/invoice_finalization_guard.dart')
        .readAsStringSync();
    expect(guard, contains("'invoice_tax_edit'"));
  });

  test('offline tax Save has a persisted local preview and index projection', () {
    final source = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    expect(
      RegExp(r'_offlineInvoiceTax\.projectPending\(')
          .allMatches(source).length,
      greaterThanOrEqualTo(4),
    );
    expect(source, contains("'_local_tax_sync_state'"));
    expect(source, contains('Tax correction saved on this phone'));
    final service = File('lib/services/offline_invoice_tax_service.dart')
        .readAsStringSync();
    expect(service, contains("'_local_pending_tax'"));
  });
}
