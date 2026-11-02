import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'job_profitability_summary.dart';

/// Last verified Owner-only profitability snapshot, scoped by authenticated
/// user, shop and job. Never calculates profit from incomplete offline records.
///
/// Only the numeric RPC summary is retained. Vendor/attachment details are not
/// persisted here, and a cached summary must always be marked as historical.
class OwnerJobProfitabilityCache {
  const OwnerJobProfitabilityCache();

  String? _key(String businessId, String userId, String jobId) {
    if (businessId.trim().isEmpty ||
        userId.trim().isEmpty ||
        jobId.trim().isEmpty) {
      return null;
    }
    return 'briskers_owner_job_profitability_v1_${Uri.encodeComponent(businessId)}'
        '_${Uri.encodeComponent(userId)}_${Uri.encodeComponent(jobId)}';
  }

  Future<void> save(
    String businessId,
    String userId,
    String jobId,
    Map<String, dynamic> rpc, {
    DateTime? verifiedAt,
  }) async {
    final key = _key(businessId, userId, jobId);
    final summary = JobProfitabilitySummary.fromRpc(rpc);
    if (key == null || summary == null) return;

    final at = verifiedAt ?? DateTime.now();
    if (at.isAfter(DateTime.now().add(const Duration(minutes: 1)))) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(<String, dynamic>{
      'revenue': summary.revenue,
      'sales_tax': summary.salesTax,
      'direct_cost': summary.directCost,
      'mechanic_cost': summary.mechanicCost,
      'total_cost': summary.totalCost,
      'verified_at': at.toUtc().toIso8601String(),
    }));
  }

  Future<({Map<String, dynamic> data, DateTime at})?> load(
    String businessId,
    String userId,
    String jobId,
  ) async {
    final key = _key(businessId, userId, jobId);
    if (key == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final at = DateTime.parse(data.remove('verified_at') as String).toLocal();
      if (at.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
        return null;
      }
      if (JobProfitabilitySummary.fromRpc(data) == null) return null;
      return (data: data, at: at);
    } catch (_) {
      return null;
    }
  }
}
