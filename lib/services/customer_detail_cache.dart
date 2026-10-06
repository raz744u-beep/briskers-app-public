import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CustomerDetailCache {
  const CustomerDetailCache();

  String _key(String businessId, String customerId, String section) =>
      'briskers_customer_section_${businessId}_${customerId}_$section';

  Future<void> save(
    String businessId,
    String customerId,
    String section,
    Object value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(businessId, customerId, section),
      jsonEncode(value),
    );
  }

  Future<dynamic> load(
    String businessId,
    String customerId,
    String section,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId, customerId, section));
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
