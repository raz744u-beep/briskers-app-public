import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'local_owner_authorization.dart';

/// Owner/session-bound encrypted profiles. Only last-four SSN digits are allowed.
/// Local edits and their comparison baselines stay encrypted, never in SQLite.
class SecureEmployeeDetailsCache {
  const SecureEmployeeDetailsCache();
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  static const editable = {
    'name',
    'phone',
    'email',
    'address',
    'position_id',
    'compensation_enabled',
    'payment_type',
    'hourly_rate',
    'weekly_rate',
    'active',
  };
  static const safeKeys = {
    ...editable,
    'id',
    'position',
    'ssn_last4',
    'default_payment_method',
    'w9_status',
    'user_linked',
    'positions',
  };
  static final Map<String, Future<void>> _writes = {};
  String _key(String shop, String actor, String employee) =>
      'briskers_employee_private_v1:${jsonEncode([shop, actor, employee])}';
  Map<String, dynamic> _safe(Map<String, dynamic> input) {
    final result = {
      for (final k in safeKeys)
        if (input.containsKey(k)) k: input[k],
    };
    if (result['ssn_last4'] != null &&
        !RegExp(r'^\d{4}$').hasMatch('${result['ssn_last4']}')) {
      result.remove('ssn_last4');
    }
    return result;
  }

  Future<void> _write(
    String shop,
    String employee,
    LocalOwnerGrant grant,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>?) transform,
  ) async {
    grant.assertValid(shop, grant.actorId);
    final key = _key(shop, grant.actorId, employee);
    final next = (_writes[key] ?? Future<void>.value()).then((_) async {
      final old = await read(shop, employee, grant);
      final value = await transform(old);
      grant.assertValid(shop, grant.actorId);
      await _storage.write(key: key, value: jsonEncode(value));
      grant.assertValid(shop, grant.actorId);
    });
    _writes[key] = next.catchError((Object _) {});
    await next;
  }

  Future<void> save(
    String shop,
    String employee,
    Map<String, dynamic> detail,
    LocalOwnerGrant grant,
  ) async {
    final safe = _safe(detail);
    if (safe['id'] != employee) throw StateError('Employee identity differs.');
    await _write(shop, employee, grant, (old) async {
      final pending = Map<String, dynamic>.from(old?['pending'] as Map? ?? {});
      final base = Map<String, dynamic>.from(old?['base'] as Map? ?? {});
      final merged = {...?old?['details'] as Map?, ...safe, ...pending};
      return {
        'verified_at': DateTime.now().toUtc().toIso8601String(),
        'details': merged,
        'base': pending.isEmpty ? safe : base,
        'pending': pending,
      };
    });
  }

  Future<void> edit(
    String shop,
    String employee,
    Map<String, dynamic> patch,
    LocalOwnerGrant grant,
  ) async {
    if (patch.keys.any((k) => !editable.contains(k))) {
      throw ArgumentError('Protected or unsupported employee field.');
    }
    if (patch.containsKey('name') && '${patch['name'] ?? ''}'.trim().isEmpty) {
      throw ArgumentError('Employee name is required.');
    }
    await _write(shop, employee, grant, (old) async {
      if (old == null) {
        throw StateError(
          'This profile has not been saved locally yet. Existing server details are unknown.',
        );
      }
      final details = Map<String, dynamic>.from(old['details'] as Map);
      final pending = Map<String, dynamic>.from(old['pending'] as Map? ?? {});
      final base = Map<String, dynamic>.from(old['base'] as Map? ?? details);
      for (final entry in patch.entries) {
        if (!details.containsKey(entry.key)) {
          throw StateError(
            'Unknown field cannot overwrite existing server data.',
          );
        }
        if (details[entry.key] != entry.value) {
          if (!pending.containsKey(entry.key)) {
            base[entry.key] = details[entry.key];
          }
          pending[entry.key] = entry.value;
        }
      }
      return {
        ...old,
        'details': {...details, ...patch},
        'base': base,
        'pending': pending,
      };
    });
  }

  Future<void> acknowledge(
    String shop,
    String employee,
    Map<String, dynamic> sent,
    Map<String, dynamic> remote,
    LocalOwnerGrant grant,
  ) async {
    if (remote['id'] != employee) {
      throw StateError('Employee identity differs.');
    }
    await _write(shop, employee, grant, (old) async {
      if (old == null) throw StateError('Local profile unavailable.');
      final pending = Map<String, dynamic>.from(old['pending'] as Map? ?? {});
      final base = Map<String, dynamic>.from(old['base'] as Map? ?? {});
      for (final k in sent.keys) {
        // An edit made while a sync was in flight must remain queued.
        if (pending[k] == sent[k]) {
          pending.remove(k);
        } else {
          base[k] = sent[k];
        }
      }
      final safe = _safe(remote);
      return {
        'verified_at': DateTime.now().toUtc().toIso8601String(),
        'details': {...old['details'] as Map, ...safe, ...pending},
        'base': pending.isEmpty ? safe : base,
        'pending': pending,
      };
    });
  }

  /// Explicit Owner conflict choice rebases only the reviewed fields.
  /// A second local edit during review is retained and must be reviewed again.
  Future<void> resolveConflict(
    String shop,
    String employee,
    Map<String, dynamic> remote,
    Map<String, dynamic> reviewed,
    bool keepLocal,
    LocalOwnerGrant grant,
  ) async {
    if (remote['id'] != employee ||
        reviewed.keys.any((k) => !editable.contains(k))) {
      throw StateError('Employee conflict identity or fields differ.');
    }
    await _write(shop, employee, grant, (old) async {
      if (old == null) throw StateError('Local profile unavailable.');
      final pending = Map<String, dynamic>.from(old['pending'] as Map? ?? {});
      final base = Map<String, dynamic>.from(old['base'] as Map? ?? {});
      for (final key in reviewed.keys) {
        if (!remote.containsKey(key) || pending[key] != reviewed[key]) {
          throw StateError('Employee changed during review. Review again.');
        }
        base[key] = remote[key];
        if (!keepLocal) pending.remove(key);
      }
      return {
        ...old,
        'details': {...old['details'] as Map, ..._safe(remote), ...pending},
        'base': base,
        'pending': pending,
      };
    });
  }

  Future<Map<String, dynamic>?> read(
    String shop,
    String employee,
    LocalOwnerGrant grant,
  ) async {
    grant.assertValid(shop, grant.actorId);
    final raw = await _storage.read(key: _key(shop, grant.actorId, employee));
    grant.assertValid(shop, grant.actorId);
    if (raw == null) return null;
    final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if ((value['details'] as Map)['id'] != employee) {
      throw StateError('Employee identity differs.');
    }
    // A profile is durable local data, not a seven-day disposable cache.
    value['details'] = _safe(
      Map<String, dynamic>.from(value['details'] as Map),
    );
    return value;
  }
}
