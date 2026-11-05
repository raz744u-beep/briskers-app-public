import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Force Offline closeout exits before selection and server RPC', () {
    final source = File('lib/screens/documents_screen.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _showCloseInvoices() async {');
    final end = source.indexOf('Future<void> _showExpensesFromList(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final closeAction = source.substring(start, end);
    final offlineGuard = closeAction.indexOf(
      'if (BriskersConnectionModeController.instance.forceOffline) {',
    );
    final selection = closeAction.indexOf('final eligible =');
    final preflight = closeAction.indexOf('_finalizationGuard.check(');
    final rpc = closeAction.indexOf('_api.closeInvoice(');
    expect(offlineGuard, greaterThanOrEqualTo(0));
    expect(selection, greaterThan(offlineGuard));
    expect(preflight, greaterThan(selection));
    expect(rpc, greaterThan(preflight));

    final guard = closeAction.substring(offlineGuard, selection);
    expect(guard, contains("setState(() => _error = null)"));
    expect(guard, contains('Invoice closeout is paused offline'));
    expect(guard, contains('Continue offline'));
    expect(guard, contains('Pending Close'));
    expect(guard, contains('No invoice was closed'));
    expect(guard, contains('Sync needs attention'));
    expect(guard, contains('return;'));
    expect(guard, isNot(contains('_api.')));
    expect(guard, isNot(contains('_finalizationGuard.run')));
  });

  test('Never bypass durable receipt/sync gate to mark invoice Closed', () {
    final guard = File('lib/services/invoice_finalization_guard.dart')
        .readAsStringSync();
    final docs = File('lib/screens/documents_screen.dart').readAsStringSync();
    expect(guard, contains("if (_forceOffline()) throw StateError("));
    expect(guard, contains("'invoice_payment_received'"));
    expect(guard, contains("'invoice_pending_payment_edit'"));
    expect(guard, contains("'invoice_tax_edit'"));
    expect(docs, contains('VerifiedInvoiceCloseEvents.serverConfirmed('));
    expect(docs, contains('recordServerConfirmedClosed('));
  });
}
