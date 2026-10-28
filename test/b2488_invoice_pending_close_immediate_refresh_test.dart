import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/local_invoice_payment_coverage_events.dart';

void main() {
  test('Only exact invoice local coverage event reaches the list subscription', () async {
    final received = <LocalInvoicePaymentCoverageChanged>[];
    final subscription =
        LocalInvoicePaymentCoverageEvents.changes.listen(received.add);
    addTearDown(subscription.cancel);

    LocalInvoicePaymentCoverageEvents.committed(
      const LocalInvoicePaymentCoverageChanged(
        businessId: 'shop-a', invoiceId: 'invoice-6358',
        coversRemainingBalance: true));
    LocalInvoicePaymentCoverageEvents.committed(
      const LocalInvoicePaymentCoverageChanged(
        businessId: 'shop-a', invoiceId: 'invoice-6358',
        coversRemainingBalance: false));
    LocalInvoicePaymentCoverageEvents.committed(
      const LocalInvoicePaymentCoverageChanged(
        businessId: '', invoiceId: 'invalid',
        coversRemainingBalance: true));
    expect(received.length, 2);
    expect(received.first.invoiceId, 'invoice-6358');
    expect(received.first.coversRemainingBalance, isTrue);
    expect(received.last.coversRemainingBalance, isFalse);
  });

  test('Coverage emits only after durable receipt queue commit', () {
    final source = File('lib/services/offline_invoice_payment_ledger.dart')
        .readAsStringSync();
    final begin = source.indexOf('Future<String> recordReceivedPayment(');
    final end = source.indexOf('Future<void> editNeverSubmittedPayment(', begin);
    final method = source.substring(begin, end);
    expect(begin, greaterThan(0));
    expect(end, greaterThan(begin));
    expect(method, contains("entity_type, entity_id, operation, payload_json"));
    expect(method, contains('LocalInvoicePaymentCoverageEvents.committed('));
    expect(method.indexOf('LocalInvoicePaymentCoverageEvents.committed('),
        greaterThan(method.lastIndexOf('    });'));
    expect(method, contains('remainingBeforePaymentCents > 0'));
    expect(method, contains('amountCents >= remainingBeforePaymentCents'));
    expect(method, contains('return operationId;'));
    for (final edit in ['editNeverSubmittedPayment(', 'queueServerPendingEdit(',
        'deleteNeverSubmittedPayment(']) {
      final start = source.indexOf(edit);
      final next = source.indexOf('  Future<', start + 3);
      final body = source.substring(start, next < 0 ? source.length : next);
      expect(body, contains('coversRemainingBalance: false'),
          reason: '$edit must invalidate any previous local coverage hint');
    }
  });

  test('Open invoices transition to Pending Close immediately, never Closed', () {
    final source = File('lib/screens/documents_screen.dart').readAsStringSync();
    expect(source, contains('LocalInvoicePaymentCoverageEvents.changes.listen('));
    expect(source, contains('_locallyCoveredInvoiceIds.add(event.invoiceId)'));
    expect(source, contains('_locallyCoveredInvoiceIds.remove(event.invoiceId)'));
    expect(source, contains("_locallyCoveredInvoiceIds.contains(row['id']?.toString())"));
    expect(source, contains("return 'Pending Close';"));
    expect(source, contains("status != 'Closed' && status != 'Void' && status != 'Reopened'"));
    expect(source, contains('_localPaymentEvents?.cancel()'));
    expect(source, contains('_locallyCoveredInvoiceIds.clear();'));
    expect(source, contains('unawaited(_load());'));
  });

  test('Posted payment and actual close still require independent verification', () {
    final source = File('lib/services/verified_invoice_payment_events.dart')
        .readAsStringSync();
    expect(source, contains('Never emit for entered/queued/pending receipts.'));
    final docs = File('lib/screens/documents_screen.dart').readAsStringSync();
    expect(docs, contains('VerifiedInvoiceCloseEvents.changes.listen('));
    expect(docs, contains('_locallyCoveredInvoiceIds.remove(event.invoiceId);'));
    final guard = File('lib/services/invoice_finalization_guard.dart')
        .readAsStringSync();
    expect(guard, contains('isOwner'));
    expect(guard, contains('_forceOffline()'));
    expect(guard, contains('invoiceTotal - finalizedPayments'));
  });
}
