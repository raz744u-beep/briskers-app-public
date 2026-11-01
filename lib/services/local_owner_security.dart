import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/supabase_config.dart';

/// Local Owner identity lives in Android Keystore / iOS Keychain-backed
/// secure storage. Supabase is used ONLY to migrate an already verified Owner
/// profile; subsequent unlocks never access a network or Supabase session.
class LocalOwnerSecurity {
  LocalOwnerSecurity._();
  static final instance = LocalOwnerSecurity._();
  static const _store = FlutterSecureStorage();
  static const _identityKey = 'briskers_local_owner_identity_v1';
  static const _passwordKey = 'briskers_local_owner_password_v1';
  static const _biometricKey = 'briskers_local_owner_biometric_v1';
  final LocalAuthentication _auth = LocalAuthentication();

  Map<String, dynamic>? _unlockedIdentity;
  Map<String, dynamic>? get unlockedIdentity => _unlockedIdentity == null
      ? null : Map<String, dynamic>.unmodifiable(_unlockedIdentity!);
  String? get unlockedActorId => _unlockedIdentity?['actor_id'] as String?;
  bool get isUnlocked => _unlockedIdentity != null;

  Future<bool> get isConfigured async =>
      (await _store.read(key: _identityKey)) != null &&
      (await _store.read(key: _passwordKey)) != null;

  static String _hashPassword(Map<String, String> args) {
    final salt = base64Decode(args['salt']!);
    final password = utf8.encode(args['password']!);
    final hmac = Hmac(sha256, password);
    final block = Uint8List.fromList([...salt, 0, 0, 0, 1]);
    var u = hmac.convert(block).bytes;
    final result = Uint8List.fromList(u);
    for (var i = 1; i < 120000; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return base64Encode(result);
  }

  /// An already signed-in, cached Owner account is required ONCE for migration.
  /// Never allow installing a fresh app to self-assign Owner privileges.
  Future<void> enrollExistingOwner(String password) async {
    if (await isConfigured) {
      throw StateError('An Owner password is already configured on this device.');
    }
    if (password.length < 10) {
      throw StateError('Use an Owner password of at least 10 characters.');
    }
    final user = supabase.auth.currentUser;
    if (supabase.auth.currentSession == null || user == null) {
      throw StateError('An existing verified Owner session is needed for one-time migration.');
    }
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('briskers_business_context_${user.id}');
    if (cached == null) {
      throw StateError('No verified Owner business was previously saved on this device.');
    }
    final decoded = jsonDecode(cached);
    if (decoded is! Map || decoded['role_code'] != 'owner' ||
        decoded['business_id'] is! String ||
        (decoded['business_id'] as String).isEmpty) {
      throw StateError('Existing local business context is not an Owner account.');
    }
    final salt = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final encodedSalt = base64Encode(salt);
    final digest = await compute(_hashPassword,
        {'password': password, 'salt': encodedSalt});
    final identity = jsonEncode({
      'actor_id': user.id,
      'business_id': decoded['business_id'],
      'business_name': decoded['business_name'] ?? 'Briskers',
      'role_code': 'owner',
    });
    // Write credential before identity; an interrupted setup never
    // exposes an unlocked Owner account.
    await _store.write(key: _passwordKey,
        value: jsonEncode({'salt': encodedSalt, 'digest': digest}));
    await _store.write(key: _identityKey, value: identity);
    _unlockedIdentity = Map<String, dynamic>.from(jsonDecode(identity) as Map);
  }

  Future<bool> unlockWithPassword(String password) async {
    _unlockedIdentity = null;
    final saved = await _store.read(key: _passwordKey);
    final identity = await _store.read(key: _identityKey);
    if (saved == null || identity == null) return false;
    final decoded = jsonDecode(saved) as Map<String, dynamic>;
    final expected = base64Decode(decoded['digest'] as String);
    final received = base64Decode(await compute(_hashPassword,
      {'password': password, 'salt': decoded['salt'] as String}));
    var difference = expected.length ^ received.length;
    for (var i = 0; i < expected.length && i < received.length; i++) {
      difference |= expected[i] ^ received[i];
    }
    if (difference != 0) return false;
    _unlockedIdentity = Map<String, dynamic>.from(jsonDecode(identity) as Map);
    return true;
  }

  Future<bool> get biometricsEnabled async =>
      (await _store.read(key: _biometricKey)) == 'yes';

  Future<bool> get hasEnrolledBiometrics async {
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    if (!isUnlocked) throw StateError('Unlock with your Owner password first.');
    if (enabled && !await hasEnrolledBiometrics) {
      throw StateError('Enroll a face or fingerprint in phone settings first.');
    }
    await _store.write(key: _biometricKey, value: enabled ? 'yes' : 'no');
  }

  Future<bool> unlockWithBiometrics() async {
    _unlockedIdentity = null;
    if (!await isConfigured || !await biometricsEnabled ||
        !await hasEnrolledBiometrics) return false;
    try {
      final valid = await _auth.authenticate(
        localizedReason: 'Unlock Briskers Owner access',
        options: const AuthenticationOptions(
          biometricOnly: true, stickyAuth: true));
      if (!valid) return false;
      final identity = await _store.read(key: _identityKey);
      if (identity == null) return false;
      _unlockedIdentity = Map<String, dynamic>.from(jsonDecode(identity) as Map);
      return true;
    } catch (_) {
      return false;
    }
  }

  void lock() => _unlockedIdentity = null;
}
