import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'expenses_period_totals.dart';

/// Only complete posted totals may be saved. Never derives totals from pages
/// in the list cache; exact business/filter scope is required for reuse.
class VerifiedExpenseTotalsCache {
  const VerifiedExpenseTotalsCache();

  String _key(String scope) => 'briskers_verified_totals_v1_$scope';

  Future<void> save(String scope, ExpensesPeriodTotals totals, DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(scope), jsonEncode({
      'income': totals.income, 'expenses': totals.expenses,
      'transactions': totals.transactions, 'feesUnverified': totals.feesUnverified,
      'verifiedAt': at.toUtc().toIso8601String(),
    }));
  }

  Future<({ExpensesPeriodTotals totals, DateTime at})?> load(String scope) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(scope));
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final income = (data['income'] as num).toDouble();
      final expenses = (data['expenses'] as num).toDouble();
      final transactions = data['transactions'] as int;
      final at = DateTime.parse(data['verifiedAt'] as String).toLocal();
      if (!income.isFinite || !expenses.isFinite || income < 0 || expenses < 0 ||
          transactions < 0 || at.isAfter(DateTime.now())) return null;
      return (totals: ExpensesPeriodTotals(income: income, expenses: expenses,
        transactions: transactions, feesUnverified: data['feesUnverified'] as bool), at: at);
    } catch (_) {
      return null;
    }
  }
}
