import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

class LocalCatalogRepository {
  LocalCatalogRepository({BriskersLocalDatabase? database})
      : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;

  Future<bool> hasBootstrap(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT bootstrapped
      FROM local_sync_states
      WHERE business_id = ? AND scope = 'catalog'
      LIMIT 1
      ''',
      variables: [Variable<String>(businessId)],
    ).get();
    return rows.isNotEmpty && rows.first.read<int>('bootstrapped') == 1;
  }

  Future<List<Map<String, dynamic>>> items(
    String businessId, {
    String? search,
    bool includeInactive = true,
  }) async {
    final query = search?.trim().toLowerCase() ?? '';
    final variables = <Variable<Object>>[Variable<String>(businessId)];
    final where = <String>['business_id = ?'];
    if (!includeInactive) where.add('active = 1');
    if (query.isNotEmpty) {
      where.add('''
        (lower(name) LIKE ? OR lower(COALESCE(description, '')) LIKE ?
         OR lower(COALESCE(category, '')) LIKE ?)
      ''');
      final like = '%$query%';
      variables.addAll([
        Variable<String>(like),
        Variable<String>(like),
        Variable<String>(like),
      ]);
    }

    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_catalog_items
      WHERE ${where.join(' AND ')}
      ORDER BY
        CASE WHEN lower(name) = ? THEN 0
             WHEN lower(name) LIKE ? THEN 1
             ELSE 2 END,
        lower(name), id
      ''',
      variables: [
        ...variables,
        Variable<String>(query),
        Variable<String>('$query%'),
      ],
    ).get();

    return rows.map((row) => <String, dynamic>{
      'id': row.read<String>('id'),
      'name': row.read<String>('name'),
      'description': row.readNullable<String>('description'),
      'item_type': row.read<String>('item_type'),
      'selling_price': row.read<double>('selling_price'),
      'pricing_unit': row.readNullable<String>('pricing_unit'),
      'cost': row.read<double>('cost'),
      'taxable': row.read<int>('taxable') == 1,
      'category': row.readNullable<String>('category'),
      'barcode': row.readNullable<String>('barcode'),
      'active': row.read<int>('active') == 1,
      '_local_snapshot': true,
    }).toList();
  }

  Future<void> replaceFromServer(
    String businessId,
    List<Map<String, dynamic>> items,
  ) async {
    await _database.transaction(() async {
      await _database.customStatement(
        'DELETE FROM local_catalog_items WHERE business_id = ? AND sync_state = ?',
        [businessId, 'synced'],
      );
      for (final item in items) {
        await _database.customStatement(
          '''
          INSERT OR REPLACE INTO local_catalog_items
          (id, business_id, name, description, item_type, selling_price,
           pricing_unit, cost, taxable, category, barcode, active, sync_state)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
          ''',
          [
            item['id']?.toString(),
            businessId,
            item['name']?.toString() ?? '',
            item['description']?.toString(),
            item['item_type']?.toString() ?? 'non_inventory',
            num.tryParse(item['selling_price']?.toString() ?? '')?.toDouble() ?? 0,
            item['pricing_unit']?.toString(),
            num.tryParse(item['cost']?.toString() ?? '')?.toDouble() ?? 0,
            item['taxable'] == true ? 1 : 0,
            item['category']?.toString(),
            item['barcode']?.toString(),
            item['active'] == true ? 1 : 0,
          ],
        );
      }
      await _database.customStatement(
        '''
        INSERT OR REPLACE INTO local_sync_states
        (business_id, scope, last_pull_at, bootstrapped)
        VALUES (?, 'catalog', ?, 1)
        ''',
        [businessId, DateTime.now().toUtc()],
      );
    });
  }
}
