import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Bounded actual offline Job opening measurements for diagnostics.
class JobPerformanceMetrics {
  const JobPerformanceMetrics();
  String _key(String shop) => 'briskers_perf_job_$shop';

  Future<void> record(String shop, {
    required String jobId,
    required String stage,
    required int milliseconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> old = [];
    try {
      final value=jsonDecode(prefs.getString(_key(shop)) ?? '[]');
      if (value is List) old=value;
    } catch (_) {}
    old.add({
      'job_id':jobId,'stage':stage,'ms':milliseconds,
      'at':DateTime.now().toUtc().toIso8601String(),
    });
    if (old.length>25) old=old.sublist(old.length-25);
    await prefs.setString(_key(shop),jsonEncode(old));
  }

  Future<List<Map<String,dynamic>>> recent(String shop) async {
    final prefs=await SharedPreferences.getInstance();
    try {
      final raw=jsonDecode(prefs.getString(_key(shop)) ?? '[]');
      if (raw is! List) return const [];
      return raw.whereType<Map>()
        .map((x)=>Map<String,dynamic>.from(x)).toList();
    } catch (_) {
      return const [];
    }
  }
}
