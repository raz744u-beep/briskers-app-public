import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalDocumentDetailCache {
  const LocalDocumentDetailCache();

  String _key(String businessId, String documentId) =>
      'briskers_document_detail_${businessId}_$documentId';

  Future<void> save(
    String businessId,
    String documentId,
    Map<String, dynamic> detail,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(businessId, documentId),
      jsonEncode(detail),
    );
  }

  Future<Map<String, dynamic>?> load(
    String businessId,
    String documentId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId, documentId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(
    String businessId,
    String documentId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(businessId, documentId));
  }
}
