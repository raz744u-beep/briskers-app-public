// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'shop_lan_lab_store.dart';

const int lanLabProtocolVersion = 1;
const String lanLabAppId = 'briskers-synthetic-lan-lab';
const String lanLabSyncPath = '/briskers-lan-lab/v1/sync';

String newLanLabPairingKey() {
  final rand = Random.secure();
  final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
  return base64Url.encode(bytes);
}

class LanLabPairing {
  const LanLabPairing({
    required this.host,
    required this.port,
    required this.key,
  });

  final String host;
  final int port;
  final String key;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'app': lanLabAppId,
    'version': lanLabProtocolVersion,
    'host': host,
    'port': port,
    'key': key,
  };

  static LanLabPairing parse(String value) {
    final parsed = jsonDecode(value);
    if (parsed is! Map) throw const FormatException('Not a pairing QR');
    final json = Map<String, dynamic>.from(parsed);
    if (json['app'] != lanLabAppId ||
        json['version'] != lanLabProtocolVersion) {
      throw const FormatException('Incompatible pairing QR');
    }
    final host = json['host']?.toString() ?? '';
    final address = InternetAddress.tryParse(host);
    if (address == null || address.type != InternetAddressType.IPv4 ||
        !isLanLabPrivateIpv4(address)) {
      throw const FormatException('Pairing address must be on private Wi-Fi');
    }
    final port = json['port'];
    if (port is! int || port < 1024 || port > 65535) {
      throw const FormatException('Invalid pairing port');
    }
    final key = json['key']?.toString() ?? '';
    if (!isValidLanLabKey(key)) {
      throw const FormatException('Invalid pairing key');
    }
    return LanLabPairing(host: host, port: port, key: key);
  }
}

bool isLanLabPrivateIpv4(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final x = address.rawAddress;
  return x[0] == 127 || // isolated loopback integration tests only
      x[0] == 10 ||
      (x[0] == 172 && x[1] >= 16 && x[1] <= 31) ||
      (x[0] == 192 && x[1] == 168) ||
      (x[0] == 169 && x[1] == 254);
}

bool isValidLanLabKey(String input) {
  try {
    return base64Url.decode(input).length == 32;
  } on FormatException {
    return false;
  }
}

/// Authenticated encryption for synthetic test traffic only.
///
/// This is a mutually shared high-entropy pairing key read from a QR code.
/// No part of this lab is wired to real shop records or the production outbox.
class LanLabCipher {
  LanLabCipher(String base64Key)
      : _key = SecretKey(base64Url.decode(base64Key)) {
    if (!isValidLanLabKey(base64Key)) {
      throw ArgumentError('Invalid synthetic pairing key');
    }
  }

  final SecretKey _key;
  final _aes = AesGcm.with256bits();

  Future<Map<String, dynamic>> seal(
    Map<String, dynamic> data, {
    required String purpose,
  }) async {
    final encrypted = await _aes.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: _key,
      aad: utf8.encode('briskers-lab-v1:' + purpose),
    );
    return <String, dynamic>{
      'v': lanLabProtocolVersion,
      'nonce': base64Url.encode(encrypted.nonce),
      'cipher': base64Url.encode(encrypted.cipherText),
      'tag': base64Url.encode(encrypted.mac.bytes),
    };
  }

  Future<Map<String, dynamic>> open(
    Map<String, dynamic> box, {
    required String purpose,
  }) async {
    if (box['v'] != lanLabProtocolVersion) {
      throw const FormatException('Unsupported encrypted envelope');
    }
    final bytes = base64Url.decode(box['cipher']?.toString() ?? '');
    final nonce = base64Url.decode(box['nonce']?.toString() ?? '');
    final tag = base64Url.decode(box['tag']?.toString() ?? '');
    if (nonce.length != 12 || tag.length != 16 || bytes.length > 65536) {
      throw const FormatException('Malformed encrypted envelope');
    }
    final data = await _aes.decrypt(
      SecretBox(bytes, nonce: nonce, mac: Mac(tag)),
      secretKey: _key,
      aad: utf8.encode('briskers-lab-v1:' + purpose),
    );
    final decoded = jsonDecode(utf8.decode(data));
    if (decoded is! Map) {
      throw const FormatException('Expected object in encrypted envelope');
    }
    return Map<String, dynamic>.from(decoded);
  }
}

class LanLabSyncResult {
  const LanLabSyncResult({
    required this.sent,
    required this.imported,
    required this.totalLocal,
  });

  final int sent;
  final int imported;
  final int totalLocal;
}

/// Two Android apps communicate over local TCP/IP, never Supabase.
///
/// All requests and responses containing notes are AES-256-GCM encrypted and
/// authenticated. The HTTP layer is a lab transport only; production requires
/// enrolled device identity, roles, revocation, and independently durable ACKs.
class LanLabTransport {
  LanLabTransport({
    required this.store,
    required String pairingKey,
    required this.deviceId,
    this.onRemoteChanged,
    this.preferredPort = 48572,
  }) : _cipher = LanLabCipher(pairingKey);

  final LanLabStore store;
  final String deviceId;
  final Future<void> Function()? onRemoteChanged;
  /// TEST #17's preferred LAN port, distinct from TEST #15/#16's 48571.
  /// If occupied, the operating system supplies a free temporary port.
  final int preferredPort;
  LanLabCipher _cipher;
  HttpServer? _server;

  int? get port => _server?.port;

  void updatePairingKey(String key) {
    _cipher = LanLabCipher(key);
  }

  Future<void> start() async {
    if (_server != null) return;
    // TEST #15/#16 use port 48571. Prefer a separate listener for TEST #17.
    // If another process has the preferred port, avoid a fatal setup error.
    // The actual bound port is shown in the QR pairing payload.
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort);
    } on SocketException catch (error) {
      // EADDRINUSE (errno 98): an older test/other app owns this port.
      if (error.osError?.errorCode != 98) rethrow;
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server!.listen((request) { unawaited(_accept(request)); });
  }

  Future<void> close() async {
    final current = _server;
    _server = null;
    if (current != null) await current.close(force: true);
  }

  Future<void> _accept(HttpRequest request) async {
    final response = request.response;
    try {
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (request.uri.path != lanLabSyncPath ||
          request.method != 'POST') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.contentLength > 262144) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > 262144) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
      }
      final payload = jsonDecode(utf8.decode(bytes));
      if (payload is! Map) {
        response.statusCode = HttpStatus.badRequest;
        return;
      }
      final body = await _cipher.open(
        Map<String, dynamic>.from(payload),
        purpose: 'request',
      );
      final senderId = body['deviceId']?.toString() ?? '';
      if (body['app'] != lanLabAppId ||
          body['version'] != lanLabProtocolVersion ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(senderId) ||
          senderId == deviceId) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      final received = body['notes'];
      if (received is! List || received.length > 50) {
        response.statusCode = HttpStatus.badRequest;
        return;
      }
      final notes = <LanLabNote>[];
      for (final raw in received) {
        if (raw is! Map) throw const FormatException('Invalid note');
        notes.add(await LanLabNote.fromJson(
          Map<String, dynamic>.from(raw),
        ));
      }

      // Durable per-note commit happens BEFORE returning an ACK.
      final inserted = await store.saveAll(notes);
      if (inserted > 0 && onRemoteChanged != null) {
        unawaited(onRemoteChanged!());
      }
      final snapshot = await store.all();
      final sealed = await _cipher.seal(<String, dynamic>{
        'app': lanLabAppId,
        'version': lanLabProtocolVersion,
        'acceptedIds': notes.map((note) => note.id).toList(),
        'notes': snapshot.map((note) => note.toJson()).toList(),
      }, purpose: 'response');
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(sealed));
    } on SecretBoxAuthenticationError {
      response.statusCode = HttpStatus.forbidden;
    } on FormatException {
      response.statusCode = HttpStatus.badRequest;
    } on StateError {
      response.statusCode = HttpStatus.conflict;
    } catch (_) {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  Future<LanLabSyncResult> syncWith(LanLabPairing peer) async {
    if (peer.host.isEmpty || !isValidLanLabKey(peer.key)) {
      throw const FormatException('Pair with a local Android device first');
    }
    if (!isLanLabPrivateIpv4(InternetAddress(peer.host))) {
      throw const FormatException('Public IPs not permitted in LAN lab');
    }
    final local = await store.all();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri(
        scheme: 'http',
        host: peer.host,
        port: peer.port,
        path: lanLabSyncPath,
      )).timeout(const Duration(seconds: 6));
      request.headers.contentType = ContentType.json;
      request.followRedirects = false;
      request.write(jsonEncode(await LanLabCipher(peer.key).seal(
        <String, dynamic>{
          'app': lanLabAppId,
          'version': lanLabProtocolVersion,
          'deviceId': deviceId,
          'notes': local.map((note) => note.toJson()).toList(),
        }, purpose: 'request',
      )));
      final response = await request.close().timeout(
        const Duration(seconds: 9),
      );
      final raw = await utf8.decoder.bind(response).join().timeout(
        const Duration(seconds: 9),
      );
      if (response.statusCode != 200) {
        throw StateError('Peer rejected sync (HTTP ' +
            response.statusCode.toString() + ')');
      }
      final content = jsonDecode(raw);
      if (content is! Map) throw const FormatException('Invalid peer response');
      final decoded = await LanLabCipher(peer.key).open(
        Map<String, dynamic>.from(content), purpose: 'response',
      );
      if (decoded['app'] != lanLabAppId ||
          decoded['version'] != lanLabProtocolVersion) {
        throw const FormatException('Peer protocol mismatch');
      }
      final accepted = decoded['acceptedIds'];
      if (accepted is! List ||
          !local.every((note) => accepted.contains(note.id))) {
        throw StateError('Peer did not acknowledge every local note');
      }
      final received = decoded['notes'];
      if (received is! List || received.length > 50) {
        throw const FormatException('Bad remote note batch');
      }
      final notes = <LanLabNote>[];
      for (final item in received) {
        if (item is! Map) throw const FormatException('Bad remote note');
        notes.add(await LanLabNote.fromJson(
          Map<String, dynamic>.from(item),
        ));
      }
      final imported = await store.saveAll(notes);
      return LanLabSyncResult(
        sent: local.length,
        imported: imported,
        totalLocal: (await store.all()).length,
      );
    } finally {
      client.close(force: true);
    }
  }
}
