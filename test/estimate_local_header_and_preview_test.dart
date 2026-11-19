import 'dart:convert';
import 'dart:io';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late BriskersLocalDatabase db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('estimate-header-preview');
    db = BriskersLocalDatabase(NativeDatabase(File('${directory.path}/shop.sqlite')));
    await LocalDocumentDetailCache.initialize(db);
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
    LocalDocumentDetailCache.sqliteWritesEnabled = false;
  });

  test('local estimate header keeps items and total through edit and restart', () async {
    final drafts = OfflineDocumentDraftService(database: db);
    final id = await drafts.createStandaloneEstimate('shop', customerId: 'customer',
      customerName: 'Terry', initialLines: [
        {'name': 'Headlight', 'line_kind': 'part', 'quantity': 1,
          'unit_price': 100, 'tax_rate': 0.0975},
      ]);
    final cache = LocalDocumentDetailCache(database: db);
    final before = (await cache.load('shop', id))!;
    await drafts.updatePendingEstimateDetails('shop', id,
      documentDate: DateTime(2026,11,19), customerId: 'customer', customerName: 'Terry',
      vehicleId: 'vehicle', vehicleLabel: '2015 Mercedes GLK350');
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(File('${directory.path}/shop.sqlite')));
    final saved = (await LocalDocumentDetailCache(database: db).load('shop', id))!;
    expect(saved['lines'], before['lines']);
    expect(saved['total_amount'], before['total_amount']);
    expect(saved['total_amount'], greaterThan(0));
    expect(saved['vehicle'], '2015 Mercedes GLK350');
    expect(saved['document_date'], '2026-11-19');
    final queue = await db.customSelect("SELECT payload_json FROM sync_outbox WHERE entity_type='document_draft_create'").getSingle();
    expect((jsonDecode(queue.read<String>('payload_json')) as Map)['vehicle_id'], 'vehicle');
    expect((await LocalDocumentDetailCache(database: db).estimatePreviews('shop', [id]))[id]!['lines'], saved['lines']);
  });

  test('preview batch rejects wrong identity, other business, invoices and deleted records', () async {
    final cache = LocalDocumentDetailCache(database: db);
    for (final id in ['valid','wrong-id','wrong-business','invoice','deleted']) {
      await LocalDocumentSqlStore.write(db, LocalDocumentDetailCache.key('shop',id),
        jsonEncode({'id': id == 'wrong-id' ? 'another' : id,
          'business_id': id == 'wrong-business' ? 'elsewhere' : 'shop',
          'kind': id == 'invoice' ? 'invoice' : 'estimate',
          'lines': [{'name':'Saved labor'}]}));
    }
    await db.customStatement('INSERT INTO local_document_detail_deleted VALUES(?)',
      [LocalDocumentDetailCache.key('shop','deleted')]);
    final previews = await cache.estimatePreviews('shop',
      ['valid','wrong-id','wrong-business','invoice','deleted','missing']);
    expect(previews.keys, ['valid']);
    expect((previews['valid']!['lines'] as List).single['name'], 'Saved labor');
  });

  test('attempted synchronization still prevents local estimate header rewrite', () async {
    final drafts = OfflineDocumentDraftService(database: db);
    final id = await drafts.createStandaloneEstimate('shop',customerId:'customer',customerName:'Terry');
    await db.customStatement('UPDATE sync_outbox SET attempt_count=1 WHERE entity_id=?', [id]);
    await expectLater(drafts.updatePendingEstimateDetails('shop',id,
      documentDate:DateTime(2026,11,19),customerId:'customer',customerName:'Terry'), throwsStateError);
  });
}
