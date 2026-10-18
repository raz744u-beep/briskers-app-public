import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/connection_mode.dart';
import '../core/supabase_config.dart';
import 'briskers_api.dart';

/// Non-sensitive, per-user/per-shop employee roster. Compensation, SSNs,
/// contact fields, and app-login information are NEVER persisted here.
/// The Settings view retains inactive employees; assignment only uses active.
class EmployeeRosterSnapshot {
  const EmployeeRosterSnapshot(this.rows, this.refreshedAt);
  final List<Map<String, dynamic>> rows;
  final DateTime refreshedAt;
}

class EmployeeRosterCache {
  EmployeeRosterCache({
    BriskersApi api = const BriskersApi(),
    String? Function()? actorId,
    bool Function()? forceOffline,
  })  : _api = api,
        // Supabase's cached session is accessible without network calls.
        // networkSupabase deliberately throws in Force Offline, including
        // for harmless auth.currentUser reads; never use it for cache keys.
        _actorId = actorId ?? (() => supabase.auth.currentUser?.id),
        _forceOffline = forceOffline ??
            (() => BriskersConnectionModeController.instance.forceOffline);

  final BriskersApi _api;
  final String? Function() _actorId;
  final bool Function() _forceOffline;

  String? _key(String businessId, String scope) {
    final actor = _actorId();
    if (actor == null || actor.isEmpty || businessId.isEmpty) return null;
    return 'briskers_safe_employee_roster_v2_${actor}_${businessId}_$scope';
  }

  // Allow-list only. Never store arbitrary server Maps in preferences.
  static Map<String, dynamic>? _safeRow(Map raw) {
    final id = raw['id']?.toString() ?? '';
    final name = (raw['name'] ?? raw['display_name'])?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    return {
      'id': id,
      'name': name,
      'position_name': (raw['position_name'] ?? raw['position'])
              ?.toString().trim() ?? 'Employee',
      'active': raw['active'] != false,
    };
  }

  static List<Map<String, dynamic>> _safeRows(Iterable<dynamic> rows) {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final raw in rows) {
      if (raw is! Map) continue;
      final safe = _safeRow(raw);
      if (safe == null || !seen.add(safe['id'].toString())) continue;
      result.add(safe);
    }
    return result;
  }

  Future<void> _save(
      String businessId, String scope, List<Map<String, dynamic>> rows) async {
    final key = _key(businessId, scope);
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode({
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'rows': _safeRows(rows),
      }));
    } catch (_) {
      // A storage/plugin failure must not masquerade as a failed server write.
      // The online roster remains authoritative and available in this view.
    }
  }

  Future<EmployeeRosterSnapshot?> _read(String businessId, String scope) async {
    try {
      final key = _key(businessId, scope);
      if (key == null) return null;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null; // No cache is not a true empty roster.
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final updatedAt = DateTime.tryParse(data['updated_at']?.toString() ?? '');
      final rows = data['rows'];
      if (updatedAt == null || rows is! List) return null;
      return EmployeeRosterSnapshot(
          _safeRows(rows), updatedAt.toLocal());
    } catch (_) {
      return null;
    }
  }

  Future<EmployeeRosterSnapshot?> cachedSettings(String businessId) =>
      _read(businessId, 'settings');

  Future<EmployeeRosterSnapshot?> cachedAssignable(String businessId) =>
      _read(businessId, 'assignable');

  /// Only a successfully returned server list replaces the old snapshot.
  /// A successful *empty* server response is a real zero-employee roster.
  Future<List<Map<String, dynamic>>> refreshAssignable(
      String businessId) async {
    if (_forceOffline()) {
      throw StateError('Employee roster refresh requires a connection.');
    }
    final rows = _safeRows(await _api.assignableEmployees(businessId))
        .where((row) => row['active'] == true).toList();
    await _save(businessId, 'assignable', rows);
    return rows;
  }

  /// Settings server endpoint is separately permission-gated. Cache only
  /// harmless display/assignment identity fields from this privileged list.
  Future<List<Map<String, dynamic>>> refreshSettings(
      String businessId) async {
    if (_forceOffline()) {
      throw StateError('Employee settings refresh requires a connection.');
    }
    final rows = await _api.employeesSettings(businessId);
    await saveFromSettings(businessId, rows);
    return rows; // Full sensitive values remain in transient online UI only.
  }

  Future<void> saveFromSettings(
      String businessId, List<Map<String, dynamic>> serverRows) async {
    final safe = _safeRows(serverRows);
    await _save(businessId, 'settings', safe);
    await _save(businessId, 'assignable',
        safe.where((row) => row['active'] == true).toList());
  }

  /// Called if a successful employee/position write cannot be followed by
  /// an authoritative refresh. Never leave an old employee assignable.
  Future<void> invalidate(String businessId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final scope in ['settings', 'assignable']) {
        final key = _key(businessId, scope);
        if (key != null) await prefs.remove(key);
      }
    } catch (_) {
      // App settings storage failure must not invite a duplicate server save.
      // Next successful authoritative refresh replaces the stale snapshot.
    }
  }
}
