import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_owner_authorization.dart';
import 'payroll_lan_identity.dart';

/// The lease follows a reconciled ledger, never a permanently designated phone.
/// Secure storage fences the sender BEFORE it exports an offer. A lost reply
/// cannot re-elect the sender. Copying SQLite cannot copy this capability.
class PayrollPending implements Exception {
  const PayrollPending(this.message);
  final String message;
  @override
  String toString() => message;
}

class PayrollAlreadyRecorded implements Exception {
  const PayrollAlreadyRecorded();
  String get message => 'This payment was already recorded. No second payment was created. See Reports for its receipt.';
  @override String toString() => message;
}

class PayrollOwnerProof {
  PayrollOwnerProof._(this.business, this.device, this._check);
  final String business;
  final String device;
  final Future<void> Function() _check;
  Future<void> validate(String shop, String? localDevice) async {
    if (shop != business || localDevice != device) {
      throw StateError('Payroll authorization belongs to another shop or device.');
    }
    await _check();
  }
}

class PayrollOwnerLease {
  PayrollOwnerLease({required this.identity, required this.business,
    required this.anchor, required this.read, required this.write});
  final PayrollLanIdentity identity;
  final String business;
  // Existing shop identity is only a migration trust anchor, NOT a writer pin.
  final String anchor;
  Future<void> Function(String operation, String snapshot)? storeSnapshot;
  Future<String?> Function(String operation)? loadSnapshot;
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  static final Map<String, Future<void>> _locks = {};
  String get key => 'briskers_owner_payroll_lease_v2:$business';

  static Future<PayrollOwnerLease> platform(String business) async {
    const storage = FlutterSecureStorage(
      iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device));
    return PayrollOwnerLease(
      identity: await PayrollLanIdentity.load(), business: business,
      anchor: const String.fromEnvironment('BRISKERS_PAYROLL_TRUST_ANCHOR',
        defaultValue: 'DnB57MD2pnPv-eoEWaRA_lBwajw0dtsLik5z18jjrAY='),
      read: (key) => storage.read(key: key),
      write: (key, value) => storage.write(key: key, value: value),
    );
  }

  Future<T> serial<T>(Future<T> Function() action) {
    final lockKey = '$key:${identity.deviceId}';
    final next = (_locks[lockKey] ?? Future<void>.value()).then((_) => action());
    _locks[lockKey] = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<Map<String, dynamic>?> state() async {
    final raw = await read(key);
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> _save(Map<String, dynamic> value) => write(key, jsonEncode(value));
  static Future<String> digest(String value) async =>
      base64UrlEncode((await Sha256().hash(utf8.encode(value))).bytes);

  Future<Map<String, dynamic>> _signed(Map<String, dynamic> payload) async {
    final body = jsonEncode(payload);
    return {'body': body, 'signature': await identity.sign(body)};
  }

  /// Explicit existing Owner unlock is reused. Only the previously protected
  /// installation can migrate its existing single-device authority implicitly.
  Future<void> migrate(LocalOwnerGrant grant) => serial(() async {
    grant.assertValid(business, grant.actorId);
    if (await state() != null) return;
    if (await read('$key:epoch') != null) {
      throw const PayrollPending('Payment pending: recover current payroll state from a trusted Owner device.');
    }
    final legacy = 'briskers_payroll_lan_v1:${jsonEncode([business, 'writer'])}';
    if (anchor.isEmpty || identity.deviceId != anchor || ((await read(legacy)) != null && await read(legacy) != anchor)) {
      throw const PayrollPending('Payment pending: connect to the shop payroll ledger over Wi-Fi.');
    }
    final certificate = await _signed({'version': 2, 'business': business,
      'actor': grant.actorId, 'device': identity.deviceId, 'issuer': identity.deviceId,
      'parent': null});
    final lease = await _signed({'version': 2, 'business': business, 'epoch': 0,
      'holder': identity.deviceId, 'actor': grant.actorId, 'operation': 'migration',
      'issuer': identity.deviceId, 'previous': null, 'snapshot': null});
    grant.assertValid(business, grant.actorId);
    await _save({'certificate': certificate, 'lease': lease, 'status': 'active'});
    await write('$key:epoch', '0');
  });

  Future<Map<String, dynamic>> verifyCertificate(Map<String, dynamic> certificate) async {
    final chain = [
      ...?certificate['chain'] as List?,
      {'body': certificate['body'], 'signature': certificate['signature']},
    ];
    Map<String, dynamic>? prior;
    String? parentHash;
    for (final raw in chain) {
      final entry = Map<String, dynamic>.from(raw as Map);
      final body = entry['body'] as String;
      final data = Map<String, dynamic>.from(jsonDecode(body) as Map);
      final issuer = data['issuer'] as String;
      if (data['version'] != 2 || data['business'] != business ||
          !await PayrollLanIdentity.verify(issuer, body, entry['signature'] as String)) {
        throw StateError('Invalid Owner payroll certificate.');
      }
      if (prior == null) {
        if (anchor.isEmpty || issuer != anchor || data['device'] != anchor || data['parent'] != null) {
          throw StateError('Untrusted shop payroll identity.');
        }
      } else if (prior['device'] != issuer || prior['actor'] != data['actor'] || data['parent'] != parentHash) {
        throw StateError('Owner account or trust chain differs.');
      }
      prior = data;
      parentHash = await digest(jsonEncode(entry));
    }
    return prior!;
  }

  Future<Map<String, dynamic>> approveDevice(String device, LocalOwnerGrant grant) =>
      serial(() async {
    grant.assertValid(business, grant.actorId);
    final current = await state();
    if (current == null) throw const PayrollPending('Connect to the existing shop payroll ledger first.');
    final parent = Map<String, dynamic>.from(current['certificate'] as Map);
    final certified = await verifyCertificate(parent);
    if (certified['actor'] != grant.actorId || certified['device'] != identity.deviceId ||
        base64Url.decode(device).length != 32) {
      throw StateError('Only this authenticated Owner can approve an Owner connection.');
    }
    final entry = {'body': parent['body'], 'signature': parent['signature']};
    final certificate = await _signed({'version': 2, 'business': business, 'actor': grant.actorId,
      'device': device, 'issuer': identity.deviceId, 'parent': await digest(jsonEncode(entry))});
    return {...certificate, 'chain': [...?parent['chain'] as List?, entry]};
  });

  Future<void> acceptCertificate(Map<String, dynamic> certificate, LocalOwnerGrant grant) =>
      serial(() async {
    grant.assertValid(business, grant.actorId);
    final data = await verifyCertificate(certificate);
    if (data['actor'] != grant.actorId || data['device'] != identity.deviceId) {
      throw StateError('Owner connection belongs to another account or installation.');
    }
    final current = await state();
    await _save({...?current, 'certificate': certificate,
      if (current == null) 'status': 'pending'});
  });

  Future<Map<String, dynamic>> verifyLease(Map<String, dynamic> lease) async {
    final chain = [...?lease['chain'] as List?,
      {'body': lease['body'], 'signature': lease['signature']}];
    Map<String, dynamic>? previous;
    String? hash;
    for (final raw in chain) {
      final entry = Map<String, dynamic>.from(raw as Map);
      final body = entry['body'] as String;
      final data = Map<String, dynamic>.from(jsonDecode(body) as Map);
      final issuer = data['issuer'] as String;
      if (data['version'] != 2 || data['business'] != business ||
          !await PayrollLanIdentity.verify(issuer, body, entry['signature'] as String)) {
        throw StateError('Invalid payroll ledger lease.');
      }
      if (previous == null) {
        if (anchor.isEmpty || data['epoch'] != 0 || issuer != anchor ||
            data['holder'] != anchor || data['previous'] != null) {
          throw StateError('Untrusted payroll ledger origin.');
        }
      } else if (previous['holder'] != issuer || previous['actor'] != data['actor'] ||
          data['epoch'] != (previous['epoch'] as int) + 1 || data['previous'] != hash) {
        throw StateError('Conflicting payroll lease lineage.');
      }
      previous = data;
      hash = await digest(jsonEncode(entry));
    }
    return previous!;
  }

  Future<PayrollOwnerProof> proof(LocalOwnerGrant grant) async {
    Future<void> check() async {
      grant.assertValid(business, grant.actorId);
      final current = await state();
      if (current == null || current['status'] != 'active' || current['lease'] == null) {
        throw const PayrollPending('Payment pending: the current payroll state must be reconciled over shop Wi-Fi.');
      }
      final lease = await verifyLease(Map<String, dynamic>.from(current['lease'] as Map));
      final certificate = await verifyCertificate(Map<String, dynamic>.from(current['certificate'] as Map));
      final highWater = int.tryParse(await read('$key:epoch') ?? '-1') ?? -1;
      if ((lease['epoch'] as int) < highWater || lease['holder'] != identity.deviceId || lease['actor'] != grant.actorId ||
          certificate['device'] != identity.deviceId || certificate['actor'] != grant.actorId) {
        throw const PayrollPending('Payment pending: reconnect to the current payroll ledger.');
      }
      grant.assertValid(business, grant.actorId);
    }
    await check();
    return PayrollOwnerProof._(business, identity.deviceId, check);
  }

  /// `export` executes after fencing and must read the existing SQLite ledger.
  /// All retries for the same offer return the original durable snapshot.
  Future<Map<String, dynamic>> offer({required String operation,
    required Map<String, dynamic> recipient, required Future<String> Function() export}) => serial(() async {
    final peer = await verifyCertificate(recipient);
    final current = await state();
    if (current == null || current['lease'] == null) {
      throw const PayrollPending('This device has no current payroll state to transfer.');
    }
    final priorOffer = current['offer'];
    if (priorOffer != null && current['operation'] == operation && current['status'] == 'offered') {
      final prior = Map<String, dynamic>.from(priorOffer as Map);
      if (prior['recipient'] != peer['device']) throw StateError('Conflicting lease retry.');
      final snapshot = await _snapshot(operation);
      if (snapshot == null) throw const PayrollPending('The original payroll transfer snapshot is unavailable. Payment remains pending.');
      return {...prior, 'snapshot': snapshot};
    }
    if ((current['used'] as List? ?? []).contains(operation)) {
      throw StateError('This payroll transfer was already superseded.');
    }
    final priorLease = Map<String, dynamic>.from(current['lease'] as Map);
    final prior = await verifyLease(priorLease);
    if (peer['actor'] != prior['actor'] || peer['device'] == identity.deviceId ||
        prior['holder'] != identity.deviceId || current['status'] != 'active') {
      throw const PayrollPending('Payment pending: another Owner device holds the current ledger.');
    }
    await write('$key:epoch', '${(prior['epoch'] as int) + 1}');
    // No clock timeout or disconnected re-election can undo this fence.
    // Fence the legacy release as well if the same installation is restored.
    await write('briskers_payroll_lan_v1:${jsonEncode([business, 'writer'])}', peer['device'] as String);
    await _save({...current, 'status': 'offering', 'operation': operation,
      'recipient': peer['device'], 'used': [...?current['used'] as List?, operation]});
    return _finishOffer(operation, recipient, export);
  });

  Future<Map<String, dynamic>> _finishOffer(String operation,
      Map<String, dynamic> recipient, Future<String> Function() export) async {
    final current = (await state())!;
    final priorLease = Map<String, dynamic>.from(current['lease'] as Map);
    final previous = await verifyLease(priorLease);
    final peer = await verifyCertificate(recipient);
    final snapshot = await _snapshot(operation) ?? await export();
    if (storeSnapshot != null) {
      await storeSnapshot!(operation, snapshot);
    } else {
      await write('$key:snapshot:$operation', snapshot);
    }
    final previousEntry = {'body': priorLease['body'], 'signature': priorLease['signature']};
    final signedLease = await _signed({'version': 2, 'business': business,
      'epoch': (previous['epoch'] as int) + 1, 'holder': peer['device'],
      'actor': peer['actor'], 'operation': operation, 'issuer': identity.deviceId,
      'previous': await digest(jsonEncode(previousEntry)), 'snapshot': await digest(snapshot)});
    final lease = {...signedLease, 'chain': [...?priorLease['chain'] as List?, previousEntry]};
    final offer = {'lease': lease, 'recipient': peer['device']};
    await _save({...current, 'status': 'offered', 'operation': operation, 'offer': offer});
    return {...offer, 'snapshot': snapshot};
  }

  Future<String?> _snapshot(String operation) => loadSnapshot != null
      ? loadSnapshot!(operation) : read('$key:snapshot:$operation');

  Future<Map<String, dynamic>> resumeOffer({required String operation,
    required Map<String, dynamic> recipient, required Future<String> Function() export}) => serial(() async {
    final current = await state();
    final peer = await verifyCertificate(recipient);
    if (current?['status'] != 'offering' || current?['operation'] != operation ||
        current?['recipient'] != peer['device']) {
      throw const PayrollPending('Payroll transfer requires its original request.');
    }
    return _finishOffer(operation, recipient, export);
  });

  Future<void> acceptOffer(Map<String, dynamic> offer, LocalOwnerGrant grant,
      Future<void> Function(String) applySnapshot) => serial(() async {
    grant.assertValid(business, grant.actorId);
    final lease = Map<String, dynamic>.from(offer['lease'] as Map);
    final incoming = await verifyLease(lease);
    final current = await state();
    if (incoming['holder'] != identity.deviceId || incoming['actor'] != grant.actorId ||
        current?['certificate'] == null ||
        await digest(offer['snapshot'] as String) != incoming['snapshot']) {
      throw StateError('Payroll transfer identity or snapshot differs.');
    }
    final highWater = int.tryParse(await read('$key:epoch') ?? '-1') ?? -1;
    if ((incoming['epoch'] as int) < highWater) throw StateError('Superseded payroll lease.');
    final priorRaw = current?['lease'];
    if (priorRaw != null) {
      final prior = await verifyLease(Map<String, dynamic>.from(priorRaw as Map));
      if ((prior['epoch'] as int) >= (incoming['epoch'] as int)) {
        if (jsonEncode(priorRaw) == jsonEncode(lease) && current?['status'] == 'active') return;
        throw StateError('Stale or conflicting payroll ledger transfer.');
      }
    }
    await applySnapshot(offer['snapshot'] as String);
    grant.assertValid(business, grant.actorId);
    await write('$key:epoch', '${incoming['epoch']}');
    await _save({...current!, 'lease': lease, 'status': 'active'});
  });
}
