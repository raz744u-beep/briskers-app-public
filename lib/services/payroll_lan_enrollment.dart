import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_owner_authorization.dart';
import 'payroll_lan_identity.dart';
import 'payroll_lan_peer.dart';

/// The signed distribution pins the shop's authorized writer. Local Owner
/// approval activates that device, and pairing persists the same pin.
class PayrollLanEnrollment {
  PayrollLanEnrollment(
    this.identity, {
    String approvedWriter = const String.fromEnvironment(
      'BRISKERS_PAYROLL_WRITER_DEVICE',
    ),
    FlutterSecureStorage storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    ),
  }) : _storage = storage, _approvedWriter = approvedWriter;

  final PayrollLanIdentity identity;
  final FlutterSecureStorage _storage;
  final String _approvedWriter;

  void _assertApproved(String writer) {
    if (_approvedWriter.isEmpty || writer != _approvedWriter) {
      throw StateError('This shop has no matching approved payroll writer.');
    }
  }
  static Future<void> _writes = Future<void>.value();

  String _key(String business, String entry) =>
      'briskers_payroll_lan_v1:${jsonEncode([business, entry])}';

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _pin(String business, String owner) async {
    _assertApproved(owner);
    final key = _key(business, 'writer');
    final current = await _storage.read(key: key);
    if (current != null && current != owner) {
      throw StateError('This shop already has a different payroll device.');
    }
    if (current == null) await _storage.write(key: key, value: owner);
  }

  Future<void> designate(String business, LocalOwnerGrant grant) =>
      _serialize(() async {
        grant.assertValid(business, grant.actorId);
        await _pin(business, identity.deviceId);
        grant.assertValid(business, grant.actorId);
      });

  Future<void> assertWriter(String business, LocalOwnerGrant grant) async {
    _assertApproved(identity.deviceId);
    grant.assertValid(business, grant.actorId);
    if (await _storage.read(key: _key(business, 'writer')) !=
        identity.deviceId) {
      throw StateError('Only the designated Owner device can record payroll.');
    }
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
    final body = jsonEncode([
      'briskers-payroll-pair-v1', business, employee, identity.deviceId,
      mechanicDevice, base64UrlEncode(secret),
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
    await _pin(business, peer.ownerDevice);
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
    return _readPeer(business, 'mechanic', code: entry[1] as String);
  }

  Future<PayrollLanPeer?> ownerPeer(String business, String employee) =>
      _readPeer(business, 'peer:$employee');

  Future<PayrollLanPeer?> _readPeer(String business, String key, {String? code}) async {
    code ??= await _storage.read(key: _key(business, key));
    if (code == null) return null;
    final peer = await _decode(code);
    _assertApproved(peer.ownerDevice);
    final localDevice = key == 'mechanic'
        ? peer.mechanicDevice : peer.ownerDevice;
    if (peer.business != business || localDevice != identity.deviceId ||
        peer.ownerDevice != await _storage.read(key: _key(business, 'writer'))) {
      throw StateError('Payroll pairing does not match this installation.');
    }
    return peer;
  }

  Future<PayrollLanPeer> _decode(String code) async {
    if (code.length > 4096) throw const FormatException('Pairing code too large.');
    final envelope = jsonDecode(code) as List<dynamic>;
    if (envelope.length != 2) throw const FormatException('Invalid pairing code.');
    final body = envelope[0] as String;
    final fields = (jsonDecode(body) as List<dynamic>).cast<String>();
    if (fields.length != 6 || fields[0] != 'briskers-payroll-pair-v1' ||
        !await PayrollLanIdentity.verify(fields[3], body, envelope[1] as String)) {
      throw const FormatException('Invalid payroll pairing signature.');
    }
    return PayrollLanPeer(
      business: fields[1], employee: fields[2], ownerDevice: fields[3],
      mechanicDevice: fields[4], pairKey: base64Url.decode(fields[5]),
    );
  }
}
