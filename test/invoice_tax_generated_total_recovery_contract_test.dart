import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated total tax migration does not assign total_amount', () async {
    final sql = await File(
      'tools/migrations/invoice_tax_generated_total_fix_20261018.sql',
    ).readAsString();
    expect(sql, contains("a.attgenerated='s'"));
    expect(sql, contains('perform briskers.recalculate_native_document('));
    expect(sql, contains('select x.total_amount,x.tax_amount into v_total,v_tax'));
    expect(sql, isNot(contains('set total_amount=')));
    expect(sql, contains("briskers.require_permission(p_business_id, 'invoices.edit')"));
    expect(sql, contains('d.row_version <> p_expected_version'));
    expect(sql, contains('briskers.capture_document_revision('));
    expect(sql, contains('v_pending > v_total + 0.005'));
    expect(sql, contains('briskers_invoice_tax_patch_level_v1'));
  });

  test('tax recovery cannot automatically replay rejected invoice or payment', () async {
    final service = await File('lib/services/offline_invoice_tax_service.dart')
        .readAsString();
    final start = service.indexOf('Future<void> requeueVerifiedGeneratedTotalRejection(');
    final end = service.indexOf('Future<Map<String, dynamic>> projectPending(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = service.substring(start, end);
    expect(body, contains('invoiceTaxPatchLevel('));
    expect(body, contains('generated_total_safe_20261018'));
    expect(body, contains('428c9'));
    expect(body, contains('generated column'));
    expect(body, contains("read<String>('state') != 'inflight'"));
    expect(body, contains("read<int>('attempt_count') != 1"));
    expect(body, contains('_sameLines('));
    expect(body, contains('LocalJobQuarantine.assertReplayAllowed'));
    expect(body, contains("state='pending',last_error=NULL"));
    expect(body, isNot(contains('updateInvoiceTaxRate(')));
    expect(body, isNot(contains('flush(businessId)')));
    expect(body, isNot(contains('finalizePendingInvoicePayment(')));
  });

  test('owner must explicitly authorize rejected tax recovery', () async {
    final ui = await File('lib/screens/settings/local_sync_status_screen.dart')
        .readAsString();
    final start = ui.indexOf('Future<void> _reviewKnownRejectedTax(');
    final end = ui.indexOf('Future<void> _syncNow()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = ui.substring(start, end);
    expect(body, contains('widget.isOwner'));
    expect(body, contains('forceOffline'));
    expect(body, contains('showDialog<bool>'));
    expect(body, contains('if (!approved || !mounted) return;'));
    expect(body, contains('requeueVerifiedGeneratedTotalRejection('));
    expect(ui, contains("error.contains('428c9')"));
  });
}
