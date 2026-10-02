import 'briskers_api.dart';
import 'local_document_repository.dart';

class DocumentIndexSyncService {
  DocumentIndexSyncService({
    BriskersApi api = const BriskersApi(),
    LocalDocumentRepository? repository,
  })  : _api = api,
        _repository = repository ?? LocalDocumentRepository();

  final BriskersApi _api;
  final LocalDocumentRepository _repository;

  Future<void> pull(String businessId) async {
    for (final kind in const ['estimate', 'invoice']) {
      final rows = await _api.documents(businessId, kind: kind);
      final normalized = rows.map((row) {
        final copy = Map<String, dynamic>.from(row);
        copy['kind'] ??= kind;
        return copy;
      }).toList();
      await _repository.replaceFromServer(
        businessId,
        normalized,
        kind: kind,
      );
    }
  }

  Future<void> refreshBestEffort(String businessId) async {
    try {
      await pull(businessId);
    } catch (_) {
      // Keep the existing local index available offline.
    }
  }
}
