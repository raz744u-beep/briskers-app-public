import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Device-local employee display alias, separate from the legal payroll name.
///
/// No remote nickname sync is claimed by this service. Multi-device sync
/// requires a separate vetted storage/replay contract before release.
class EmployeeNicknameStore {
  static const _keyPrefix = 'briskers_employee_nicknames_v1:';
  String _key(String businessId) => '$_keyPrefix$businessId';

  Future<Map<String, String>> all(String businessId) async {
    if (businessId.trim().isEmpty) return {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String &&
              (entry.value as String).trim().isNotEmpty)
            entry.key as String: (entry.value as String).trim(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<String?> get(String businessId, String employeeId) async {
    if (employeeId.trim().isEmpty) return null;
    return (await all(businessId))[employeeId];
  }

  Future<void> save(
    String businessId,
    String employeeId,
    String nickname,
  ) async {
    if (businessId.trim().isEmpty || employeeId.trim().isEmpty) {
      throw ArgumentError('A business and employee ID are required.');
    }
    final value = nickname.trim();
    if (value.length > 32 || value.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError('Nickname must be at most 32 characters on one line.');
    }
    final saved = await all(businessId);
    if (value.isEmpty) {
      saved.remove(employeeId);
    } else {
      saved[employeeId] = value;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key(businessId), jsonEncode(saved))) {
      throw StateError('Nickname could not be saved on this device.');
    }
  }

  Future<List<Map<String, dynamic>>> decorate(
    String businessId,
    List<Map<String, dynamic>> employees,
  ) async {
    final values = await all(businessId);
    return [
      for (final employee in employees)
        {
          ...employee,
          if (values[employee['id']?.toString()] != null)
            'nickname': values[employee['id']?.toString()],
        },
    ];
  }

  static String displayName(Map<String, dynamic> employee) {
    final nickname = employee['nickname']?.toString().trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    return employee['name']?.toString().trim() ?? '';
  }
}
