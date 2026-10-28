import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_job_retirement.dart';
import 'local_job_deletion_v3.dart';
import 'test_job_cleanup_policy.dart';

class LocalDocumentDetailCache {
  const LocalDocumentDetailCache({BriskersLocalDatabase? database,
    Future<bool> Function(SharedPreferences, String, String)? preferenceWriter,
  }) : _injectedDatabase = database, _preferenceWriter = preferenceWriter;

  final BriskersLocalDatabase? _injectedDatabase;
  final Future<bool> Function(SharedPreferences, String, String)? _preferenceWriter;
  BriskersLocalDatabase get _database => _injectedDatabase ?? localDatabase;

  Future<bool> _blocked(
    String businessId,
    String documentId, [
    Map<String, dynamic>? detail,
  ]) async {
    final payload = detail ?? const <String, dynamic>{};
    if (await LocalJobDeletionV3.payloadIsDeleted(_database, businessId, payload, includeVisibilityScope: false)) { return true; }
    final ids = <String>{
      documentId,
      if (payload['id'] != null) payload['id'].toString(),
      if (payload['_server_document_id'] != null)
        payload['_server_document_id'].toString(),
    };
    final blocked = {...await LocalJobRetirement.blockedDocumentIds(
        _database, businessId, includeVisibilityScope: false),
      ...await LocalJobDeletionV3.scopeDirtyIds(_database, businessId)};
    if (ids.any(blocked.contains)) { return true; }
    final jobId = payload['job_id']?.toString() ?? '';
    // Invoice details can arrive before the index row. Estimates and other
    // accounting kinds remain accessible; an unknown kind fails closed.
    return (payload['kind'] == null || payload['kind'] == 'invoice') &&
        jobId.isNotEmpty &&
        (await LocalJobRetirement.blockedJobIds(_database, businessId, includeVisibilityScope: false)).contains(jobId);
  }

  Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) { return null; }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _projectRetiredConversion(
    String businessId,
    Map<String, dynamic> detail,
  ) async {
    final invoiceId = detail['converted_invoice_id']?.toString() ?? '';
    if (detail['kind'] != 'estimate' ||
        invoiceId.isEmpty ||
        !await LocalJobRetirement.isDocumentBlocked(
          _database,
          businessId,
          invoiceId,
        )) {
      return detail;
    }
    // This is a presentation projection. The saved estimate, accepted status,
    // invoice history and exact original conversion identity stay untouched.
    return {
      ...detail,
      'converted': false,
      'converted_invoice_id': null,
      'converted_invoice_number': null,
      'converted_invoice_date': null,
      '_retired_conversion': true,
    };
  }

  // Serialize every read/write/invalidation for an identity, including across
  // different service instances. A newer edit queued behind cleanup is saved
  // afterwards, rather than disappearing in a check/remove race.
  static final Map<String, Future<void>> _pending = {};

  String _key(String businessId, String documentId) =>
      'briskers_document_detail_${businessId}_$documentId';

  Future<T> _serialized<T>(String key, Future<T> Function() operation) async {
    final before = _pending[key];
    final done = Completer<void>();
    _pending[key] = done.future;
    if (before != null) { await before; }
    try {
      return await operation();
    } finally {
      done.complete();
      if (identical(_pending[key], done.future)) _pending.remove(key);
    }
  }

  Future<void> save(
    String businessId,
    String documentId,
    Map<String, dynamic> detail, {
    int? visibilityGeneration,
  }) {
    final key = _key(businessId, documentId);
    final encoded = jsonEncode(LocalJobDeletionV3.stripVisibilityMetadata(detail));
    // Always acquire SQLite before the preference queue. Callers may already
    // hold a SQLite transaction; reversing that order can deadlock a cache
    // writer against a transactional sync reader.
    return _database.transaction(
      () => _serialized(key, () async {
        final generation = await LocalJobDeletionV3.validateVisibilityCacheWrite(
            _database, businessId, key, detail, visibilityGeneration: visibilityGeneration);
        if (generation == null) {
          if (visibilityGeneration != null) { throw StateError('Cache scope changed or retained work requires reconciliation'); }
          return;
        }
        // A detail response authorizes this cache only. Do not release the
        // separate index-row fence before that row is freshly replaced.
        if (await _blocked(businessId, documentId, detail)) { return; }
        final prefs = await SharedPreferences.getInstance();
        // A late response may omit a provisional alias's canonical identity.
        // The existing association remains authoritative while it is blocked.
        if (await _blocked(
          businessId,
          documentId,
          _decode(prefs.getString(key)),
        )) {
          return;
        }
        final written = await (_preferenceWriter?.call(prefs, key, encoded) ?? prefs.setString(key, encoded));
        await prefs.reload();
        if (!written || prefs.getString(key) != encoded) {
          throw StateError('Document cache write was not verified');
        }
        await LocalJobDeletionV3.markVisibilityCacheWritten(_database, businessId, key, generation);
      }),
    );
  }

  Future<Map<String, dynamic>?> load(String businessId, String documentId) {
    final key = _key(businessId, documentId);
    return _database.transaction(
      () => _serialized(key, () async {
        final generation = await LocalJobDeletionV3.captureVisibilityGeneration(_database, businessId);
        if (!await LocalJobDeletionV3.visibilityCacheReadable(_database, businessId, key)) { return null; }
        if (await _blocked(businessId, documentId)) { return null; }
        final prefs = await SharedPreferences.getInstance();
        final detail = _decode(prefs.getString(key));
        if (detail == null) { return null; }
        if (await _blocked(businessId, documentId, detail)) { return null; }
        final result = await _projectRetiredConversion(businessId, detail);
        await LocalJobDeletionV3.assertVisibilityGeneration(_database, businessId, generation);
        return generation == 0 ? result : {...result, '_local_visibility_generation': generation};
      }),
    );
  }

  /// Read existing local snapshots for exact payment-ID reporting links.
  /// Missing snapshots remain unknown; this never deletes or changes data.
  Future<List<Map<String, dynamic>>> loadAll(String businessId) {
    return _database.transaction(() async {
      final prefs = await SharedPreferences.getInstance();
      final prefix = 'briskers_document_detail_${businessId}_';
      final result = <Map<String, dynamic>>[];
      for (final key in prefs.getKeys().where(
        (key) => key.startsWith(prefix),
      )) {
        final snapshot = await load(businessId, key.substring(prefix.length));
        if (snapshot != null) result.add(snapshot);
      }
      return result;
    });
  }

  /// Conditional cleanup invalidation. Snapshot comparison and removal share
  /// the same per-document queue with all writes. Unknown/dirty state is kept.
  Future<bool> removeIfUnchanged(
    String businessId,
    String documentId,
    Map<String, dynamic>? expected,
  ) {
    final key = _key(businessId, documentId);
    return _database.transaction(
      () => _serialized(key, () async {
        if (await _blocked(businessId, documentId, expected)) { return false; }
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final raw = prefs.getString(key);
        if (raw == null) { return true; }
        if (await _blocked(businessId, documentId, _decode(raw))) { return false; }
        if (expected == null ||
            raw != jsonEncode(LocalJobDeletionV3.stripVisibilityMetadata(expected)) ||
            TestJobCleanupPolicy.hasPendingSnapshot(expected)) {
          return false;
        }
        return prefs.remove(key);
      }),
    );
  }

  Future<void> remove(String businessId, String documentId) {
    final key = _key(businessId, documentId);
    return _database.transaction(
      () => _serialized(key, () async {
        if (await _blocked(businessId, documentId)) { return; }
        final prefs = await SharedPreferences.getInstance();
        if (await _blocked(
          businessId,
          documentId,
          _decode(prefs.getString(key)),
        )) {
          return;
        }
        await prefs.remove(key);
      }),
    );
  }
}

