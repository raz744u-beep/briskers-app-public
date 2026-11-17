import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/document_copy_plan.dart';
import 'package:briskers_app/services/invoice_tax_proposal.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/offline_document_edit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('copy applies current configured rate and preserves historical exemptions', () {
    final original = <String, dynamic>{'kind': 'invoice', 'lines': [
      {'name': 'Part', 'quantity': 1, 'unit_price': 100, 'tax_rate': .0925},
      {'name': 'Exempt', 'quantity': 1, 'unit_price': 50, 'tax_rate': 0},
    ]};
    final plan = DocumentCopyPlan.prepare(original,
      customerId: 'customer', vehicleId: null, currentTaxRate: .0975);
    final lines = plan['lines'] as List;
    expect(lines[0]['tax_rate'], .0975);
    expect(lines[1]['tax_rate'], 0);
    expect((original['lines'] as List)[0]['tax_rate'], .0925);
  });

  test('legacy rounding permits correction while unrelated tax mismatch fails', () {
    final lines = List.generate(12, (_) => <String, dynamic>{
      'quantity': 1, 'unit_price': .05, 'tax_rate': .0925,
    });
    expect(InvoiceTaxProposal.matchesStoredTax(lines, .0555), isTrue);
    expect(InvoiceTaxProposal.matchesStoredTax(lines, 5), isFalse);
  });

  test('existing copied local invoice tax saves atomically and survives reopening', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('copied-tax-');
    final file = File('${directory.path}/shop.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    final previousMode = LocalDocumentDetailCache.sqliteWritesEnabled;
    LocalDocumentDetailCache.sqliteWritesEnabled = true;
    addTearDown(() async {
      await db.close();
      LocalDocumentDetailCache.sqliteWritesEnabled = previousMode;
      await directory.delete(recursive: true);
    });
    final cache = LocalDocumentDetailCache(database: db);
    final service = OfflineDocumentDraftService(database: db, cache: cache);
    final id = await service.createQuickInvoice('shop',
      customerId: 'customer', customerName: 'Customer', initialLines: [
        {'name': 'Part', 'quantity': 1, 'unit_price': 100, 'tax_rate': .0925},
        {'name': 'Exempt', 'quantity': 1, 'unit_price': 50, 'tax_rate': 0},
      ]);
    final before = (await cache.load('shop', id))!;
    await service.updateTaxRate('shop', id, oldRate: .0925, newRate: .0975);
    await db.close();
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase(file));
    final reopenedCache = LocalDocumentDetailCache(database: db);
    final reopened = (await reopenedCache.load('shop', id))!;
    expect(reopened['tax_amount'], 9.75);
    expect(reopened['total_amount'], 159.75);
    expect(reopened['document_number'], before['document_number']);
    expect(reopened['paid_amount'], before['paid_amount']);
    expect((reopened['lines'] as List)[1]['tax_rate'], 0);
    expect(reopened['_local_tax_history'], hasLength(1));
    expect((await db.customSelect('SELECT * FROM sync_outbox').get()), hasLength(1));
    await db.customStatement('UPDATE sync_outbox SET attempt_count=1');
    await expectLater(OfflineDocumentDraftService(database: db, cache: reopenedCache)
      .updateTaxRate('shop', id, oldRate: .0975, newRate: .1), throwsStateError);
    expect((await reopenedCache.load('shop', id))!['tax_amount'], 9.75);
  });
  test('tax correction follows saved item edits without requiring sync', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = LocalDocumentDetailCache(database: db);
    await db.customStatement("INSERT INTO local_documents(id,business_id,kind,"
      "status,total,row_version,sync_state) VALUES('invoice','shop','invoice',"
      "'issued',109.25,1,'synced')");
    await cache.save('shop', 'invoice', {
      'id': 'invoice', 'kind': 'invoice', 'origin': 'native',
      'status': 'issued', 'row_version': 1, 'paid_amount': 0,
      'tax_amount': 9.25, 'net_amount': 100, 'total_amount': 109.25,
      'lines': [
        {'id': 'part', 'name': 'Part', 'line_kind': 'item',
          'quantity': 1, 'unit_price': 100, 'tax_rate': .0925},
      ],
    });
    final service = OfflineDocumentEditService(database: db, cache: cache);
    await service.updateLine('shop', 'invoice', 'part', name: 'Part',
      quantity: 2, unitPrice: 100, taxRate: .0925, lineKind: 'item');
    await service.updateTaxRate('shop', 'invoice', oldRate: .0925, newRate: .0975);
    final saved = (await cache.load('shop', 'invoice'))!;
    expect(saved['tax_amount'], 19.5);
    expect(saved['total_amount'], 219.5);
    await service.verifySavedLineCorrections('shop', 'invoice', saved);
    final queue = await db.customSelect('SELECT * FROM sync_outbox ORDER BY id').get();
    expect(queue, hasLength(2));
    expect(queue.last.data['payload_json'], contains('previous_tax_rate'));
  });

}
