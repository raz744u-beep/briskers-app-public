import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'briskers_api.dart';

/// Shop-scoped item-category choices used by invoice and catalog editors.
///
/// Category definitions are separate from catalog item snapshots. An invoice
/// opened in Force Offline must never depend on the item-category RPC.
class LocalItemCategoriesCache {
  const LocalItemCategoriesCache({BriskersApi api = const BriskersApi()})
      : _api = api;

  final BriskersApi _api;

  String _key(String businessId) => 'briskers_item_categories_$businessId';

  Future<void> save(
    String businessId,
    List<Map<String, dynamic>> categories,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(businessId), jsonEncode(categories));
  }

  Future<List<Map<String, dynamic>>> load(String businessId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(businessId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((category) => Map<String, dynamic>.from(category))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Existing offline catalog entries retain category *names* even if the
  /// category settings list has never been downloaded on this device.
  static List<Map<String, dynamic>> fromCatalogItems(
    List<Map<String, dynamic>> items,
  ) {
    final names = <String, String>{};
    for (final item in items) {
      final name = item['category']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      names.putIfAbsent(name.toLowerCase(), () => name);
    }
    final sorted = names.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted
        .map((name) => <String, dynamic>{'name': name, 'active': true})
        .toList();
  }

  /// Official choices take precedence, including their inactive flags and
  /// sort order. Add locally used category names to avoid orphaned selections
  /// in offline work, while deduplicating case-insensitively.
  static List<Map<String, dynamic>> merge(
    List<Map<String, dynamic>> official,
    List<Map<String, dynamic>> fallback,
  ) {
    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];
    for (final row in [...official, ...fallback]) {
      final name = row['name']?.toString().trim() ?? '';
      if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
      merged.add({...row, 'name': name});
    }
    return merged;
  }

  /// In Auto, try to refresh while the owner is searching for a catalog item.
  /// If transport fails, use the last saved shop snapshot plus categories
  /// already present on locally cached catalog items.
  Future<List<Map<String, dynamic>>> forInvoiceEditor(
    String businessId, {
    required bool forceOffline,
    required List<Map<String, dynamic>> localCatalogItems,
  }) async {
    final locallyUsed = fromCatalogItems(localCatalogItems);
    final cached = await load(businessId);
    if (forceOffline) return merge(cached, locallyUsed);

    try {
      final live = await _api
          .itemCategories(businessId, includeInactive: true)
          .timeout(const Duration(seconds: 4));
      await save(businessId, live);
      return merge(live, locallyUsed);
    } catch (_) {
      return merge(cached, locallyUsed);
    }
  }
}
