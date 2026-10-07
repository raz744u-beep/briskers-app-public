import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'briskers_api.dart';

class LocalInvoiceStatusStylesCache {
  LocalInvoiceStatusStylesCache({
    BriskersApi api = const BriskersApi(),
  }) : _api = api;

  final BriskersApi _api;

  String _key(String businessId) =>
      'briskers_invoice_status_styles_$businessId';

  Future<List<Map<String, dynamic>>> refresh(String businessId) async {
    final styles = await _api.invoiceStatusStyles(businessId);
    await save(businessId, styles);
    return styles;
  }

  Future<void> save(
    String businessId,
    List<Map<String, dynamic>> styles,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(businessId), jsonEncode(styles));
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
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
