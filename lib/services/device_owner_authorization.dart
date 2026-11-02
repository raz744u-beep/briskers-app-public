import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import 'briskers_api.dart';
import 'local_owner_authorization.dart';

class _DeviceEnrollmentStore implements OwnerEnrollmentStore {
  static const _key = 'briskers_owner_delete_enrollment_v1';
  // Android uses Keystore-backed encryption. iOS records stay on this device.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  );
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class DeviceOwnerAuthorization with WidgetsBindingObserver {
  DeviceOwnerAuthorization._();
  static final instance = DeviceOwnerAuthorization._();
  final _deviceAuth = LocalAuthentication();
  StreamSubscription<AuthState>? _subscription;
  OwnerSessionIdentity? _lastIdentity;
  late final authority = LocalOwnerAuthorization(
    store: _DeviceEnrollmentStore(),
    currentIdentity: currentIdentity,
    verifyOwner: _verifyOwner,
    verifyLocalOwner: _verifyLocalOwner,
    authenticateDevice: () async {
      if (!await _deviceAuth.isDeviceSupported()) {
        throw StateError('Set a screen lock or fingerprint on this Owner device first.');
      }
      return _deviceAuth.authenticate(
        localizedReason: 'Unlock Owner access to delete Briskers records',
        biometricOnly: false,
        persistAcrossBackgrounding: false,
      );
    },
  );

  OwnerSessionIdentity? currentIdentity() {
    final session = supabase.auth.currentSession;
    if (session == null) return null;
    try {
      final token = session.accessToken.split('.');
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token[1])))) as Map;
      final sessionId = claims['session_id'];
      if (claims['sub'] != session.user.id || sessionId is! String || sessionId.isEmpty) return null;
      // These claims identify the already-enrolled session; they NEVER grant
      // Owner privileges. Enrollment independently verifies the token remotely.
      return OwnerSessionIdentity(session.user.id, sessionId);
    } catch (_) { return null; }
  }

  // Uses the same account-bound local business context as the regular app.
  // The OS device challenge is mandatory; callers cannot supply a role map.
  Future<VerifiedOwnerEnrollment> _verifyLocalOwner(String business) async {
    final identity = currentIdentity();
    if (identity == null) throw StateError('Open the saved Owner account first.');
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString('briskers_business_context_${identity.actorId}');
    final data = raw == null ? null : jsonDecode(raw);
    if (data is! Map || data['business_id'] != business || data['role_code'] != 'owner' ||
        !identity.matches(currentIdentity())) {
      throw StateError('Only the saved Owner account can delete local records.');
    }
    return VerifiedOwnerEnrollment(identity,business);
  }

  Future<VerifiedOwnerEnrollment> _verifyOwner(String business) async {
    final before = currentIdentity();
    if (before == null) throw StateError('Sign in before enrolling this device.');
    final user = (await networkSupabase.auth.getUser()).user;
    if (user?.id != before.actorId) throw StateError('Owner identity could not be verified.');
    final memberships = await const BriskersApi().myBusinesses();
    if (!before.matches(currentIdentity()) || !memberships.any((row) =>
        '${row['business_id'] ?? row['id'] ?? ''}' == business &&
        '${row['role_code'] ?? row['role'] ?? ''}' == 'owner')) {
      await authority.revoke();
      throw StateError('Only the verified Owner of this business can enroll this device.');
    }
    return VerifiedOwnerEnrollment(before, business);
  }

  void initialize() {
    if (_subscription != null) return;
    WidgetsBinding.instance.addObserver(this);
    _lastIdentity = currentIdentity();
    _subscription = supabase.auth.onAuthStateChange.listen((event) {
      final next = currentIdentity();
      if (event.event == AuthChangeEvent.signedOut ||
          (_lastIdentity != null && !_lastIdentity!.matches(next))) {
        // revoke invalidates grants synchronously before its first await.
        unawaited(authority.revoke().catchError((Object _) {}));
      }
      _lastIdentity = next;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.detached) &&
        !authority.isAuthenticating) {
      authority.lock();
    }
  }

  /// Only invoke with an authenticated server response, never a cached row.
  Future<void> observeServerMemberships(List<Map<String, dynamic>> rows,
      OwnerSessionIdentity identity) async {
    if (!identity.matches(currentIdentity())) return;
    final stored = await _DeviceEnrollmentStore().read();
    if (!identity.matches(currentIdentity()) || stored == null) return;
    try {
      final enrollment = jsonDecode(stored) as Map;
      if (enrollment['actor_id'] != identity.actorId ||
          enrollment['session_id'] != identity.sessionId ||
          !rows.any((row) => '${row['business_id'] ?? row['id'] ?? ''}' == enrollment['business_id'] &&
              '${row['role_code'] ?? row['role'] ?? ''}' == 'owner')) {
        await authority.revoke();
      }
    } catch (_) { await authority.revoke(); }
  }
}
