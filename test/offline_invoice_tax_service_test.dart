import 'dart:convert';

import 'package:drift/drift.dart' show Variable;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_invoice_tax_service.dart';

Map<String, dynamic> _invoice({
  int version = 5,
  num taxRate = 0.0925,
  num pending = 174.80,
  bool discount = false,
}) {
  final tax = (160 * taxRate * 100).round() / 100;
  return {
    'id': 'barbara-6349',
    'kind': 'invoice',
    'origin': 'native',
    'legacy_read_only': false,
    'status': 'issued',
    'row_version': version,
    'net_amount': 160,
    'tax_amount': tax,
    'total_amount': 160 + tax,
    'paid_amount': 0,
    'pending_payment': pending,
    'payments': [
      {'id': 'existing-cash-17480', 'amount': pending,
        'payment_method': 'Cash', 'state': 'pending'},
    ],
    'lines': [
      {'id': 'oil-change', 'line_kind': 'item', 'quantity': 1,
        'unit_price': 160, 'tax_rate': taxRate,
        'net_amount': 160, 'tax_amount': tax},
      if (discount)
        {'id': 'discount', 'line_kind': 'discount', 'quantity': -1,
          'unit_price': 10, 'tax_rate': 0},
    ],
  };
}

class _FakeApi extends BriskersApi {
  Map<String, dynamic> server = _invoice();
  int taxCalls = 0;
  bool lostReply = false;
  bool patchDeployed = true;

  @override
  Future<String> invoiceTaxPatchLevel(String businessId) async {
    if (!patchDeployed) throw StateError('Patch missing');
    return 'generated_total_safe_20261018';
  }

  @override
  Future<Map<String, dynamic>> documentDetail(String businessId,
      String documentId) async =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(server)) as Map);

  @override
  Future<Map<String, dynamic>> updateInvoiceTaxRate(String businessId,
      String invoiceId, {
      required int expectedVersion, required num oldRate,
      required num newRate}) async {
    taxCalls++;
    if (server['row_version'] != expectedVersion) {
      throw StateError('Conflict');
    }
    final original = Map<String, dynamic>.from(server);
    final lines = List<dynamic>.from(original['lines'] as List);
    final updated = lines.map((raw) {
      final line = Map<String, dynamic>.from(raw as Map);
      if ((line['tax_rate'] as num) > 0) {
        line['tax_rate'] = newRate;
        line['tax_amount'] = (160 * newRate * 100).round() / 100;
      }
      return line;
    }).toList();
    server = {
      ...original,
      'row_version': expectedVersion + 1,
      'tax_amount': (160 * newRate * 100).round() / 100,
      'total_amount': 160 + (160 * newRate * 100).round() / 100,
      'lines': updated,
    };
    if (lostReply) throw StateError('Server accepted tax but reply was lost');
    return {'invoice_id': invoiceId, 'changed_lines': 1,
      'total_amount': server['total_amount']};
  }
}

Future<BriskersLocalDatabase> _dbWithInvoice(
  LocalDocumentDetailCache cache, BriskersLocalDatabase db,
  Map<String, dynamic> detail,
) async {
  await cache.save('shop', 'barbara-6349', detail);
  await db.customStatement(
    "INSERT INTO local_documents(id,business_id,job_id,customer_id,"
    "kind,status,display_status_code,converted,total,row_version,sync_state) "
    "VALUES ('barbara-6349','shop','job21','barbara','invoice',"
    "'issued','pending_close',0,?,?,'synced')",
    [detail['total_amount'], detail['row_version']],
  );
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Force Offline tax save changes local total, survives restart, '
      'does not alter existing pending payment', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final api = _FakeApi();
    await _dbWithInvoice(cache, db, api.server);
    final service = OfflineInvoiceTaxService(api: api,
      database: db, cache: cache, canSend: () => false);

    final saved = await service.saveOffline('shop', 'barbara-6349',
      expectedVersion: 5, oldRate: 0.0925, newRate: 0.0975);
    expect((saved['tax_amount'] as num).toDouble(), closeTo(15.60, .001));
    expect((saved['total_amount'] as num).toDouble(), closeTo(175.60, .001));
    expect(saved['_local_pending_tax'], true);
    expect(saved['payments'], api.server['payments']);
    expect(saved['pending_payment'], 174.80);
    expect(saved['paid_amount'], 0);
    expect(api.taxCalls, 0);

    final queued = await db.customSelect(
      "SELECT id,state,operation FROM sync_outbox "
      "WHERE business_id='shop' AND entity_type='invoice_tax_edit'").get();
    expect(queued, hasLength(1));
    expect(queued.single.read<String>('state'), 'pending');
    final index = await db.customSelect(
      "SELECT total,sync_state FROM local_documents WHERE id='barbara-6349'"
    ).getSingle();
    expect(index.read<double>('total'), closeTo(175.60, .001));
    expect(index.read<String>('sync_state'), 'pending');

    final restarted = OfflineInvoiceTaxService(api: api,
      database: db, cache: cache, canSend: () => false);
    final restored = await restarted.projectPending(
        'shop', 'barbara-6349', (await cache.load('shop', 'barbara-6349'))!);
    expect(restored['total_amount'], 175.6);
    expect(restored['_local_pending_tax'], true);
    await restarted.flush('shop');
    expect(api.taxCalls, 0);
    await restarted.saveOffline('shop', 'barbara-6349',
      expectedVersion: 5, oldRate: 0.0925, newRate: 0.0975);
    expect((await db.customSelect(
      "SELECT id FROM sync_outbox WHERE entity_type='invoice_tax_edit'").get()).length, 1);
    await expectLater(
      restarted.saveOffline('shop', 'barbara-6349',
        expectedVersion: 5, oldRate: 0.0925, newRate: 0.099),
      throwsStateError,
    );
    await db.close();
  });

  test('verified replay edits server invoice once, leaves pending payment alone',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final api = _FakeApi();
    await _dbWithInvoice(cache, db, api.server);
    final service = OfflineInvoiceTaxService(
        api: api, cache: cache, database: db, canSend: () => true);
    await service.saveOffline('shop', 'barbara-6349',
      expectedVersion: 5, oldRate: 0.0925, newRate: 0.0975);
    await service.flush('shop');
    expect(api.taxCalls, 1);
    expect(api.server['total_amount'], 175.6);
    expect(api.server['pending_payment'], 174.8);
    expect((api.server['payments'] as List).single['id'], 'existing-cash-17480');
    expect((await db.customSelect(
      "SELECT id FROM sync_outbox WHERE entity_type='invoice_tax_edit'"
    ).get()), isEmpty);
    expect((await cache.load('shop', 'barbara-6349'))!['_local_pending_tax'], isNull);
    await service.flush('shop');
    expect(api.taxCalls, 1);
    await db.close();
  });

  test('Auto and manual tax sync share one replay and do not double-post',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final api = _FakeApi();
    await _dbWithInvoice(cache, db, api.server);
    final auto = OfflineInvoiceTaxService(
        api: api, cache: cache, database: db, canSend: () => true);
    final manual = OfflineInvoiceTaxService(
        api: api, cache: cache, database: db, canSend: () => true);
    await auto.saveOffline('shop', 'barbara-6349',
        expectedVersion: 5, oldRate: 0.0925, newRate: 0.0975);
    await Future.wait([auto.flush('shop'), manual.flush('shop')]);
    expect(api.taxCalls, 1);
    expect(api.server['total_amount'], 175.6);
    expect(await db.customSelect(
      "SELECT id FROM sync_outbox WHERE entity_type='invoice_tax_edit'"
    ).get(), isEmpty);
    await db.close();
  });

  test('stale server version becomes conflict without any tax RPC',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final api = _FakeApi();
    await _dbWithInvoice(cache, db, api.server);
    final service = OfflineInvoiceTaxService(
        api: api, cache: cache, database: db, canSend: () => true);
    await service.saveOffline('shop', 'barbara-6349',
      expectedVersion: 5, oldRate: 0.0925, newRate: 0.0975);
    api.server['row_version'] = 6;
    await service.flush('shop');
    expect(api.taxCalls, 0);
    final row = await db.customSelect(
      "SELECT state FROM sync_outbox WHERE entity_type='invoice_tax_edit'"
    ).getSingle();
    expect(row.read<String>('state'), 'conflict');
    await db.close();
  });

  test('lost response remains inflight; restart never automatically resends',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final api = _FakeApi()..lostReply = true;
    await _dbWithInvoice(cache, db, api.server);
    final service = OfflineInvoiceTaxService(
        api: api, cache: cache, database: db, canSend: () => true);
    await service.saveOffline('shop', 'barbara-6349',
      expectedVersion: 5, oldRate: 0.0925, newRate: 0.0975);
    await expectLater(service.flush('shop'), throwsStateError);
    expect(api.taxCalls, 1);
    expect(api.server['total_amount'], 175.6);
    final row = await db.customSelect(
      "SELECT state,attempt_count FROM sync_outbox "
      "WHERE entity_type='invoice_tax_edit'").getSingle();
    expect(row.read<String>('state'), 'inflight');
    expect(row.read<int>('attempt_count'), 1);
    final restarted = OfflineInvoiceTaxService(
        api: api, cache: cache, database: db, canSend: () => true);
    await restarted.flush('shop');
    expect(api.taxCalls, 1);
    await db.close();
  });

  test('428C9 rejected tax can be requeued only after server attestation '
      'and original-version confirmation', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final api = _FakeApi();
    await _dbWithInvoice(cache, db, api.server);
    final service = OfflineInvoiceTaxService(
      api: api, cache: cache, database: db, canSend: () => true);
    await service.saveOffline('shop', 'barbara-6349',
      expectedVersion: 5, oldRate: 0.0925, newRate: 0.0975);
    final id = (await db.customSelect(
      "SELECT id FROM sync_outbox WHERE entity_type='invoice_tax_edit'"
    ).getSingle()).read<int>('id');
    await db.customStatement(
      "UPDATE sync_outbox SET state='inflight',attempt_count=1,"
      "last_error=? WHERE id=?",
      ['Tax correction outcome uncertain: PostgrestException('
       'column "total_amount" can only be updated to DEFAULT, '
       'code: 428C9, details: generated column)', id],
    );

    // A missing migration means NO local requeue and NO server write.
    api.patchDeployed = false;
    await expectLater(service.requeueVerifiedGeneratedTotalRejection(
      'shop', id), throwsStateError);
    var state = await db.customSelect(
      "SELECT state FROM sync_outbox WHERE id=?", variables: [Variable<int>(id)]
    ).getSingle();
    expect(state.read<String>('state'), 'inflight');
    api.patchDeployed = true;
    await service.requeueVerifiedGeneratedTotalRejection('shop', id);
    state = await db.customSelect(
      "SELECT state,attempt_count FROM sync_outbox WHERE id=?",
      variables: [Variable<int>(id)]
    ).getSingle();
    expect(state.read<String>('state'), 'pending');
    expect(state.read<int>('attempt_count'), 1);
    expect(api.taxCalls, 0);
    expect(api.server['total_amount'], 174.8);
    await expectLater(service.requeueVerifiedGeneratedTotalRejection(
      'shop', id), throwsStateError);
    await db.close();
  });

  test('rejected tax recovery keeps fence if server changed', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final api = _FakeApi();
    await _dbWithInvoice(cache, db, api.server);
    final service = OfflineInvoiceTaxService(
      api: api, cache: cache, database: db, canSend: () => true);
    await service.saveOffline('shop', 'barbara-6349',
      expectedVersion: 5, oldRate: 0.0925, newRate: 0.0975);
    final id = (await db.customSelect(
      "SELECT id FROM sync_outbox WHERE entity_type='invoice_tax_edit'"
    ).getSingle()).read<int>('id');
    await db.customStatement(
      "UPDATE sync_outbox SET state='inflight',attempt_count=1,"
      "last_error=? WHERE id=?",
      ['column "total_amount", code: 428C9; generated column',id]);
    api.server['row_version'] = 6;
    await expectLater(service.requeueVerifiedGeneratedTotalRejection(
      'shop', id), throwsStateError);
    expect((await db.customSelect(
      "SELECT state FROM sync_outbox WHERE id=?",
      variables:[Variable<int>(id)]).getSingle()).read<String>('state'),
      'inflight');
    expect(api.taxCalls, 0);
    await db.close();
  });

  test('unverified timeout cannot be released as generated-total rejection',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final api = _FakeApi();
    await _dbWithInvoice(cache, db, api.server);
    final service = OfflineInvoiceTaxService(
      api: api, cache: cache, database: db, canSend: () => true);
    await service.saveOffline('shop', 'barbara-6349',
      expectedVersion: 5, oldRate: 0.0925, newRate: 0.0975);
    final id = (await db.customSelect(
      "SELECT id FROM sync_outbox WHERE entity_type='invoice_tax_edit'"
    ).getSingle()).read<int>('id');
    await db.customStatement(
      "UPDATE sync_outbox SET state='inflight',attempt_count=1,"
      "last_error='Remote request timeout' WHERE id=?", [id]);
    await expectLater(service.requeueVerifiedGeneratedTotalRejection(
      'shop', id), throwsStateError);
    expect(api.taxCalls, 0);
    await db.close();
  });

  test('posted or overpaid invoice fails closed without queue changes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final api = _FakeApi();
    final paid = _invoice(pending: 200);
    await _dbWithInvoice(cache, db, paid);
    final service = OfflineInvoiceTaxService(
        api: api, cache: cache, database: db, canSend: () => false);
    await expectLater(
      service.saveOffline('shop', 'barbara-6349',
        expectedVersion: 5, oldRate: 0.0925, newRate: 0.0975),
      throwsStateError,
    );
    expect((await db.customSelect(
      "SELECT id FROM sync_outbox WHERE entity_type='invoice_tax_edit'").get()),
      isEmpty);
    await db.close();
  });
}
