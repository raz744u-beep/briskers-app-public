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
    expect((lines.single as Map)['name'], 'Oil filter');
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
}
