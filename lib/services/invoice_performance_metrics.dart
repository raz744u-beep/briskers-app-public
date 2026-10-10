import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Only anonymous invoice identifiers and elapsed milliseconds. This is a
/// bounded, device-local record for diagnosing Auto vs offline performance.
class InvoicePerformanceMetrics {
  const InvoicePerformanceMetrics();

  String _key(String businessId) => 'briskers_perf_invoice_$businessId';

  Future<void> record(
    String businessId, {
    required String documentId,
    required String stage,
    required int milliseconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(businessId);
    List<dynamic> existing = [];
    try {
      existing = jsonDecode(prefs.getString(key) ?? '[]') as List;
    } catch (_) {
      // Restore bounded log after a corrupt preference value.
    }
    existing.add({
      'document_id': documentId,
      'stage': stage,
      'ms': milliseconds,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    if (existing.length > 25) {
      existing = existing.sublist(existing.length - 25);
    }
    await prefs.setString(key, jsonEncode(existing));
  }

  Future<List<Map<String, dynamic>>> recent(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(prefs.getString(_key(businessId)) ?? '[]');
      if (decoded is! List) return const [];
      return decoded.whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value)).toList();
    } catch (_) {
      return const [];
    }
  }
}
