import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'local_owner_authorization.dart';
import 'payroll_lan_peer.dart';
import 'payroll_lan_identity.dart';
import 'payroll_lan_enrollment.dart';
import 'local_payroll_repository.dart';
import 'payroll_owner_lease.dart';
import 'payroll_owner_ledger.dart';

/// Owner connections reuse LAN signing/encryption and the existing Owner unlock.
/// No shared Owner code, cloud login or permanent payment phone is involved.
class PayrollOwnerLan {
  PayrollOwnerLan({required this.lease, required this.database,
    required this.approve, required this.actor, this.assertAccount, this.onResponse, PayrollLanEnrollment? enrollment}) {
    this.enrollment = enrollment ?? PayrollLanEnrollment(lease.identity);
    lease.storeSnapshot = (operation, snapshot) async {
      await database.customStatement('INSERT OR IGNORE INTO payroll_owner_snapshot_v2 VALUES(?,?,?)',
        [lease.business, operation, snapshot]);
      final rows = await database.customSelect('SELECT body FROM payroll_owner_snapshot_v2 WHERE business_id=? AND operation=?',
        variables: [lease.business, operation].map(Variable<String>.new).toList()).get();
      if (rows.single.data['body'] != snapshot) throw StateError('Conflicting payroll snapshot retry.');
    };
    lease.loadSnapshot = (operation) async {
      final rows = await database.customSelect('SELECT body FROM payroll_owner_snapshot_v2 WHERE business_id=? AND operation=?',
        variables: [lease.business, operation].map(Variable<String>.new).toList()).get();
      return rows.firstOrNull?.read<String>('body');
    };
  }
  final PayrollOwnerLease lease;
  final BriskersLocalDatabase database;
  final String actor;
  late final PayrollLanEnrollment enrollment;
  final void Function()? assertAccount;
  Future<void> Function(String command)? onResponse;
  Future<LocalOwnerGrant?> Function(String device) approve;
  late final ledger = PayrollOwnerLedger(database, lease.business);
  HttpServer? _server;
  Object? lastFailure;
  Future<void>? _ackWork;
  int get port => _server?.port ?? 0;
  static final _exchange = X25519();
  static final _cipher = AesGcm.with256bits();
  static const path = '/briskers/owner-payroll/v2';
  String _peerKey(String device) => 'briskers_owner_peer_v2:${lease.business}:$device';
  String get _peersKey => 'briskers_owner_peers_v2:${lease.business}';

  Future<void> prepare() async {
    await ledger.prepare();
    await database.customStatement('CREATE TABLE IF NOT EXISTS payroll_owner_acquisitions_v2 '
      '(business TEXT NOT NULL,payment TEXT NOT NULL,operation TEXT NOT NULL,PRIMARY KEY(business,payment))');
    await database.customStatement('CREATE TABLE IF NOT EXISTS payroll_owner_acks_v2 '
      '(business TEXT NOT NULL,peer TEXT NOT NULL,operation TEXT NOT NULL,direction TEXT NOT NULL,'
      'digest TEXT NOT NULL,acknowledged INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(business,peer,operation,direction))');
    await database.customStatement('CREATE TABLE IF NOT EXISTS payroll_owner_join_replays_v2 '
      '(business TEXT NOT NULL,device TEXT NOT NULL,nonce TEXT NOT NULL,body TEXT NOT NULL,response TEXT NOT NULL,'
      'PRIMARY KEY(business,device,nonce))');
    await database.customStatement('CREATE TABLE IF NOT EXISTS payroll_owner_proof_required_v2 '
      '(business_id TEXT PRIMARY KEY NOT NULL)');
    await database.customStatement('INSERT OR IGNORE INTO payroll_owner_proof_required_v2 VALUES(?)', [lease.business]);
    await database.customStatement('CREATE TABLE IF NOT EXISTS payroll_owner_snapshot_v2 '
      '(business_id TEXT NOT NULL,operation TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(business_id,operation))');
    await database.customStatement('CREATE TABLE IF NOT EXISTS payroll_owner_pages_v2 '
      '(business TEXT NOT NULL,peer TEXT NOT NULL,operation TEXT NOT NULL,'
      'direction TEXT NOT NULL,page INTEGER NOT NULL,body TEXT NOT NULL,'
      'PRIMARY KEY(business,peer,operation,direction,page))');
  }
  Future<int> listen(InternetAddress address, {int port = 45873}) async {
    if (_server != null) return this.port;
    await prepare();
    final server = await HttpServer.bind(address, port);
    _server = server;
    server.listen(_receive);
    return server.port;
  }
  Future<void> close() async { await _server?.close(force: true); _server = null; await _ackWork; }
  Future<Map<String, dynamic>?> _peer(String device) async {
    final raw = await lease.read(_peerKey(device));
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }
  PayrollLanPeer _crypto(Map<String, dynamic> peer) => PayrollLanPeer(
    business: lease.business, employee: 'owner:$actor',
    ownerDevice: peer['server'] as String, mechanicDevice: peer['client'] as String,
    pairKey: base64Url.decode(peer['secret'] as String));
  Future<void> _remember(String device, Map<String, dynamic> peer) async {
    await lease.write(_peerKey(device), jsonEncode(peer));
    final raw = await lease.read(_peersKey);
    final ids = raw == null ? <String>[] : (jsonDecode(raw) as List).cast<String>();
    if (!ids.contains(device)) ids.add(device);
    await lease.write(_peersKey, jsonEncode(ids));
  }
  static Uri endpoint(String value) {
    final uri = Uri.parse(value.contains('://') ? value : 'http://$value');
    final ip = InternetAddress.tryParse(uri.host);
    if (uri.scheme != 'http' || uri.userInfo.isNotEmpty || ip == null ||
        ip.type != InternetAddressType.IPv4 || uri.port < 1 || uri.port > 65535) {
      throw const PayrollPending('Use the shop Wi-Fi device address.');
    }
    final b = ip.rawAddress;
    if (!(ip.isLoopback || b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168))) { throw const PayrollPending('Payroll requires a private shop Wi-Fi connection.'); }
    return uri.replace(path: path, query: null, fragment: null);
  }
  Future<String> _read(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final part in stream.timeout(const Duration(seconds: 20))) {
      bytes.addAll(part);
      if (bytes.length > 150000) throw const FormatException('Payroll message too large.');
    }
    return utf8.decode(bytes);
  }
  Future<String> _post(Uri uri, String body, {String? device}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      if (device != null) request.headers.set('x-briskers-device', device);
      request.write(body);
      final response = await request.close().timeout(const Duration(seconds: 20));
      final result = await _read(response);
      if (response.statusCode != 200) throw const PayrollPending('Payment pending: the shop payroll device could not verify this request. Reconnect and retry.');
      return result;
    } finally { client.close(force: true); }
  }

  Future<void> connect(String address, LocalOwnerGrant grant) async {
    grant.assertValid(lease.business, actor);
    if (port == 0) await listen(InternetAddress.anyIPv4);
    final target = endpoint(address);
    final ephemeral = await _exchange.newKeyPair();
    final nonce = base64UrlEncode(List.generate(24, (_) => Random.secure().nextInt(256)));
    final current = await lease.state();
    final body = jsonEncode({'business': lease.business, 'actor': actor,
      'device': lease.identity.deviceId, 'exchange': base64UrlEncode((await ephemeral.extractPublicKey()).bytes),
      'nonce': nonce, 'port': port, 'time': DateTime.now().millisecondsSinceEpoch,
      'certificate': current?['certificate']});
    final response = Map<String, dynamic>.from(jsonDecode(await _post(
      target.replace(path: '$path/join'), jsonEncode({'body': body,
        'signature': await lease.identity.sign(body)}))) as Map);
    final replyBody = response['body'] as String;
    final reply = Map<String, dynamic>.from(jsonDecode(replyBody) as Map);
    final serverCertificate = Map<String, dynamic>.from(reply['server_certificate'] as Map);
    final server = await lease.verifyCertificate(serverCertificate);
    if (server['actor'] != actor || reply['nonce'] != nonce ||
        !await PayrollLanIdentity.verify(server['device'] as String, replyBody, response['signature'] as String)) {
      throw StateError('Shop Owner connection could not be verified.');
    }
    final shared = await _exchange.sharedSecretKey(keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(base64Url.decode(reply['exchange'] as String), type: KeyPairType.x25519));
    final secret = await _cipher.decrypt(SecretBox.fromConcatenation(
      base64Url.decode(reply['secret'] as String), nonceLength: 12, macLength: 16),
      secretKey: shared, aad: utf8.encode(nonce));
    final certificate = Map<String, dynamic>.from(reply['certificate'] as Map);
    await lease.acceptCertificate(certificate, grant);
    await _remember(server['device'] as String, {
      'server': server['device'], 'client': lease.identity.deviceId,
      'secret': base64UrlEncode(secret), 'endpoint': target.toString(),
      'certificate': serverCertificate});
    grant.assertValid(lease.business, actor);
    await _syncMechanicLinks((await _peer(server['device'] as String))!, grant);
    await refresh(grant);
  }

  Future<void> _receive(HttpRequest request) async {
    try {
      assertAccount?.call();
      if (request.method != 'POST') throw StateError('Invalid payroll request.');
      final raw = await _read(request);
      if (request.uri.path == '$path/join') {
        final signed = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final body = signed['body'] as String;
        final data = Map<String, dynamic>.from(jsonDecode(body) as Map);
        final device = data['device'] as String;
        final time = data['time'] as int;
        if (data['business'] != lease.business || data['actor'] != actor || device == lease.identity.deviceId ||
            (DateTime.now().millisecondsSinceEpoch - time).abs() > 300000 ||
            !await PayrollLanIdentity.verify(device, body, signed['signature'] as String)) {
          throw StateError('Invalid Owner connection.');
        }
        final replay = await database.customSelect('SELECT body,response FROM payroll_owner_join_replays_v2 '
          'WHERE business=? AND device=? AND nonce=?',
          variables: [lease.business, device, data['nonce'] as String].map(Variable<String>.new).toList()).get();
        if (replay.isNotEmpty) {
          if (replay.single.data['body'] != body) throw StateError('Conflicting Owner connection retry.');
          request.response.write(replay.single.data['response']);
          return;
        }
        var certificate = data['certificate'] as Map? ?? (await _peer(device))?['certificate'] as Map?;
        if (certificate != null) {
          final approved = await lease.verifyCertificate(Map<String, dynamic>.from(certificate));
          if (approved['device'] != device || approved['actor'] != actor) throw StateError('Owner identity differs.');
        } else {
          final grant = await approve(device);
          if (grant == null) throw StateError('Owner connection was not approved.');
          certificate = await lease.approveDevice(device, grant);
        }
        final current = await lease.state();
        if (current?['certificate'] == null) throw StateError('Connect to the existing shop ledger first.');
        final ephemeral = await _exchange.newKeyPair();
        final shared = await _exchange.sharedSecretKey(keyPair: ephemeral,
          remotePublicKey: SimplePublicKey(base64Url.decode(data['exchange'] as String), type: KeyPairType.x25519));
        final secret = List.generate(32, (_) => Random.secure().nextInt(256));
        final nonce = data['nonce'] as String;
        final encrypted = await _cipher.encrypt(secret, secretKey: shared, aad: utf8.encode(nonce));
        final remoteAddress = request.connectionInfo!.remoteAddress.address;
        final remotePort = data['port'] as int;
        final remote = endpoint('$remoteAddress:$remotePort');
        await _remember(device, {'server': lease.identity.deviceId, 'client': device,
          'secret': base64UrlEncode(secret), 'endpoint': remote.toString(), 'certificate': certificate});
        final reply = jsonEncode({'nonce': nonce, 'certificate': certificate,
          'server_certificate': current!['certificate'],
          'exchange': base64UrlEncode((await ephemeral.extractPublicKey()).bytes),
          'secret': base64UrlEncode(encrypted.concatenation())});
        final response = jsonEncode({'body': reply, 'signature': await lease.identity.sign(reply)});
        await database.customStatement('INSERT INTO payroll_owner_join_replays_v2 VALUES(?,?,?,?,?)',
          [lease.business, device, nonce, body, response]);
        request.response.write(response);
      } else if (request.uri.path == '$path/call') {
        final device = request.headers.value('x-briskers-device') ?? '';
        final peer = await _peer(device);
        if (peer == null) throw StateError('Unknown Owner connection.');
        final certificate = await lease.verifyCertificate(Map<String, dynamic>.from(peer['certificate'] as Map));
        if (certificate['device'] != device || certificate['actor'] != actor) throw StateError('Owner connection changed.');
        final crypto = _crypto(peer);
        final message = await crypto.open(sender: device, recipient: lease.identity, envelope: raw);
        if ((DateTime.now().millisecondsSinceEpoch - (message['time'] as int)).abs() > 300000) {
          throw StateError('Owner payroll request expired.');
        }
        final result = await _handle(device, message, peer);
        await onResponse?.call(message['command'] as String);
        request.response.write(await crypto.seal(lease.identity, device, result));
      } else { request.response.statusCode = 404; }
    } catch (error) { lastFailure = error; request.response.statusCode = 409; }
    finally { try { await request.response.close(); } catch (_) { /* Lost replies retry durably. */ } }
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> peer, Map<String, dynamic> message) async {
    final other = peer['server'] == lease.identity.deviceId ? peer['client'] : peer['server'];
    final crypto = _crypto(peer);
    return crypto.open(sender: other as String, recipient: lease.identity,
      envelope: await _post(endpoint(peer['endpoint'] as String).replace(path: '$path/call'),
        await crypto.seal(lease.identity, other, {...message, 'time': DateTime.now().millisecondsSinceEpoch}), device: lease.identity.deviceId));
  }
  Future<void> _page(String device, String op, String direction, int index, String body) async {
    final rows = await database.customSelect('SELECT body FROM payroll_owner_pages_v2 '
      'WHERE business=? AND peer=? AND operation=? AND direction=? AND page=?',
      variables: [Variable(lease.business), Variable(device), Variable(op), Variable(direction), Variable(index)]).get();
    if (rows.isNotEmpty && rows.single.data['body'] != body) throw StateError('Conflicting payroll page retry.');
    await database.customStatement('INSERT OR IGNORE INTO payroll_owner_pages_v2 VALUES(?,?,?,?,?,?)',
      [lease.business, device, op, direction, index, body]);
  }
  Future<String> _assemble(String device, String op, String direction, int count) async {
    if (count < 1 || count > 4096) throw StateError('Invalid payroll snapshot size.');
    final rows = await database.customSelect('SELECT page,body FROM payroll_owner_pages_v2 '
      'WHERE business=? AND peer=? AND operation=? AND direction=? ORDER BY page',
      variables: [lease.business, device, op, direction].map(Variable<String>.new).toList()).get();
    if (rows.length != count || rows.indexed.any((r) => r.$1 != r.$2.read<int>('page'))) throw StateError('Incomplete payroll snapshot.');
    return utf8.decode(base64Url.decode(rows.map((r) => r.read<String>('body')).join()));
  }
  List<String> _chunks(String body) {
    final encoded = base64UrlEncode(utf8.encode(body));
    return [for (var i = 0; i < encoded.length; i += 16000)
      encoded.substring(i, min(i + 16000, encoded.length))];
  }
  Future<Map<String, dynamic>> _publish(String device, String op, String body) async {
    final chunks = _chunks(body);
    return database.transaction(() async {
      for (var i = 0; i < chunks.length; i++) { await _page(device, op, 'out', i, chunks[i]); }
      return {'count': chunks.length, 'digest': await PayrollOwnerLease.digest(body)};
    });
  }

  Future<Map<String, dynamic>> _handle(String device, Map<String, dynamic> message, Map<String, dynamic> peer) async {
    final op = message['operation'] as String;
    if (op.isEmpty || op.length > 128) throw StateError('Invalid payroll request identity.');
    final current = await lease.state();
    switch (message['command']) {
      case 'links':
        final employees = await LocalPayrollRepository(database, business: lease.business, owner: true).employees();
        return {'employees': [for (final row in employees) row['id']]};
      case 'link':
        final code = await enrollment.exportOwnerLink(lease.business, message['employee'] as String, () { assertAccount?.call(); });
        return {'code': code};
      case 'received':
        final pages = await database.customSelect("SELECT count(*) AS n FROM payroll_owner_pages_v2 WHERE business=? AND peer=? AND operation=? AND direction='out'",
          variables: [lease.business, device, op].map(Variable<String>.new).toList()).getSingle();
        final offer = jsonDecode(await _assemble(device, op, 'out', pages.read<int>('n'))) as Map;
        final digest = await PayrollOwnerLease.digest(jsonEncode(offer['lease']));
        if (offer['recipient'] != device || digest != message['digest']) throw StateError('Invalid payroll acknowledgment.');
        await _ack(device, op, 'in', digest, 1);
        return {'ack': op, 'digest': digest};
      case 'upload':
        final index = message['page'] as int;
        final chunk = message['body'] as String;
        if (index < 0 || index > 4095 || chunk.length > 16000) throw StateError('Invalid payroll page.');
        await _page(device, op, 'in', index, chunk);
        return {'ok': true};
      case 'page':
        final rows = await database.customSelect('SELECT body FROM payroll_owner_pages_v2 '
          "WHERE business=? AND peer=? AND operation=? AND direction='out' AND page=?",
          variables: [Variable(lease.business), Variable(device), Variable(op), Variable(message['page'] as int)]).get();
        return {'body': rows.single.data['body']};
      case 'tasks':
        return _publish(device, op, await ledger.export());
      case 'read':
        if (current?['status'] != 'active') throw const PayrollPending('Reconnect to the current payroll ledger.');
        return _publish(device, op, await ledger.export());
      case 'resume':
      case 'take':
        final priorPages = await database.customSelect(
          "SELECT count(*) AS n FROM payroll_owner_pages_v2 WHERE business=? AND peer=? AND operation=? AND direction='out'",
          variables: [lease.business, device, op].map(Variable<String>.new).toList()).getSingle();
        final count = priorPages.read<int>('n');
        if (count > 0) {
          if (current?['status'] != 'offered' || current?['operation'] != op) {
            throw const PayrollPending('That payroll transfer was superseded; request the current ledger.');
          }
          final old = await _assemble(device, op, 'out', count);
          return {'count': count, 'digest': await PayrollOwnerLease.digest(old)};
        }
        if (message['command'] == 'resume' && current?['operation'] != op) return {'absent': true};
        final certificate = Map<String, dynamic>.from(peer['certificate'] as Map);
        Future<String> export() => ledger.export();
        Map<String, dynamic> offer;
        if (current?['status'] == 'offering' && current?['operation'] == op) {
          offer = await lease.resumeOffer(operation: op, recipient: certificate, export: export);
        } else {
          if (current?['status'] == 'active') {
            final tasks = await _assemble(device, op, 'in', message['count'] as int);
            if (await PayrollOwnerLease.digest(tasks) != message['digest']) throw StateError('Payroll context digest differs.');
            await ledger.mergeSnapshot(tasks, canonical: false);
          }
          offer = await lease.offer(operation: op, recipient: certificate, export: export);
        }
        return _publish(device, op, jsonEncode(offer));
      default: throw StateError('Unknown payroll command.');
    }
  }
  Future<String> _download(Map<String, dynamic> peer, String op, Map<String, dynamic> result) async {
    final count = result['count'] as int;
    if (count < 1 || count > 4096) throw StateError('Invalid payroll response size.');
    final device = peer['server'] == lease.identity.deviceId ? peer['client'] as String : peer['server'] as String;
    await _page(device, op, 'download-manifest', 0, jsonEncode(result));
    final chunks = <String>[];
    for (var i = 0; i < count; i++) {
      final saved = await database.customSelect("SELECT body FROM payroll_owner_pages_v2 WHERE business=? AND peer=? AND operation=? AND direction='download' AND page=?",
        variables: [Variable(lease.business), Variable(device), Variable(op), Variable(i)]).get();
      if (saved.isNotEmpty) { chunks.add(saved.single.read<String>('body')); continue; }
      final chunk = (await _call(peer, {'command': 'page', 'operation': op, 'page': i}))['body'] as String;
      await _page(device, op, 'download', i, chunk);
      chunks.add(chunk);
    }
    final body = utf8.decode(base64Url.decode(chunks.join()));
    if (await PayrollOwnerLease.digest(body) != result['digest']) throw StateError('Payroll response digest differs.');
    return body;
  }
  Future<List<Map<String, dynamic>>> peers() async {
    final raw = await lease.read(_peersKey);
    final ids = raw == null ? <String>[] : (jsonDecode(raw) as List).cast<String>();
    return [for (final id in ids) if (await _peer(id) case final Map<String, dynamic> peer) peer];
  }
  Future<void> _ack(String device, String operation, String direction, String digest, int acknowledged) async {
    await database.transaction(() async {
      final rows = await database.customSelect('SELECT digest FROM payroll_owner_acks_v2 WHERE business=? AND peer=? AND operation=? AND direction=?',
        variables: [lease.business, device, operation, direction].map(Variable<String>.new).toList()).get();
      if (rows.isNotEmpty && rows.single.data['digest'] != digest) throw StateError('Conflicting payroll acknowledgment.');
      await database.customStatement('INSERT OR IGNORE INTO payroll_owner_acks_v2 VALUES(?,?,?,?,?,?)',
        [lease.business, device, operation, direction, digest, acknowledged]);
    });
  }
  Future<void> _syncMechanicLinks(Map<String, dynamic> peer, LocalOwnerGrant grant) async {
    final current = await lease.state();
    if (current?['certificate'] == null) return;
    final certificate = Map<String, dynamic>.from(current!['certificate'] as Map);
    final operation = 'links-${DateTime.now().microsecondsSinceEpoch}';
    final response = await _call(peer, {'command': 'links', 'operation': operation});
    for (final employee in response['employees'] as List) {
      final link = await _call(peer, {'command': 'link', 'operation': operation, 'employee': employee});
      if (link['code'] != null) {
        grant.assertValid(lease.business, actor);
        await enrollment.importOwnerLink(lease.business, employee as String, link['code'] as String, certificate, grant);
      }
    }
  }

  Future<void> _cacheOffer(Map<String, dynamic> peer, String operation, Map<String, dynamic> offer) async {
    final device = peer['server'] == lease.identity.deviceId ? peer['client'] : peer['server'];
    await lease.storeSnapshot!('incoming:$operation', jsonEncode({'peer': device, 'offer': offer}));
  }

  Future<void> _accept(Map<String, dynamic> peer, Map<String, dynamic> offer, LocalOwnerGrant grant, String operation) async {
    final device = peer['server'] == lease.identity.deviceId ? peer['client'] as String : peer['server'] as String;
    final digest = await PayrollOwnerLease.digest(jsonEncode(offer['lease']));
    await lease.acceptOffer(offer, grant, (snapshot) => database.transaction(() async {
      await ledger.mergeSnapshot(snapshot, canonical: true);
      await _ack(device, operation, 'out', digest, 0);
    }));
    try { await _syncMechanicLinks(peer, grant); } catch (_) { /* Approved links can reconcile after reconnect. */ }
    _scheduleAcks();
  }
  void _scheduleAcks() {
    _ackWork ??= _flushAcks().catchError((Object _) {}).whenComplete(() => _ackWork = null);
    unawaited(_ackWork);
  }
  Future<void> _flushAcks() async {
    final rows = await database.customSelect("SELECT * FROM payroll_owner_acks_v2 WHERE business=? AND direction='out' AND acknowledged=0",
      variables: [Variable(lease.business)]).get();
    for (final row in rows) {
      try {
        final peer = await _peer(row.read<String>('peer'));
        if (peer == null) continue;
        final op = row.read<String>('operation'), digest = row.read<String>('digest');
        final reply = await _call(peer, {'command': 'received', 'operation': op, 'digest': digest});
        if (reply['ack'] != op || reply['digest'] != digest) throw StateError('Payroll acknowledgment differs.');
        await database.customStatement("UPDATE payroll_owner_acks_v2 SET acknowledged=1 WHERE business=? AND peer=? AND operation=? AND direction='out' AND digest=?",
          [lease.business, row.read<String>('peer'), op, digest]);
      } catch (_) { /* Keep the original acknowledgment queued across restarts. */ }
    }
  }

  Future<void> refresh(LocalOwnerGrant grant) async {
    grant.assertValid(lease.business, actor);
    await prepare();
    await _flushAcks();
    final current = await lease.state();
    if (current?['status'] == 'active') {
      for (final peer in await peers()) {
        try {
          final op = 'tasks-${DateTime.now().microsecondsSinceEpoch}';
          final result = await _call(peer, {'command': 'tasks', 'operation': op});
          final snapshot = await _download(peer, op, result);
          grant.assertValid(lease.business, actor);
          await ledger.mergeSnapshot(snapshot, canonical: false);
        } on PayrollPending { rethrow; }
          catch (_) { /* Current exclusive holder can keep working offline. */ }
      }
      return;
    }
    for (final peer in await peers()) {
      try {
        final op = 'read-${DateTime.now().microsecondsSinceEpoch}';
        final result = await _call(peer, {'command': 'read', 'operation': op});
        final snapshot = await _download(peer, op, result);
        grant.assertValid(lease.business, actor);
        await ledger.mergeSnapshot(snapshot, canonical: true);
        return;
      } catch (_) { /* A disconnected or former holder cannot supply current state. */ }
    }
    throw const PayrollPending('Payment pending: reconnect to the current Owner payroll ledger over shop Wi-Fi.');
  }
  Future<PayrollOwnerProof> acquire(LocalOwnerGrant grant, String paymentOperation) async {
    await prepare();
    try { await lease.migrate(grant); } on PayrollPending { /* A connected Owner can transfer its lease. */ }
    try {
      final proof = await lease.proof(grant);
      _scheduleAcks();
      return proof;
    } on PayrollPending { /* Reconcile before finalizing. */ }
    final highWater = int.tryParse(await lease.read('${lease.key}:epoch') ?? '-1') ?? -1;
    final existing = await database.customSelect('SELECT operation FROM payroll_owner_acquisitions_v2 WHERE business=? AND payment=?',
      variables: [lease.business, paymentOperation].map(Variable<String>.new).toList()).get();
    var operation = existing.firstOrNull?.read<String>('operation');
    if (operation != null) {
      final cached = await lease.loadSnapshot!('incoming:$operation');
      if (cached != null) {
        final record = jsonDecode(cached) as Map;
        final offer = Map<String, dynamic>.from(record['offer'] as Map);
        final certified = await lease.verifyLease(Map<String, dynamic>.from(offer['lease'] as Map));
        if ((certified['epoch'] as int) < highWater) {
          operation = null;
        } else {
          final peer = await _peer(record['peer'] as String);
          if (peer != null) {
            await _accept(peer, offer, grant, operation);
            return lease.proof(grant);
          }
        }
      }
    }
    operation ??= await PayrollOwnerLease.digest(jsonEncode(['owner-ledger', paymentOperation, highWater]));
    await database.customStatement('INSERT INTO payroll_owner_acquisitions_v2 VALUES(?,?,?) '
      'ON CONFLICT(business,payment) DO UPDATE SET operation=excluded.operation', [lease.business, paymentOperation, operation]);
    for (final peer in await peers()) {
      try {
        final resumed = await _call(peer, {'command': 'resume', 'operation': operation});
        if (resumed['absent'] != true) {
          final offer = Map<String, dynamic>.from(jsonDecode(await _download(peer, operation, resumed)) as Map);
          await _cacheOffer(peer, operation, offer);
          await _accept(peer, offer, grant, operation);
          return await lease.proof(grant);
        }
        final contextKey = 'context:$operation';
        final snapshot = await lease.loadSnapshot!(contextKey) ?? await ledger.export();
        await lease.storeSnapshot!(contextKey, snapshot);
        final chunks = _chunks(snapshot);
        for (var i = 0; i < chunks.length; i++) {
          await _call(peer, {'command': 'upload', 'operation': operation, 'page': i, 'body': chunks[i]});
        }
        final result = await _call(peer, {'command': 'take', 'operation': operation,
          'count': chunks.length, 'digest': await PayrollOwnerLease.digest(snapshot)});
        final offer = Map<String, dynamic>.from(jsonDecode(await _download(peer, operation, result)) as Map);
        await _cacheOffer(peer, operation, offer);
        await _accept(peer, offer, grant, operation);
        return await lease.proof(grant);
      } catch (_) { /* Durable offer/pending intent is retried with its original operation. */ }
    }
    throw const PayrollPending('Payment pending, not recorded: connect both Owner devices to shop Wi-Fi to verify the current payroll balance.');
  }
}
