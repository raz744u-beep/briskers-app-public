import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Shop-scoped payment method snapshots for an offline payment entry dialog.
/// Caching method choices does not authorize or record a payment.
class LocalPaymentMethodsCache {
  const LocalPaymentMethodsCache();

  String _key(String businessId) => 'briskers_payment_methods_$businessId';

  Future<void> save(
    String businessId,
    List<Map<String, dynamic>> methods,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(businessId), jsonEncode(methods));
  }

  Future<List<Map<String, dynamic>>> load(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
