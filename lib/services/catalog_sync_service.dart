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
