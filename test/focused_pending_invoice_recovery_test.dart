import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending invoice recovery bypasses broad 22-stage sync', () {
    final source =
        File('lib/screens/settings/local_sync_status_screen.dart')
            .readAsStringSync();
    final start = source.indexOf('Future<void> _recoverPendingInvoices() async');
    final end = source.indexOf('Future<void> _syncNow() async', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final recovery = source.substring(start, end);

    // Recovery cannot silently erase any original queued finance record.
    expect(recovery, isNot(contains('DELETE FROM')));
    expect(recovery, isNot(contains('UPDATE sync_outbox')));
    expect(recovery, contains('_customerVehicleAdmin.flush(widget.businessId)'));
    expect(recovery, contains('_documentDrafts.flush(widget.businessId)'));
    expect(recovery, contains('_payments.flush(widget.businessId)'));

    final parent = recovery.indexOf('_customerVehicleAdmin.flush(');
    final invoice = recovery.indexOf('_documentDrafts.flush(');
    final payment = recovery.indexOf('_payments.flush(');
    expect(parent, lessThan(invoice));
    expect(invoice, lessThan(payment));

    expect(recovery, contains("_pendingRecoveryOperations('customer_create')"));
    expect(recovery, contains("_pendingRecoveryOperations('vehicle_create')"));
    expect(recovery, contains("_pendingRecoveryOperations('document_draft_create')"));
    expect(recovery, contains("_pendingRecoveryOperations('invoice_payment_received')"));

    // Crucially, no unrelated module network pull or tax-setting RPC.
    expect(recovery, isNot(contains('_taxSettings.refresh')));
    expect(recovery, isNot(contains('_catalog.pull')));
    expect(recovery, isNot(contains('_appointments.pull')));
    expect(recovery, isNot(contains('_jobs.pull')));

    expect(source, contains('Recover pending invoices'));
    expect(source, contains('_syncStep / (_targetedRecovery ? 3 : _syncStepCount)'));
    expect(source, contains('onPressed: _syncing ? null : _recoverPendingInvoices'));
  });
}
