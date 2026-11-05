import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'payroll_lan_identity.dart';

enum PayrollLanOperation { assignment, progress, payment }

/// One Owner-approved mechanic link. The transport key is per peer and must
/// be provisioned through the pairing channel, never through payroll SQLite.
class PayrollLanPeer {
  PayrollLanPeer({
    required this.business,
    required this.ownerDevice,
    required this.mechanicDevice,
    required this.employee,
    required List<int> pairKey,
  }) : _key = SecretKey(List<int>.unmodifiable(pairKey)) {
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
    _checkRoute(sender, recipient.deviceId);
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
      aad: _aad(sender, recipient.deviceId),
    );
    final signed = jsonDecode(utf8.decode(plaintext));
    if (signed is! List || signed.length != 2 ||
        signed[0] is! String || signed[1] is! String) {
      throw const FormatException('Invalid signed payroll message.');
    }
    final body = signed[0] as String;
    if (!await PayrollLanIdentity.verify(
      sender, jsonEncode([_aad(sender, recipient.deviceId), body]), signed[1] as String,
    )) {
      throw StateError('Payroll device signature is invalid.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid payroll message.');
    }
    return decoded;
  }

  void _checkRoute(String sender, String recipient) {
    if (!((sender == ownerDevice && recipient == mechanicDevice) ||
        (sender == mechanicDevice && recipient == ownerDevice))) {
      throw StateError('Unknown payroll device.');
    }
  }
}
