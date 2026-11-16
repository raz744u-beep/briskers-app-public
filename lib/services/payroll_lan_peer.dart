import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'payroll_lan_identity.dart';

enum PayrollLanOperation { assignment, progress, payment, ownerRoute }

/// One Owner-approved mechanic link. The transport key is per peer and must
/// be provisioned through the pairing channel, never through payroll SQLite.
class PayrollLanPeer {
  PayrollLanPeer({
    required this.business,
    required this.ownerDevice,
    required this.mechanicDevice,
    required this.employee,
    required List<int> pairKey,
    this.ownerCertificate,
    String? trustedOwnerDevice,
  }) : trustedOwnerDevice = trustedOwnerDevice ?? ownerDevice, _key = SecretKey(List<int>.unmodifiable(pairKey)) {
    if (pairKey.length != 32 || business.isEmpty || employee.isEmpty ||
        ownerDevice.isEmpty || mechanicDevice.isEmpty || ownerDevice == mechanicDevice) {
      throw ArgumentError('Invalid payroll peer link.');
    }
  }

  final String business;
  final String ownerDevice;
  final String mechanicDevice;
  final String employee;
  final SecretKey _key;
  final String trustedOwnerDevice;
  final Map<String, dynamic>? ownerCertificate;
  static final _cipher = AesGcm.with256bits();
  static const maxBytes = 65536;

  void authorize({
    required String sender,
    required String recipient,
    required PayrollLanOperation operation,
    required String employee,
  }) {
    final fromOwner = operation != PayrollLanOperation.progress;
    if (employee != this.employee ||
        sender != (fromOwner ? ownerDevice : mechanicDevice) ||
        recipient != (fromOwner ? mechanicDevice : ownerDevice)) {
      throw StateError('Payroll peer is not authorized for this operation.');
    }
  }

  List<int> _aad(String sender, String recipient) =>
      utf8.encode(jsonEncode(['briskers-payroll-lan-v1', business, employee, sender, recipient]));

  Future<String> seal(
    PayrollLanIdentity sender, String recipient, Map<String, dynamic> message,
  ) async {
    _checkRoute(sender.deviceId, recipient);
    final body = jsonEncode(message);
    final signed = jsonEncode([body, await sender.sign(
      jsonEncode([_aad(sender.deviceId, recipient), body]),
    )]);
    final bytes = utf8.encode(signed);
    if (bytes.length > maxBytes) throw const FormatException('Payroll message too large.');
    final box = await _cipher.encrypt(bytes, secretKey: _key, aad: _aad(sender.deviceId, recipient));
    return base64UrlEncode(box.concatenation());
  }

  Future<Map<String, dynamic>> open({
    required String sender,
    required PayrollLanIdentity recipient,
    required String envelope,
  }) async {
    return _open(sender, recipient.deviceId, envelope);
  }

  Future<Map<String, dynamic>> _open(String sender, String recipient, String envelope) async {
    _checkRoute(sender, recipient);
    if (envelope.length > (maxBytes + 28) * 2) {
      throw const FormatException('Payroll envelope too large.');
    }
    final bytes = base64Url.decode(envelope);
    if (bytes.length < 28 || bytes.length > maxBytes + 28) {
      throw const FormatException('Invalid payroll envelope.');
    }
    final plaintext = await _cipher.decrypt(
      SecretBox.fromConcatenation(bytes, nonceLength: 12, macLength: 16),
      secretKey: _key,
      aad: _aad(sender, recipient),
    );
    final signed = jsonDecode(utf8.decode(plaintext));
    if (signed is! List || signed.length != 2 ||
        signed[0] is! String || signed[1] is! String) {
      throw const FormatException('Invalid signed payroll message.');
    }
    final body = signed[0] as String;
    if (!await PayrollLanIdentity.verify(
      sender, jsonEncode([_aad(sender, recipient), body]), signed[1] as String,
    )) {
      throw StateError('Payroll device signature is invalid.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid payroll message.');
    }
    return decoded;
  }

  static Future<void> verifyDelegation(Map<String, dynamic> certificate,
      String business, String anchor, String device) async {
    final entries = [...?certificate['chain'] as List?,
      {'body': certificate['body'], 'signature': certificate['signature']}];
    bool trusted = false;
    String previousDevice = '', previousHash = '';
    Object? actor;
    for (final raw in entries) {
      final entry = Map<String, dynamic>.from(raw as Map);
      final body = entry['body'] as String;
      final data = jsonDecode(body) as Map;
      if (data['version'] != 2 || data['business'] != business) throw StateError('Wrong shop delegation.');
      if (!trusted && data['device'] == anchor) {
        trusted = true;
        actor = data['actor'];
      } else if (trusted) {
        if (data['issuer'] != previousDevice || data['parent'] != previousHash ||
            data['actor'] != actor || !await PayrollLanIdentity.verify(
              previousDevice, body, entry['signature'] as String)) {
          throw StateError('Invalid Owner device delegation.');
        }
      }
      if (trusted) {
        previousDevice = data['device'] as String;
        previousHash = base64UrlEncode((await Sha256().hash(utf8.encode(jsonEncode(entry)))).bytes);
      }
    }
    if (!trusted || previousDevice != device) throw StateError('Owner device is not approved by this mechanic’s Owner.');
  }

  Future<PayrollLanPeer> delegatedOwner(Map<String, dynamic> certificate) async {
    final data = jsonDecode(certificate['body'] as String) as Map;
    final device = data['device'] as String;
    await verifyDelegation(certificate, business, trustedOwnerDevice, device);
    return PayrollLanPeer(business: business, employee: employee,
      ownerDevice: device, mechanicDevice: mechanicDevice,
      pairKey: await _key.extractBytes(), ownerCertificate: certificate,
      trustedOwnerDevice: trustedOwnerDevice);
  }

  /// Progress queued before a route update remains readable by an Owner who
  /// was approved by the originally paired Owner. No signing seed is shared.
  Future<Map<String, dynamic>> openMechanic({required PayrollLanIdentity recipient,
      required String envelope}) async {
    try { return await open(sender: mechanicDevice, recipient: recipient, envelope: envelope); }
    catch (_) {
      if (ownerCertificate == null || recipient.deviceId != ownerDevice) rethrow;
      await verifyDelegation(ownerCertificate!, business, trustedOwnerDevice, ownerDevice);
      final original = PayrollLanPeer(business: business, employee: employee,
        ownerDevice: trustedOwnerDevice, mechanicDevice: mechanicDevice, pairKey: await _key.extractBytes());
      return original._open(mechanicDevice, trustedOwnerDevice, envelope);
    }
  }

  void _checkRoute(String sender, String recipient) {
    if (!((sender == ownerDevice && recipient == mechanicDevice) ||
        (sender == mechanicDevice && recipient == ownerDevice))) {
      throw StateError('Unknown payroll device.');
    }
  }
}
