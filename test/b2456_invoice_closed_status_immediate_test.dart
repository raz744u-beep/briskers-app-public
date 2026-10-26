import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/documents_screen.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/verified_invoice_close_events.dart';

void main() {
  test('Confirmed Closed outranks stale or missing receipt totals', () {
    const previouslyIssued = {
      'id': 'synthetic-invoice',
      'kind': 'invoice',
      'status': 'issued',
      'total_amount': 1198.05,
      'paid_amount': 0.0,
      'pending_payment': 0.0,
    };
    final closed = {...previouslyIssued,
      'status': 'closed', 'display_status_code': 'closed'};
    expect(invoiceListStageWithReceipts(closed, receipts: 0), 'Closed');
    expect(invoiceListStageWithReceipts(closed, receipts: 100), 'Closed');
    expect(invoiceListStageWithReceipts({
      ...previouslyIssued, 'closed_at': '2026-10-26T15:00:00Z',
    }, receipts: 0), 'Closed');
    expect(invoiceListStageWithReceipts({
      ...previouslyIssued, 'display_status_code': 'reopened',
    }, receipts: 1198.05), 'Reopened');
    expect(invoiceListStageWithReceipts({
      ...previouslyIssued, 'status': 'void',
    }, receipts: 0), 'Void');
    // A completed Job or full receipt alone is NOT authoritative closure.
    expect(invoiceListStageWithReceipts(previouslyIssued, receipts: 0),
        isNot('Closed'));
    expect(invoiceListStageWithReceipts(previouslyIssued, receipts: 1198.05),
        isNot('Closed'));
  });

  test('Only a confirmed close updates matching local synced invoice index', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    const shop = 'synthetic-shop';
    await db.customStatement(
      """INSERT INTO local_documents
        (id,business_id,kind,document_number,status,display_status_code,
         total,sync_state) VALUES
        ('I-6354',?,'invoice','6354','issued','open',1198.05,'synced'),
        ('I-pending',?,'invoice','9999','issued','open',123,'pending'),
        ('I-elsewhere','other','invoice','6354','issued','open',1198.05,'synced')""",
      [shop,shop],
    );
    final repo = LocalDocumentRepository(database: db);
    await repo.recordServerConfirmedClosed(shop, 'I-6354');
    await repo.recordServerConfirmedClosed(shop, 'I-pending');
    await repo.recordServerConfirmedClosed(shop, 'missing');
    final rows = await db.customSelect(
      'SELECT id,status,display_status_code,total,sync_state FROM local_documents '
      'ORDER BY id',
    ).get();
    final byId = {for (final row in rows) row.read<String>('id'): row};
    expect(byId['I-6354']!.read<String>('status'), 'closed');
    expect(byId['I-6354']!.read<String>('display_status_code'), 'closed');
    expect(byId['I-6354']!.read<double>('total'), 1198.05);
    expect(byId['I-pending']!.read<String>('status'), 'issued');
    expect(byId['I-pending']!.read<String>('sync_state'), 'pending');
    expect(byId['I-elsewhere']!.read<String>('status'), 'issued');
    await db.close();
  });

  test('Closure event broadcasts only a scoped confirmed identity', () async {
    final events = <VerifiedInvoiceClosed>[];
    final sub = VerifiedInvoiceCloseEvents.changes.listen(events.add);
    VerifiedInvoiceCloseEvents.serverConfirmed(
      const VerifiedInvoiceClosed(
        businessId: 'synthetic-shop', invoiceId: 'I-6354',
      ),
    );
    VerifiedInvoiceCloseEvents.serverConfirmed(
      const VerifiedInvoiceClosed(
        businessId: '', invoiceId: 'I-invalid',
      ),
    );
    expect(events, hasLength(1));
    expect(events.single.businessId, 'synthetic-shop');
    expect(events.single.invoiceId, 'I-6354');
    await sub.cancel();
  });

  test('Every close path updates retained list after verified RPC, not before', () {
    final docs = File('lib/screens/documents_screen.dart').readAsStringSync();
    final closeService = File(
      'lib/services/owner_invoice_auto_close_service.dart').readAsStringSync();
    final detail = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();

    expect(docs, contains('VerifiedInvoiceCloseEvents.changes.listen('));
    expect(docs, contains("'display_status_code': 'closed'"));
    expect(docs, contains('++_loadEpoch;'));
    expect(docs, contains('unawaited(_load());'));
    expect(docs, contains('invoiceListStageWithReceipts('));
    expect(docs, contains("if (const {'Closed', 'Void', 'Reopened'}.contains(existing))"));
    expect(closeService, contains('await _guard.run<void>('));
    expect(closeService, contains('.recordServerConfirmedClosed(businessId, id)'));
    expect(closeService, contains('VerifiedInvoiceCloseEvents.serverConfirmed('));
    expect(detail, contains('await InvoiceFinalizationGuard().run<void>('));
    expect(detail, contains('VerifiedInvoiceCloseEvents.serverConfirmed('));
    expect(docs, contains('await _finalizationGuard.run('));
    expect(docs, contains('VerifiedInvoiceCloseEvents.serverConfirmed('));
  });
}
