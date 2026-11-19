import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Device-local view preferences, kept separate from financial records and sync.
class ExpenseFilterPreferences {
  const ExpenseFilterPreferences({
    this.direction = 'all',
    this.dateRange = 'all',
    this.customStart,
    this.customEnd,
    this.accountId,
    this.categoryId,
    this.counterpartyId,
  });

  final String direction;
  final String dateRange;
  final DateTime? customStart;
  final DateTime? customEnd;
  final String? accountId;
  final String? categoryId;
  final String? counterpartyId;

  static String storageKey(String business, String role) =>
      'briskers_expense_filters_v1_${jsonEncode([business, role])}';

  static Future<void> _writes = Future<void>.value();

  Future<void> save(String business, String role) {
    // Serialize rapid selections so an older write cannot win after a newer one.
    final write = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(storageKey(business, role), jsonEncode({
        'direction': direction,
        'dateRange': dateRange,
        'customStart': customStart?.toIso8601String(),
        'customEnd': customEnd?.toIso8601String(),
        'accountId': accountId,
        'categoryId': categoryId,
        'counterpartyId': counterpartyId,
      }));
      if (!saved) throw StateError('Expense filters could not be saved');
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  static Future<ExpenseFilterPreferences> load(String business, String role) async {
    await _writes;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey(business, role));
    if (raw == null) return const ExpenseFilterPreferences();
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      String? id(String key) => data[key] is String &&
              (data[key] as String).trim().isNotEmpty
          ? data[key] as String : null;
      final direction = data['direction'];
      final range = data['dateRange'];
      final year = int.tryParse(range?.toString() ?? '');
      final validRange = const {
        'all', '30d', '60d', '90d', 'thisMonth', 'lastMonth',
        '3m', '6m', 'ytd', '1y', 'custom',
      }.contains(range) || (year != null && year >= 1900 && year <= 9999);
      final start = DateTime.tryParse(data['customStart']?.toString() ?? '');
      final end = DateTime.tryParse(data['customEnd']?.toString() ?? '');
      final validCustom = start != null && end != null && !start.isAfter(end);
      return ExpenseFilterPreferences(
        direction: const {'all', 'income', 'expense'}.contains(direction)
            ? direction as String : 'all',
        dateRange: validRange && (range != 'custom' || validCustom)
            ? range as String : 'all',
        customStart: validCustom ? start : null,
        customEnd: validCustom ? end : null,
        accountId: id('accountId'),
        categoryId: id('categoryId'),
        counterpartyId: id('counterpartyId'),
      );
    } catch (_) {
      return const ExpenseFilterPreferences();
    }
  }
}
