import 'dart:convert';

import 'package:briskers_app/services/expense_filter_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('all filter fields survive a fresh preference instance without network', () async {
    final selected = ExpenseFilterPreferences(
      direction: 'expense', dateRange: 'custom',
      customStart: DateTime(2026, 10, 1), customEnd: DateTime(2026, 10, 31),
      accountId: 'cash', categoryId: 'parts', counterpartyId: 'cintas',
    );
    await selected.save('shop', 'owner');
    final prefs = await SharedPreferences.getInstance();
    final disk = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
    // Discard plugin singleton/cache, retaining only its persisted values.
    SharedPreferences.setMockInitialValues(disk);
    final restored = await ExpenseFilterPreferences.load('shop', 'owner');
    expect(restored.direction, 'expense');
    expect(restored.dateRange, 'custom');
    expect(restored.customStart, DateTime(2026, 10, 1));
    expect(restored.customEnd, DateTime(2026, 10, 31));
    expect(restored.accountId, 'cash');
    expect(restored.categoryId, 'parts');
    expect(restored.counterpartyId, 'cintas');
    expect((await ExpenseFilterPreferences.load('other-shop', 'owner')).dateRange, 'all');
    expect((await ExpenseFilterPreferences.load('shop', 'secretary')).dateRange, 'all');
  });

  test('latest selection wins and explicit All Time also survives reopening', () async {
    await Future.wait([
      const ExpenseFilterPreferences(dateRange: '30d').save('shop', 'owner'),
      const ExpenseFilterPreferences(dateRange: 'lastMonth').save('shop', 'owner'),
    ]);
    expect((await ExpenseFilterPreferences.load('shop', 'owner')).dateRange, 'lastMonth');
    await const ExpenseFilterPreferences().save('shop', 'owner');
    expect((await ExpenseFilterPreferences.load('shop', 'owner')).dateRange, 'all');
  });

  test('malformed preferences and invalid custom ranges fall back safely', () async {
    final prefs = await SharedPreferences.getInstance();
    final key = ExpenseFilterPreferences.storageKey('shop', 'owner');
    for (final raw in ['broken json', '[]', jsonEncode({
      'dateRange': 'custom', 'direction': 'unknown',
      'customStart': '2026-11-30', 'customEnd': '2026-11-01',
    })]) {
      await prefs.setString(key, raw);
      final saved = await ExpenseFilterPreferences.load('shop', 'owner');
      expect(saved.dateRange, 'all');
      expect(saved.direction, 'all');
    }
  });

  test('relative ranges remain relative and calendar-year selection is retained', () async {
    for (final range in ['30d', '60d', '90d', 'thisMonth', 'lastMonth', '3m', '6m', 'ytd', '1y', '2025']) {
      await ExpenseFilterPreferences(dateRange: range).save('shop', 'owner');
      expect((await ExpenseFilterPreferences.load('shop', 'owner')).dateRange, range);
    }
  });
}
