import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'briskers_api.dart';

class LocalTaxSettingsCache {
  LocalTaxSettingsCache({BriskersApi api = const BriskersApi()}) : _api = api;

  final BriskersApi _api;

  String _key(String businessId) => 'briskers_tax_settings_$businessId';

  Future<Map<String, dynamic>> refresh(String businessId) async {
    final settings = await _api.taxSettings(businessId);
    await save(businessId, settings);
    return settings;
  }

  Future<void> save(
    String businessId,
    Map<String, dynamic> settings,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(businessId), jsonEncode(settings));
  }

  Future<Map<String, dynamic>?> load(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId));
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
}
