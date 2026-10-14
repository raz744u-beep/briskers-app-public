import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'test_job_cleanup_policy.dart';

class LocalDocumentDetailCache {
  const LocalDocumentDetailCache();

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
    if (before != null) await before;
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
    Map<String, dynamic> detail,
  ) {
    final key = _key(businessId, documentId);
    final encoded = jsonEncode(detail);
    return _serialized(key, () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, encoded);
    });
  }

  Future<Map<String, dynamic>?> load(
    String businessId,
    String documentId,
  ) {
    final key = _key(businessId, documentId);
    return _serialized(key, () async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      try {
        final decoded = jsonDecode(raw);
        return decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : null;
      } catch (_) {
        return null;
      }
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
    return _serialized(key, () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(key);
      if (raw == null) return true;
      if (expected == null || raw != jsonEncode(expected) ||
          TestJobCleanupPolicy.hasPendingSnapshot(expected)) {
        return false;
      }
      return prefs.remove(key);
    });
  }

  Future<void> remove(
    String businessId,
    String documentId,
  ) {
    final key = _key(businessId, documentId);
    return _serialized(key, () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    });
  }
}
