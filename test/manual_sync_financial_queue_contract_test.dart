import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Manual Sync Now processes invoice tax, receipt, and same-payment edit in order', () async {
    final source = await File(
      'lib/screens/settings/local_sync_status_screen.dart',
    ).readAsString();
    final start = source.indexOf('Future<void> _syncNow()');
    final end = source.indexOf('Widget _countTile(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final sync = source.substring(start, end);

    final tax = sync.indexOf('_invoiceTax.flush(widget.businessId)');
    final received = sync.indexOf('_invoicePayments.flush(widget.businessId)');
    final edited = sync.indexOf(
      '_invoicePayments.flushPendingServerEdits(widget.businessId)',
    );
    expect(tax, greaterThanOrEqualTo(0));
    expect(received, greaterThan(tax));
    expect(edited, greaterThan(received));

    expect(sync, contains('BriskersConnectionModeController.instance.forceOffline'));
    expect(sync, contains('Unreconciled local operations remain'));
    expect(sync, contains("state IN ('pending','inflight','conflict')"));
    expect(sync, contains('recordManualRefreshResult'));
    expect(
      sync.indexOf('recordManualRefreshResult'),
      greaterThan(sync.indexOf('Unreconciled local operations remain')),
    );
    expect(source, contains('static const int _syncStepCount = 22;'));
    expect(RegExp(r'await attempt\(').allMatches(sync).length, 22);
  });

  test('Job admin audit reads only local data and describes queued changes', () async {
    final source = await File(
      'lib/screens/settings/local_sync_status_screen.dart',
    ).readAsString();
    final start = source.indexOf('// Local-only preflight:');
    final end = source.indexOf('pendingDetails.add({', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final audit = source.substring(start, end);
    expect(audit, contains('widget.isOwner'));
    expect(audit, contains("entity_type') == 'job_admin'"));
    expect(audit, contains('FROM local_jobs'));
    expect(audit, contains('FROM local_documents'));
    expect(audit, contains("entity_type='job_create'"));
    expect(audit, contains('Queued change:'));
    expect(audit, contains('Queued Job creation:'));
    expect(audit, contains('Review only:'));
    expect(audit, isNot(contains('_api.')));
    expect(audit, isNot(contains('.flush(')));
    expect(audit, isNot(contains('DELETE FROM')));
    expect(audit, isNot(contains('UPDATE ')));
  });
}
