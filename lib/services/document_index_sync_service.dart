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
    // A list index alone is not an offline document snapshot.
    // Download details for every synced invoice and estimate, including closed
    // historical documents. Cached details make retries resumable.
    await localDatabase.customStatement(
      "UPDATE local_sync_states SET bootstrapped = 0 "
      "WHERE business_id = ? AND scope = ?",
      [businessId, _scope],
    );
    await _prefetchAllDocumentDetails(businessId, all);

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

  Future<void> _prefetchAllDocumentDetails(
    String businessId,
    List<Map<String, dynamic>> documents,
  ) async {
    final missing = <Map<String, dynamic>>[];
    for (final document in documents) {
      final id = document['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final cached = await _detailCache.load(businessId, id);
      final expectedKind = document['kind']?.toString() ?? '';
      final cachedValid = cached != null &&
          cached['id']?.toString() == id &&
          cached['kind']?.toString() == expectedKind &&
          cached['lines'] is List;
      // Never overwrite pending offline edits. Otherwise refresh server data
      // when its version changed (not on every index synchronization).
      final hasLocalEdits =
          cached?['sync_state']?.toString() == 'pending';
      final serverVersion = document['row_version']?.toString();
      final cachedVersion = cached?['row_version']?.toString();
      final current = cachedValid &&
          (hasLocalEdits ||
              serverVersion == null ||
              serverVersion == cachedVersion);
      if (!current) missing.add(document);
    }
    if (missing.isEmpty) return;

    // Bound concurrent requests to avoid swamping Supabase and keep failures
    // isolated; successful details stay cached across interrupted syncs.
    var cursor = 0;
    var failures = 0;
    final examples = <String>[];

    Future<void> worker() async {
      while (cursor < missing.length) {
        final document = missing[cursor++];
        final id = document['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        try {
          final detail = await _api.documentDetail(businessId, id);
          if (detail['id']?.toString() != id ||
              detail['lines'] is! List) {
            throw StateError('Invalid document detail response');
          }
          await _detailCache.save(businessId, id, detail);
        } catch (_) {
          failures++;
          if (examples.length < 5) {
            examples.add(document['document_number']?.toString() ?? id);
          }
        }
      }
    }

    const concurrency = 4;
    await Future.wait(
      List.generate(
        missing.length < concurrency ? missing.length : concurrency,
        (_) => worker(),
      ),
    );
    if (failures != 0) {
      throw StateError(
        'Offline document details incomplete: $failures of '
        '${missing.length} downloads failed. '
        'Retry synchronization to resume. '
        'Example document numbers: ${examples.join(', ')}',
      );
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
