import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// An installation identity independent of the payroll database. Copying the
/// SQLite file does not copy the private signing seed.
class PayrollLanIdentity {
  PayrollLanIdentity._(this._keys, this.publicKey);

  static final _algorithm = Ed25519();
  static const _seedKey = 'briskers_payroll_lan_signing_seed_v1';
  static Future<PayrollLanIdentity>? _installation;
  final SimpleKeyPair _keys;
  final SimplePublicKey publicKey;
  String get deviceId => base64UrlEncode(publicKey.bytes);

  static Future<PayrollLanIdentity> load() =>
      _installation ??= loadFromStorage(const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device,
        ),
      ));

  @visibleForTesting
  static Future<PayrollLanIdentity> loadFromStorage(FlutterSecureStorage storage) async {
    final saved = await storage.read(key: _seedKey);
    if (saved != null) return fromSeed(base64Url.decode(saved));
    final random = Random.secure();
    final seed = List<int>.generate(32, (_) => random.nextInt(256));
    await storage.write(key: _seedKey, value: base64UrlEncode(seed));
    return fromSeed(seed);
  }

  static Future<PayrollLanIdentity> fromSeed(List<int> seed) async {
    final keys = await _algorithm.newKeyPairFromSeed(seed);
    return PayrollLanIdentity._(keys, await keys.extractPublicKey());
  }

  Future<String> sign(String message) async => base64UrlEncode(
        (await _algorithm.sign(utf8.encode(message), keyPair: _keys)).bytes,
      );

  static Future<bool> verify(String deviceId, String message, String proof) async {
    final key = base64Url.decode(deviceId);
    final signature = base64Url.decode(proof);
    if (key.length != 32 || signature.length != 64) return false;
    return _algorithm.verify(
      utf8.encode(message),
      signature: Signature(signature, publicKey: SimplePublicKey(key, type: KeyPairType.ed25519)),
    );
  }
}
