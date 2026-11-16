import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'payroll_lan_identity.dart';
import 'payroll_lan_peer.dart';

/// One authenticated connection between an Owner and an assigned mechanic.
/// The receiver applies the change and saves its replay receipt in one
/// SQLite transaction. Both callbacks must use this same database.
class PayrollLanDelivery {
  PayrollLanDelivery({
    required this.database,
    required this.identity,
    required this.peer,
    required this.apply,
    required this.assertEnrollment,
    this.onAcknowledged,
    this.onOwnerCertificate,
  }) {
    if (identity.deviceId != peer.ownerDevice &&
        identity.deviceId != peer.mechanicDevice) {
      throw ArgumentError('The local device is not in this payroll link.');
    }
  }

  final BriskersLocalDatabase database;
  final PayrollLanIdentity identity;
  final PayrollLanPeer peer;
  final Future<void> Function(PayrollLanOperation, Map<String, dynamic>) apply;
  final void Function() assertEnrollment;
  final Future<void> Function(PayrollLanOperation, String)? onAcknowledged;
  final Future<void> Function(Map<String, dynamic>)? onOwnerCertificate;
  Future<void>? _ready;
  HttpServer? _listener;
  String get _remote =>
      identity.deviceId == peer.ownerDevice ? peer.mechanicDevice : peer.ownerDevice;
  static const _path = '/briskers/payroll-lan/v1';
  static const _timeout = Duration(seconds: 10);

  Future<void> prepare() => _ready ??= database.transaction(() async {
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS payroll_lan_delivery_v1 (
        business TEXT NOT NULL, local_device TEXT NOT NULL,
        peer_device TEXT NOT NULL, operation TEXT NOT NULL,
        direction TEXT NOT NULL, body TEXT NOT NULL, digest TEXT NOT NULL,
        acknowledged INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(business, local_device, peer_device, direction, operation)
      )
    ''');
    if (identity.deviceId == peer.mechanicDevice) {
      final pending = await database.customSelect("SELECT * FROM payroll_lan_delivery_v1 WHERE business=? AND local_device=? AND direction='out' AND acknowledged=0 AND peer_device<>?",
        variables: [peer.business, identity.deviceId, _remote].map(Variable<String>.new).toList()).get();
      for (final row in pending) {
        final change = jsonDecode(row.read<String>('body')) as Map;
        if (change['kind'] != 'progress' || (change['payload'] as Map)['employee'] != peer.employee) continue;
        await database.customStatement('INSERT OR IGNORE INTO payroll_lan_delivery_v1 VALUES(?,?,?,?,?,?,?,0)',
          [peer.business, identity.deviceId, _remote, row.data['operation'], 'out', row.data['body'], row.data['digest']]);
      }
    }
  });

  List<String> _scope(String direction, String operation) =>
      [peer.business, identity.deviceId, _remote, direction, operation];

  Future<Map<String, dynamic>?> _find(String direction, String operation) async {
    final row = await database.customSelect(
      'SELECT * FROM payroll_lan_delivery_v1 '
      'WHERE business=? AND local_device=? AND peer_device=? AND direction=? AND operation=?',
      variables: _scope(direction, operation).map(Variable<String>.new).toList(),
    ).getSingleOrNull();
    return row?.data;
  }

  Future<String> _digest(String body) async =>
      base64UrlEncode((await Sha256().hash(utf8.encode(body))).bytes);

  Future<void> enqueue({
    required String operationId,
    required PayrollLanOperation kind,
    required Map<String, dynamic> payload,
  }) async {
    assertEnrollment();
    if (operationId.isEmpty || operationId.length > 128) {
      throw ArgumentError('Invalid payroll operation ID.');
    }
    peer.authorize(sender: identity.deviceId, recipient: _remote,
      operation: kind, employee: payload['employee'] as String);
    final body = jsonEncode({'id': operationId, 'kind': kind.name, 'payload': payload});
    if (utf8.encode(body).length > 24000) {
      throw const FormatException('Payroll operation too large.');
    }
    await prepare();
    await database.transaction(() async {
      final prior = await _find('out', operationId);
      if (prior != null && prior['body'] != body) {
        throw StateError('Conflicting payroll operation replay.');
      }
      if (prior == null) {
        await database.customStatement(
          'INSERT INTO payroll_lan_delivery_v1(business,local_device,peer_device,direction,operation,body,digest,acknowledged) VALUES(?,?,?,?,?,?,?,0)',
          [..._scope('out', operationId), body, await _digest(body)],
        );
      }
      assertEnrollment();
    });
  }

  Future<int> listen(InternetAddress address, {int port = 0}) async {
    assertEnrollment();
    if (_listener != null) throw StateError('Payroll listener already started.');
    await prepare();
    final server = await HttpServer.bind(address, port);
    _listener = server;
    server.listen((request) => unawaited(_receive(request)));
    return server.port;
  }

  Future<void> close() async {
    final listener = _listener;
    _listener = null;
    if (listener != null) await listener.close(force: true);
  }

  Future<String> _read(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream.timeout(_timeout)) {
      if (bytes.length + chunk.length > 90000) {
        throw const FormatException('Payroll request too large.');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Future<void> _receive(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'POST' || request.uri.path != _path) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      assertEnrollment();
      var effective = peer;
      var remote = _remote;
      final header = request.headers.value('x-briskers-owner-certificate');
      if (header != null && identity.deviceId == peer.mechanicDevice) {
        if (header.length > 32000) throw const FormatException('Owner certificate too large.');
        effective = await peer.delegatedOwner(Map<String, dynamic>.from(jsonDecode(utf8.decode(base64Url.decode(header))) as Map));
        remote = effective.ownerDevice;
      }
      final envelope = await _read(request).timeout(_timeout);
      final opened = identity.deviceId == peer.ownerDevice
          ? await peer.openMechanic(recipient: identity, envelope: envelope)
          : await effective.open(sender: remote, recipient: identity, envelope: envelope);
      final body = opened['change'];
      if (body is! String) throw const FormatException('Payroll change missing.');
      final change = Map<String, dynamic>.from(jsonDecode(body) as Map);
      final id = change['id'] as String;
      if (id.isEmpty || id.length > 128) throw const FormatException('Bad payroll ID.');
      final kind = PayrollLanOperation.values.byName(change['kind'] as String);
      final payload = Map<String, dynamic>.from(change['payload'] as Map);
      effective.authorize(sender: remote, recipient: identity.deviceId,
        operation: kind, employee: payload['employee'] as String);
      final digest = await _digest(body);
      await database.transaction(() async {
        assertEnrollment();
        final prior = await _find('in', id);
        if (prior == null) {
          await apply(kind, payload);
          await database.customStatement(
            'INSERT INTO payroll_lan_delivery_v1(business,local_device,peer_device,direction,operation,body,digest,acknowledged) VALUES(?,?,?,?,?,?,?,1)',
            [..._scope('in', id), body, digest],
          );
        } else if (prior['body'] != body) {
          throw StateError('Conflicting payroll operation replay.');
        }
        assertEnrollment();
      });
      if (identity.deviceId == peer.mechanicDevice && effective.ownerCertificate != null) {
        await onOwnerCertificate?.call(effective.ownerCertificate!);
      }
      if (identity.deviceId == peer.ownerDevice && peer.ownerCertificate != null) {
        response.headers.set('x-briskers-owner-certificate', base64UrlEncode(utf8.encode(jsonEncode(peer.ownerCertificate))));
      }
      response.write(await effective.seal(identity, remote, {'ack': id, 'digest': digest}));
    } catch (_) {
      response.statusCode = HttpStatus.conflict;
    } finally {
      try { await response.close(); } catch (_) { /* Persisted receipts survive lost replies. */ }
    }
  }

  Future<int> deliver(InternetAddress address, int port) async {
    assertEnrollment();
    final bytes = address.rawAddress;
    if (address.type != InternetAddressType.IPv4 ||
        !(address.isLoopback || bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168))) {
      throw ArgumentError('Payroll delivery requires a private shop LAN address.');
    }
    await prepare();
    if (identity.deviceId == peer.ownerDevice && peer.ownerCertificate != null) {
      await enqueue(operationId: 'owner-route-${await _digest(jsonEncode(peer.ownerCertificate))}',
        kind: PayrollLanOperation.ownerRoute,
        payload: {'employee': peer.employee, 'owner': peer.ownerDevice});
    }
    final pending = await database.customSelect(
      "SELECT * FROM payroll_lan_delivery_v1 WHERE business=? AND local_device=? "
      "AND peer_device=? AND direction='out' AND acknowledged=0 ORDER BY rowid LIMIT 50",
      variables: [peer.business, identity.deviceId, _remote].map(Variable<String>.new).toList(),
    ).get();
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      for (final row in pending) {
        assertEnrollment();
        final id = row.read<String>('operation');
        final digest = row.read<String>('digest');
        final request = await client.postUrl(Uri(
          scheme: 'http', host: address.address, port: port, path: _path,
        )).timeout(_timeout);
        request.followRedirects = false;
        if (identity.deviceId == peer.ownerDevice && peer.ownerCertificate != null) {
          request.headers.set('x-briskers-owner-certificate', base64UrlEncode(utf8.encode(jsonEncode(peer.ownerCertificate))));
        }
        request.write(await peer.seal(identity, _remote, {'change': row.read<String>('body')}));
        final response = await request.close().timeout(_timeout);
        if (response.statusCode != HttpStatus.ok) {
          throw StateError('Payroll peer did not acknowledge the change.');
        }
        var acknowledgmentPeer = peer;
        final header = response.headers.value('x-briskers-owner-certificate');
        if (header != null && identity.deviceId == peer.mechanicDevice) {
          if (header.length > 32000) throw const FormatException('Owner certificate too large.');
          acknowledgmentPeer = await peer.delegatedOwner(Map<String, dynamic>.from(jsonDecode(utf8.decode(base64Url.decode(header))) as Map));
        }
        final ack = await acknowledgmentPeer.open(
          sender: identity.deviceId == peer.mechanicDevice ? acknowledgmentPeer.ownerDevice : _remote,
          recipient: identity, envelope: await _read(response).timeout(_timeout));
        if (ack['ack'] != id || ack['digest'] != digest) {
          throw StateError('Payroll acknowledgment does not match the change.');
        }
        assertEnrollment();
        if (identity.deviceId == peer.mechanicDevice && acknowledgmentPeer.ownerCertificate != null) {
          await onOwnerCertificate?.call(acknowledgmentPeer.ownerCertificate!);
        }
        await database.transaction(() async {
          assertEnrollment();
          await database.customStatement(
            'UPDATE payroll_lan_delivery_v1 SET acknowledged=1 '
            'WHERE business=? AND local_device=? AND peer_device=? AND direction=? AND operation=? AND digest=?',
            [..._scope('out', id), digest],
          );
          final body = jsonDecode(row.read<String>('body')) as Map<String, dynamic>;
          final kind = PayrollLanOperation.values.byName(body['kind'] as String);
          if (identity.deviceId == peer.mechanicDevice && kind == PayrollLanOperation.progress) {
            await database.customStatement("UPDATE payroll_lan_delivery_v1 SET acknowledged=1 WHERE business=? AND local_device=? AND direction='out' AND operation=? AND digest=?",
              [peer.business, identity.deviceId, id, digest]);
          }
          await onAcknowledged?.call(kind, id);
          assertEnrollment();
        });
      }
      return pending.length;
    } finally {
      client.close(force: true);
    }
  }
}
