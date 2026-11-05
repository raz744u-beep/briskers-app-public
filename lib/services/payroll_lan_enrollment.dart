import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_owner_authorization.dart';
import 'payroll_lan_identity.dart';
import 'payroll_lan_peer.dart';

abstract interface class PayrollEnrollmentStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
}
class _PlatformPairStore implements PayrollEnrollmentStore {
  _PlatformPairStore(this.storage);
  final FlutterSecureStorage storage;
  @override Future<String?> read({required String key}) => storage.read(key: key);
  @override Future<void> write({required String key, required String value}) => storage.write(key: key, value: value);
}

/// Owner authentication approves mechanic links. Payment authority is supplied
/// separately by the portable, securely fenced payroll ledger lease.
class PayrollLanEnrollment {
  PayrollLanEnrollment(
    this.identity, {
    String approvedWriter = '',
    PayrollEnrollmentStore? store,
    FlutterSecureStorage storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    ),
  }) : _storage = store ?? _PlatformPairStore(storage);

  final PayrollLanIdentity identity;
  final PayrollEnrollmentStore _storage;


  static Future<void> _writes = Future<void>.value();

  String _key(String business, String entry) =>
      'briskers_payroll_lan_v1:${jsonEncode([business, entry])}';

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Kept for old callers; no device is designated and no phone is pinned.
  Future<void> designate(String business, LocalOwnerGrant grant) =>
      assertWriter(business, grant);

  Future<void> assertWriter(String business, LocalOwnerGrant grant) async {
    grant.assertValid(business, grant.actorId);
  }

  /// Intended for a private, in-person transfer to the named mechanic device.
  /// The signed code contains a per-device shared key and must stay private.
  Future<String> invite({
    required String business,
    required String employee,
    required String mechanicDevice,
    required LocalOwnerGrant grant,
  }) => _serialize(() async {
    await assertWriter(business, grant);
    if (employee.isEmpty || mechanicDevice == identity.deviceId ||
        base64Url.decode(mechanicDevice).length != 32) {
      throw ArgumentError('Select an employee and a valid mechanic device.');
    }
    final deviceKey = _key(business, 'device:$mechanicDevice');
    final boundEmployee = await _storage.read(key: deviceKey);
    if (boundEmployee != null && boundEmployee != employee) {
      throw StateError('This mechanic device is already paired to another employee.');
    }
    final key = _key(business, 'peer:$employee');
    final existing = await _storage.read(key: key);
    if (existing != null) {
      final data = await _decode(existing);
      if (data.mechanicDevice != mechanicDevice) {
        throw StateError('This employee already has a paired device.');
      }
      return existing;
    }
    final random = Random.secure();
    final secret = List<int>.generate(32, (_) => random.nextInt(256));
    final ownState = await _storage.read(key: 'briskers_owner_payroll_lease_v2:$business');
    final certificate = ownState == null ? null : (jsonDecode(ownState) as Map)['certificate'];
    final body = jsonEncode([
      'briskers-payroll-pair-v1', business, employee, identity.deviceId,
      mechanicDevice, base64UrlEncode(secret),
      if (certificate != null) certificate,
    ]);
    final code = jsonEncode([body, await identity.sign(body)]);
    await assertWriter(business, grant);
    await _storage.write(key: deviceKey, value: employee);
    await _storage.write(key: key, value: code);
    return code;
  });

  Future<PayrollLanPeer> accept({
    required String code,
    required String business,
    required String verifiedOwnerDevice,
    required String actor,
  }) => _serialize(() async {
    final peer = await _decode(code);
    if (peer.business != business ||
        peer.ownerDevice != verifiedOwnerDevice ||
        peer.mechanicDevice != identity.deviceId) {
      throw StateError('The pairing code belongs to a different shop or device.');
    }
    if (actor.isEmpty) throw StateError('Open your saved mechanic account first.');
    final key = _key(business, 'mechanic');
    final entry = jsonEncode([actor, code]);
    final existing = await _storage.read(key: key);
    if (existing != null && existing != entry) {
      throw StateError('This device already has a payroll assignment.');
    }

    await _storage.write(key: key, value: entry);
    return peer;
  });

  Future<PayrollLanPeer?> mechanicPeer(String business, String actor) async {
    final raw = await _storage.read(key: _key(business, 'mechanic'));
    if (raw == null) return null;
    final entry = jsonDecode(raw) as List<dynamic>;
    if (entry.first != actor) {
      throw StateError('This payroll link belongs to another mechanic account.');
    }
    final original = await _readPeer(business, 'mechanic', code: entry[1] as String);
    final route = await _storage.read(key: _key(business, 'active-owner'));
    return route == null ? original : original!.delegatedOwner(Map<String, dynamic>.from(jsonDecode(route) as Map));
  }

  Future<String?> exportOwnerLink(String business, String employee, void Function() assertOwner) async {
    assertOwner();
    return await _storage.read(key: _key(business, 'peer:$employee')) ??
        await _storage.read(key: _key(business, 'delegated-code:$employee'));
  }
  Future<void> importOwnerLink(String business, String employee, String code,
      Map<String, dynamic> certificate, LocalOwnerGrant grant) async {
    grant.assertValid(business, grant.actorId);
    final certificateOwner = jsonDecode(certificate['body'] as String) as Map;
    if (certificateOwner['device'] != identity.deviceId || certificateOwner['actor'] != grant.actorId) throw StateError('Owner certificate belongs to a different account or installation.');
    final original = await _decode(code);
    if (original.business != business || original.employee != employee) throw StateError('Wrong mechanic link scope.');
    if (original.ownerDevice == identity.deviceId) {
      await _storage.write(key: _key(business, 'peer:$employee'), value: code);
    } else {
      await original.delegatedOwner(certificate);
      await _storage.write(key: _key(business, 'delegated-code:$employee'), value: code);
      await _storage.write(key: _key(business, 'delegated-cert:$employee'), value: jsonEncode(certificate));
    }
    grant.assertValid(business, grant.actorId);
  }
  Future<void> acceptOwnerRoute(String business, String actor, Map<String, dynamic> certificate) async {
    final raw = await _storage.read(key: _key(business, 'mechanic'));
    if (raw == null) throw StateError('Pair this mechanic first.');
    final entry = jsonDecode(raw) as List;
    if (entry[0] != actor) throw StateError('Mechanic account changed.');
    final original = await _decode(entry[1] as String);
    await original.delegatedOwner(certificate);
    await _storage.write(key: _key(business, 'active-owner'), value: jsonEncode(certificate));
  }

  Future<PayrollLanPeer?> ownerPeer(String business, String employee) async {
    final direct = await _readPeer(business, 'peer:$employee');
    if (direct != null) {
      final raw = await _storage.read(key: 'briskers_owner_payroll_lease_v2:$business');
      final certificate = raw == null ? null : (jsonDecode(raw) as Map)['certificate'];
      return certificate == null ? direct : direct.delegatedOwner(Map<String, dynamic>.from(certificate as Map));
    }
    final code = await _storage.read(key: _key(business, 'delegated-code:$employee'));
    final raw = await _storage.read(key: _key(business, 'delegated-cert:$employee'));
    if (code == null || raw == null) return null;
    return (await _decode(code)).delegatedOwner(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  Future<PayrollLanPeer?> _readPeer(String business, String key, {String? code}) async {
    code ??= await _storage.read(key: _key(business, key));
    if (code == null) return null;
    final peer = await _decode(code);

    final localDevice = key == 'mechanic'
        ? peer.mechanicDevice : peer.ownerDevice;
    if (peer.business != business || localDevice != identity.deviceId) {
      throw StateError('Payroll pairing does not match this installation.');
    }
    return peer;
  }

  Future<PayrollLanPeer> _decode(String code) async {
    if (code.length > 4096) throw const FormatException('Pairing code too large.');
    final envelope = jsonDecode(code) as List<dynamic>;
    if (envelope.length != 2) throw const FormatException('Invalid pairing code.');
    final body = envelope[0] as String;
    final fields = jsonDecode(body) as List;
    if ((fields.length != 6 && fields.length != 7) || fields[0] != 'briskers-payroll-pair-v1' ||
        !await PayrollLanIdentity.verify(fields[3] as String, body, envelope[1] as String)) {
      throw const FormatException('Invalid payroll pairing signature.');
    }
    Map<String, dynamic>? certificate;
    String? anchor;
    if (fields.length == 7) {
      certificate = Map<String, dynamic>.from(fields[6] as Map);
      final entries = certificate['chain'] as List? ?? [certificate];
      final first = (entries.first as Map)['body'] as String;
      anchor = (jsonDecode(first) as Map)['device'] as String;
      await PayrollLanPeer.verifyDelegation(certificate, fields[1] as String, anchor, fields[3] as String);
    }

    return PayrollLanPeer(
      business: fields[1] as String, employee: fields[2] as String, ownerDevice: fields[3] as String,
      mechanicDevice: fields[4] as String, pairKey: base64Url.decode(fields[5] as String),
      trustedOwnerDevice: anchor, ownerCertificate: certificate,
    );
  }
}
