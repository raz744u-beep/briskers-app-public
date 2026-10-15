import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('copied invoice has all lines and notes before first outbox replay',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final drafts = OfflineDocumentDraftService(
      database: db, cache: cache,
      documents: LocalDocumentRepository(database: db),
    );
    final id = await drafts.createQuickInvoice(
      'shop', customerId: 'customer-a', customerName: 'Customer A',
      vehicleId: 'car-a', vehicleLabel: 'BMW 540i',
      initialLines: [
        {'id': 'old-line', 'name': 'Water pump',
          'line_kind': 'labor', 'quantity': 2, 'unit_price': 125,
          'tax_rate': 0, 'description': 'Replace water pump'},
      ],
      initialMemo: 'Check thermostat',
    );
    final saved = (await cache.load('shop', id))!;
    expect(saved['job_id'], startsWith('local-job-'));
    expect(saved['customer_id'], 'customer-a');
    expect(saved['total_amount'], 250);
    expect(saved['memo'], 'Check thermostat');
    final lines = List<Map<String, dynamic>>.from(saved['lines'] as List);
    expect(lines, hasLength(1));
    expect(lines.single['id'], isNot('old-line'));
    expect(lines.single['description'], 'Replace water pump');
    expect((await db.customSelect(
      'SELECT COUNT(*) AS n FROM sync_outbox WHERE business_id=? '
      'AND entity_id=?', variables: [
        const Variable<String>('shop'), Variable<String>(id),
      ],
    ).getSingle()).read<int>('n'), 1);
    await db.close();
  });

  test('copied estimate is standalone with prefilled content', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalDocumentDetailCache(database: db);
    final drafts = OfflineDocumentDraftService(
      database: db, cache: cache,
      documents: LocalDocumentRepository(database: db),
    );
    final id = await drafts.createStandaloneEstimate(
      'shop', customerId: 'customer-b', customerName: 'Customer B',
      initialLines: [
        {'name': 'Diagnostic', 'line_kind': 'labor',
          'quantity': 1, 'unit_price': 95, 'tax_rate': 0},
      ],
      initialMemo: 'Customer-reported issue',
    );
    final saved = (await cache.load('shop', id))!;
    expect(saved['job_id'], isNull);
    expect(saved['total_amount'], 95);
    expect(saved['memo'], 'Customer-reported issue');
    expect((await db.customSelect(
      'SELECT COUNT(*) AS n FROM local_jobs WHERE business_id=?',
      variables: [const Variable<String>('shop')],
    ).getSingle()).read<int>('n'), 0);
    await db.close();
  });
}
