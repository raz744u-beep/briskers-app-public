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
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_catalog_items
      WHERE business_id = ?
        ${includeInactive ? '' : 'AND active = 1'}
      ORDER BY lower(name), id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    final mapped = rows.map((row) => <String, dynamic>{
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

    if (query.isEmpty) return mapped;

    final ranked = <MapEntry<int, Map<String, dynamic>>>[];
    for (final item in mapped) {
      final name = (item['name']?.toString() ?? '').toLowerCase();
      final description =
          (item['description']?.toString() ?? '').toLowerCase();
      final category = (item['category']?.toString() ?? '').toLowerCase();
      final score = _matchScore(query, name, description, category);
      if (score != null) ranked.add(MapEntry(score, item));
    }
    ranked.sort((a, b) {
      final byScore = a.key.compareTo(b.key);
      if (byScore != 0) return byScore;
      return (a.value['name']?.toString() ?? '')
          .toLowerCase()
          .compareTo((b.value['name']?.toString() ?? '').toLowerCase());
    });
    return ranked.map((entry) => entry.value).toList();
  }

  int? _matchScore(
    String query,
    String name,
    String description,
    String category,
  ) {
    if (name == query) return 0;
    if (name.startsWith(query)) return 10;
    if (name.contains(query)) return 20;
    if (description.contains(query)) return 30;
    if (category.contains(query)) return 40;

    // Fuzzy matching is intentionally conservative: it is a suggestion layer,
    // never an automatic substitution. This catches handwriting/typing cases
    // such as "insulator" -> "isolator" without hiding exact matches.
    final queryWords = _words(query);
    final nameWords = _words(name);
    var best = 999;
    for (final q in queryWords) {
      for (final n in nameWords) {
        final distance = _levenshtein(q, n);
        final allowed = q.length >= 8 ? 3 : (q.length >= 5 ? 2 : 1);
        if (distance <= allowed) {
          final normalized = 50 + distance * 5 + (n.length - q.length).abs();
          if (normalized < best) best = normalized;
        }
      }
    }
    return best == 999 ? null : best;
  }

  List<String> _words(String value) => value
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.isNotEmpty)
      .toList();

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }

  Future<void> upsertLocal(
    String businessId, {
    required String id,
    required String name,
    String? description,
    required String itemType,
    required num sellingPrice,
    String? pricingUnit,
    required num cost,
    required bool taxable,
    String? category,
    String? barcode,
    required bool active,
    String syncState = 'pending',
  }) async {
    await _database.customStatement(
      '''
      INSERT INTO local_catalog_items (
        id, business_id, name, description, item_type, selling_price,
        pricing_unit, cost, taxable, category, barcode, active, sync_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        business_id=excluded.business_id,
        name=excluded.name,
        description=excluded.description,
        item_type=excluded.item_type,
        selling_price=excluded.selling_price,
        pricing_unit=excluded.pricing_unit,
        cost=excluded.cost,
        taxable=excluded.taxable,
        category=excluded.category,
        barcode=excluded.barcode,
        active=excluded.active,
        sync_state=excluded.sync_state
      ''',
      [
        id, businessId, name, description, itemType, sellingPrice.toDouble(),
        pricingUnit, cost.toDouble(), taxable ? 1 : 0, category, barcode,
        active ? 1 : 0, syncState,
      ],
    );
  }

  Future<void> markSynced(String businessId, String id) async {
    await _database.customStatement(
      '''
      UPDATE local_catalog_items
      SET sync_state = 'synced'
      WHERE business_id = ? AND id = ?
      ''',
      [businessId, id],
    );
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
          INSERT INTO local_catalog_items
          (id, business_id, name, description, item_type, selling_price,
           pricing_unit, cost, taxable, category, barcode, active, sync_state)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
          ON CONFLICT(id) DO UPDATE SET
            business_id=excluded.business_id,
            name=excluded.name,
            description=excluded.description,
            item_type=excluded.item_type,
            selling_price=excluded.selling_price,
            pricing_unit=excluded.pricing_unit,
            cost=excluded.cost,
            taxable=excluded.taxable,
            category=excluded.category,
            barcode=excluded.barcode,
            active=excluded.active,
            sync_state='synced'
          WHERE local_catalog_items.sync_state = 'synced'
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
        [businessId, DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000],
      );
    });
  }
}
