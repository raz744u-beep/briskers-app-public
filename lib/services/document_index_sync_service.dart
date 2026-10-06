import 'dart:async';

import 'package:drift/drift.dart';

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
    final state = await localDatabase.customSelect(
      '''
      SELECT last_server_cursor
      FROM local_sync_states
      WHERE business_id = ? AND scope = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        const Variable<String>(_scope),
      ],
    ).get();

    var cursor = state.isEmpty
        ? 0
        : state.first.readNullable<int>('last_server_cursor') ?? 0;
    var hasMore = true;

    while (hasMore) {
      final response = await _api.syncPullDocuments(
        businessId,
        afterVersion: cursor,
      );
      final raw = List<dynamic>.from(
        response['documents'] ?? const <dynamic>[],
      );
      final documents = raw
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
      final next = int.tryParse(
            response['next_version']?.toString() ?? '',
          ) ??
          cursor;

      await _repository.upsertFromServer(businessId, documents);
      await _prefetchOpenDocumentDetails(businessId, documents);
      await localDatabase.customStatement(
        '''
        INSERT INTO local_sync_states (
          business_id, scope, last_server_cursor, last_pull_at,
          last_error, bootstrapped
        ) VALUES (?, ?, ?, ?, NULL, 1)
        ON CONFLICT(business_id, scope) DO UPDATE SET
          last_server_cursor=excluded.last_server_cursor,
          last_pull_at=excluded.last_pull_at,
          last_error=NULL,
          bootstrapped=1
        ''',
        [
          businessId,
          _scope,
          next,
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        ],
      );

      hasMore = response['has_more'] == true;
      if (hasMore && next <= cursor) {
        throw StateError('Document sync cursor did not advance.');
      }
      cursor = next;
    }
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
