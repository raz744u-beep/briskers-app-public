import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/confirmed_invoice_list_events.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only a server-confirmed closed invoice updates the local index', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final repo = LocalDocumentRepository(database:db);
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,kind,status,"
      "display_status_code,total,row_version,sync_state) VALUES "
      "('invoice','shop','invoice','issued','pending_close',175.60,4,'synced')",
    );
    await repo.applyConfirmedServerClose(
      'shop','invoice',closedAt:'2026-10-18T16:12:00Z',rowVersion:5);
    final rows=await repo.listByKind('shop',kind:'invoice');
    expect(rows.single['display_status_code'],'closed');
    expect(invoiceNeedsPayment(rows.single,receipts:0),isFalse);
    expect(rows.single['row_version'],5);

    // A slow older update cannot replace a higher verified version.
    await repo.applyConfirmedServerClose(
      'shop','invoice',closedAt:'2026-10-18T16:11:00Z',rowVersion:4);
    final again=await repo.listByKind('shop',kind:'invoice');
    expect(again.single['row_version'],5);
    await db.close();
  });

  test('pending unsynced invoice is not forcibly marked closed', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final repo=LocalDocumentRepository(database:db);
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,kind,status,"
      "display_status_code,total,row_version,sync_state) VALUES "
      "('unsynced','shop','invoice','issued','pending_close',175.60,4,'pending')",
    );
    await repo.applyConfirmedServerClose(
      'shop','unsynced',closedAt:'2026-10-18T16:12:00Z',rowVersion:5);
    final row=(await db.customSelect(
      "SELECT display_status_code FROM local_documents WHERE id='unsynced'"))
      .getSingle();
    expect((await row).read<String>('display_status_code'),'pending_close');
    await expectLater(repo.applyConfirmedServerClose(
      'shop','unsynced',closedAt:'',rowVersion:6),throwsStateError);
    await db.close();
  });

  test('closure events require actual timestamp and version evidence', () async {
    expect(() => ConfirmedInvoiceListEvents.publishClosed(
      const ConfirmedInvoiceClosed(businessId:'shop',
        invoiceId:'a',closedAt:'',rowVersion:4)), throwsStateError);
    expect(() => ConfirmedInvoiceListEvents.publishClosed(
      const ConfirmedInvoiceClosed(businessId:'shop',
        invoiceId:'a',closedAt:'2026-10-18T16:12:00Z',rowVersion:0)),
      throwsStateError);
  });

  test('list subscribes to confirmed closure, and stale responses keep overlay', () async {
    final screen=await File('lib/screens/documents_screen.dart').readAsString();
    final detail=await File('lib/screens/jobs/job_document_screen.dart')
      .readAsString();
    expect(screen,contains('ConfirmedInvoiceListEvents.closed.listen'));
    expect(screen,contains('_withConfirmedClosures('));
    expect(screen,contains('_rows = _withConfirmedClosures('));
    expect(detail,contains('applyConfirmedServerClose('));
    expect(detail,contains('ConfirmedInvoiceListEvents.publishClosed('));
    final start=detail.indexOf('Future<void> _autoCloseOwnerInvoiceIfReady()');
    final end=detail.indexOf('Future<void> _finalizeEnteredPayments()',start);
    final flow=detail.substring(start,end);
    expect(flow.indexOf('await _api.documentDetail(',flow.indexOf('await InvoiceFinalizationGuard().run<void>(')),
      greaterThan(flow.indexOf('await InvoiceFinalizationGuard().run<void>(')));
    expect(flow,contains('DateTime.tryParse(closedAt) != null'));
  });
}
