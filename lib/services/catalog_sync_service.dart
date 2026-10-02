import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_catalog_repository.dart';

class CatalogSyncService {
  CatalogSyncService({
    BriskersApi api = const BriskersApi(),
    LocalCatalogRepository? repository,
  })  : _api = api,
        _repository = repository ?? LocalCatalogRepository();

  final BriskersApi _api;
  final LocalCatalogRepository _repository;

  Future<void> queueSave(
    String businessId, {
    String? itemId,
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
  }) async {
    final id = itemId ?? 'local-catalog-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final payload = <String, dynamic>{
      'item_id': itemId,
      'name': name,
      'description': description,
      'item_type': itemType,
      'selling_price': sellingPrice,
      'pricing_unit': pricingUnit,
      'cost': cost,
      'taxable': taxable,
      'category': category,
      'barcode': barcode,
      'active': active,
    };
    await localDatabase.transaction(() async {
      await _repository.upsertLocal(
        businessId,
        id: id,
        name: name,
        description: description,
        itemType: itemType,
        sellingPrice: sellingPrice,
        pricingUnit: pricingUnit,
        cost: cost,
        taxable: taxable,
        category: category,
        barcode: barcode,
        active: active,
      );
      await localDatabase.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation, payload_json,
          state, attempt_count, created_at
        ) VALUES (?, 'catalog_item', ?, 'save', ?, 'pending', 0, ?)
        ''',
        [businessId, id, jsonEncode(payload),
         DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000],
      );
    });
  }

  Future<void> flush(String businessId) async {
    final rows = await localDatabase.customSelect(
      '''
      SELECT * FROM sync_outbox
      WHERE business_id = ? AND entity_type = 'catalog_item'
        AND state = 'pending'
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    for (final row in rows) {
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );
        final serverId = await _api.saveCatalogItem(
          businessId,
          itemId: payload['item_id']?.toString(),
          name: payload['name']?.toString() ?? '',
          description: payload['description']?.toString(),
          itemType: payload['item_type']?.toString() ?? 'non_inventory',
          sellingPrice: num.tryParse(payload['selling_price']?.toString() ?? '') ?? 0,
          pricingUnit: payload['pricing_unit']?.toString(),
          cost: num.tryParse(payload['cost']?.toString() ?? '') ?? 0,
          taxable: payload['taxable'] == true,
          category: payload['category']?.toString(),
          barcode: payload['barcode']?.toString(),
          active: payload['active'] == true,
        );
        await localDatabase.transaction(() async {
          await localDatabase.customStatement(
            'DELETE FROM sync_outbox WHERE id = ?',
            [row.read<int>('id')],
          );
          final localId = row.read<String>('entity_id');
          if (localId != serverId) {
            await localDatabase.customStatement(
              'DELETE FROM local_catalog_items WHERE business_id = ? AND id = ?',
              [businessId, localId],
            );
          } else {
            await _repository.markSynced(businessId, localId);
          }
        });
      } catch (error) {
        await localDatabase.customStatement(
          '''
          UPDATE sync_outbox
          SET attempt_count = attempt_count + 1,
              last_attempt_at = ?, last_error = ?
          WHERE id = ?
          ''',
          [DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
           error.toString(), row.read<int>('id')],
        );
        break;
      }
    }
    try {
      await pull(businessId);
    } catch (_) {
      // Keep the local catalog usable if refresh cannot complete.
    }
  }

  /// Refreshes the device catalog from the server. Existing local data remains
  /// usable when the network is unavailable.
  Future<void> pull(String businessId) async {
    final items = await _api.catalogItemsSettings(
      businessId,
      includeInactive: true,
    );
    await _repository.replaceFromServer(businessId, items);
  }

  /// Ensures a first local snapshot when possible. Failure is deliberately
  /// non-fatal so a previously cached catalog remains available offline.
  Future<void> ensureBootstrap(String businessId) async {
    if (await _repository.hasBootstrap(businessId)) return;
    try {
      await pull(businessId);
    } catch (_) {
      // The caller can continue with whatever local snapshot is available.
    }
  }
}
