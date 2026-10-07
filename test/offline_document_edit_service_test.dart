import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_document_edit_service.dart';

class _FakeApi extends BriskersApi {
  _FakeApi();

  var addCalls = 0;
  final Map<String, dynamic> _detail = {
    'id': 'estimate-1',
    'kind': 'estimate',
    'status': 'draft',
    'row_version': 1,
    'total_amount': 0,
    'lines': <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> documentDetail(
    String businessId,
    String documentId,
  ) async {
    return {
      ..._detail,
      'lines': List<dynamic>.from(_detail['lines'] as List),
    };
  }

  @override
  Future<void> addDocumentLine(
    String businessId,
    String documentId, {
    required int expectedVersion,
    required String name,
    required num quantity,
    required num unitPrice,
    num taxRate = 0,
    String? description,
    String? itemId,
    String lineKind = 'item',
  }) async {
    addCalls++;
    final lines = List<Map<String, dynamic>>.from(
      (_detail['lines'] as List).map(
        (raw) => Map<String, dynamic>.from(raw as Map),
      ),
    );
    lines.add({
      'id': 'server-line-$addCalls',
      'name': name,
      'description': description,
      'item_id': itemId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'tax_rate': taxRate,
      'line_kind': lineKind,
      'position': lines.length + 1,
    });
    _detail['lines'] = lines;
    _detail['row_version'] = expectedVersion + 1;
    final net = quantity * unitPrice;
    final tax = net * taxRate;
    _detail['total_amount'] = net + tax;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cached server estimate adds item locally before any network call',
      () async {
    SharedPreferences.setMockInitialValues({});

    final database = BriskersLocalDatabase(NativeDatabase.memory());
    const cache = LocalDocumentDetailCache();
    final api = _FakeApi();
    final service = OfflineDocumentEditService(
      api: api,
      cache: cache,
      database: database,
    );

    await cache.save('business-1', 'estimate-1', {
      'id': 'estimate-1',
      'kind': 'estimate',
      'status': 'draft',
      'row_version': 1,
      'total_amount': 0,
      'net_amount': 0,
      'tax_amount': 0,
      'lines': <Map<String, dynamic>>[],
    });

    await database.customStatement(
      '''
      INSERT INTO local_documents (
        id, business_id, job_id, customer_id, kind, document_number,
        status, display_status_code, closed_at, converted, total,
        created_at, server_updated_at, row_version, sync_state
      ) VALUES (?, ?, ?, ?, 'estimate', NULL, 'draft', 'draft',
                NULL, 0, 0, ?, ?, 1, 'synced')
      ''',
      [
        'estimate-1',
        'business-1',
        'job-1',
        'customer-1',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );

    await service.addLine(
      'business-1',
      'estimate-1',
      name: 'Oil filter',
      itemId: 'item-1',
      quantity: 1,
      unitPrice: 10,
      taxRate: 0.09,
      lineKind: 'item',
    );

    expect(api.addCalls, 0);

    final cached = await cache.load('business-1', 'estimate-1');
    final lines = List<dynamic>.from(cached!['lines'] as List);
    expect(lines, hasLength(1));
    final localLine = Map<String, dynamic>.from(lines.single as Map);
    expect(localLine['name'], 'Oil filter');
    expect((localLine['unit_price'] as num).toDouble(), closeTo(10.00, 0.001));
    expect((localLine['net_amount'] as num).toDouble(), closeTo(10.00, 0.001));
    expect((localLine['tax_amount'] as num).toDouble(), closeTo(0.90, 0.001));
    expect((cached['net_amount'] as num).toDouble(), closeTo(10.00, 0.001));
    expect((cached['tax_amount'] as num).toDouble(), closeTo(0.90, 0.001));
    expect((cached['total_amount'] as num).toDouble(), closeTo(10.90, 0.001));

    final outbox = await database.customSelect(
      '''
      SELECT entity_type, operation, state
      FROM sync_outbox
      WHERE business_id = ?
      ''',
      variables: [const Variable<String>('business-1')],
    ).get();

    expect(outbox, hasLength(1));
    expect(outbox.single.read<String>('entity_type'), 'document_edit');
    expect(outbox.single.read<String>('operation'), 'add_line');
    expect(outbox.single.read<String>('state'), 'pending');

    await service.flush('business-1');

    expect(api.addCalls, 1);

    final after = await database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM sync_outbox
      WHERE business_id = ?
      ''',
      variables: [const Variable<String>('business-1')],
    ).getSingle();
    expect(after.read<int>('count'), 0);

    final synced = await cache.load('business-1', 'estimate-1');
    final syncedLines = List<dynamic>.from(synced!['lines'] as List);
    expect(syncedLines, hasLength(1));
    expect((syncedLines.single as Map)['id'], 'server-line-1');

    await database.close();
  });

  test('pending taxable catalog line is repaired before reconnect sync',
      () async {
    SharedPreferences.setMockInitialValues({});

    final database = BriskersLocalDatabase(NativeDatabase.memory());
    const cache = LocalDocumentDetailCache();
    final service = OfflineDocumentEditService(
      api: _FakeApi(),
      cache: cache,
      database: database,
    );

    await database.customStatement(
      '''
      INSERT INTO local_catalog_items (
        id, business_id, name, description, item_type, selling_price,
        pricing_unit, cost, taxable, category, barcode, active, sync_state
      ) VALUES (?, ?, ?, NULL, 'non_inventory', 768.23, NULL, 0, 1,
                'Drivetrain', NULL, 1, 'synced')
      ''',
      ['item-pan', 'business-1', 'Transmission Pan'],
    );

    await cache.save('business-1', 'estimate-tax', {
      'id': 'estimate-tax',
      'kind': 'estimate',
      'status': 'draft',
      'row_version': 1,
      'net_amount': 768.23,
      'tax_amount': 0,
      'total_amount': 768.23,
      'lines': <Map<String, dynamic>>[
        {
          'id': 'local-doc-line-tax',
          'name': 'Transmission Pan',
          'item_id': 'item-pan',
          'quantity': 1,
          'unit_price': 768.23,
          'tax_rate': 0,
          'net_amount': 768.23,
          'tax_amount': 0,
          'line_kind': 'item',
          'position': 1,
          '_local_pending': true,
        },
      ],
    });

    await database.customStatement(
      '''
      INSERT INTO local_documents (
        id, business_id, job_id, customer_id, kind, status,
        display_status_code, converted, total, row_version, sync_state
      ) VALUES (?, ?, ?, ?, 'estimate', 'draft', 'draft', 0, 768.23, 1, 'pending')
      ''',
      ['estimate-tax', 'business-1', 'job-1', 'customer-1'],
    );

    await database.customStatement(
      '''
      INSERT INTO sync_outbox (
        business_id, entity_type, entity_id, operation, payload_json,
        state, attempt_count, created_at
      ) VALUES (?, 'document_edit', ?, 'add_line', ?, 'pending', 0, ?)
      ''',
      [
        'business-1',
        'estimate-tax',
        '{"local_line_id":"local-doc-line-tax","name":"Transmission Pan","item_id":"item-pan","quantity":1,"unit_price":768.23,"tax_rate":0,"line_kind":"item"}',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );

    final repaired = await service.repairPendingCatalogTaxes(
      'business-1',
      0.0975,
    );
    expect(repaired, 1);

    final cached = await cache.load('business-1', 'estimate-tax');
    final lines = List<dynamic>.from(cached!['lines'] as List);
    final line = Map<String, dynamic>.from(lines.single as Map);
    expect((line['tax_rate'] as num).toDouble(), closeTo(0.0975, 0.000001));
    expect((line['tax_amount'] as num).toDouble(), closeTo(74.902425, 0.0001));
    expect((cached['tax_amount'] as num).toDouble(), closeTo(74.902425, 0.0001));
    expect((cached['total_amount'] as num).toDouble(), closeTo(843.132425, 0.0001));

    final outbox = await database.customSelect(
      '''
      SELECT payload_json
      FROM sync_outbox
      WHERE business_id = ? AND entity_id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        const Variable<String>('estimate-tax'),
      ],
    ).getSingle();
    expect(outbox.read<String>('payload_json'), contains('"tax_rate":0.0975'));

    await database.close();
  });

}
