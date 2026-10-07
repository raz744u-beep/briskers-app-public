import 'dart:async';


import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_document_repository.dart';
import 'local_document_detail_cache.dart';

class DocumentIndexSyncService {
  DocumentIndexSyncService({
    BriskersApi api = const BriskersApi(),
    LocalDocumentRepository? repository,
  })  : _api = api,
        _repository = repository ?? LocalDocumentRepository();

  static const _scope = 'documents';
  static final StreamController<String> _syncEvents =
      StreamController<String>.broadcast();

  static Stream<String> get syncEvents => _syncEvents.stream;
  final BriskersApi _api;
  final LocalDocumentRepository _repository;
  final LocalDocumentDetailCache _detailCache = const LocalDocumentDetailCache();

  Future<void> pull(String businessId) async {
    final results = await Future.wait<dynamic>([
      _api.documents(businessId, kind: 'estimate'),
      _api.documents(businessId, kind: 'invoice'),
    ]);

    final estimates =
        List<Map<String, dynamic>>.from(results[0] as List);
    final invoices =
        List<Map<String, dynamic>>.from(results[1] as List);
    final all = <Map<String, dynamic>>[
      ...estimates,
      ...invoices,
    ];

    await _repository.replaceFromServer(
      businessId,
      estimates,
      kind: 'estimate',
    );
    await _repository.replaceFromServer(
      businessId,
      invoices,
      kind: 'invoice',
    );
    await _prefetchOpenDocumentDetails(businessId, all);

    await localDatabase.customStatement(
      '''
      INSERT INTO local_sync_states (
        business_id, scope, last_server_cursor, last_pull_at,
        last_error, bootstrapped
      ) VALUES (?, ?, NULL, ?, NULL, 1)
      ON CONFLICT(business_id, scope) DO UPDATE SET
        last_server_cursor=NULL,
        last_pull_at=excluded.last_pull_at,
        last_error=NULL,
        bootstrapped=1
      ''',
      [
        businessId,
        _scope,
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );

    _syncEvents.add(businessId);
  }

  Future<void> _prefetchOpenDocumentDetails(
    String businessId,
    List<Map<String, dynamic>> documents,
  ) async {
    for (final document in documents) {
      final id = document['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      final kind = document['kind']?.toString() ?? '';
      final status = document['status']?.toString().toLowerCase() ?? '';
      final closed = document['closed_at'] != null;
      final converted = document['converted'] == true;
      final activeEstimate = kind == 'estimate' &&
          !converted &&
          !<String>{'accepted', 'declined', 'expired', 'void'}.contains(status);
      final activeInvoice =
          kind == 'invoice' && !closed && status != 'void';
      if (!activeEstimate && !activeInvoice) continue;

      try {
        final detail = await _api.documentDetail(businessId, id);
        await _detailCache.save(businessId, id, detail);
      } catch (_) {
        // Keep the previous local detail snapshot if one already exists.
      }
    }
  }

  Future<void> refreshBestEffort(String businessId) async {
    try {
      await pull(businessId);
    } catch (error) {
      await localDatabase.customStatement(
        '''
        INSERT INTO local_sync_states (
          business_id, scope, last_error, bootstrapped
        ) VALUES (?, ?, ?, 0)
        ON CONFLICT(business_id, scope) DO UPDATE SET
          last_error=excluded.last_error
        ''',
        [businessId, _scope, error.toString()],
      );
    }
  }
}
