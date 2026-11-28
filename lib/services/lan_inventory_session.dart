import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'lan_record_inventory.dart';

/// The session shares an encrypted inventory and an optional record copy. The connection
/// code contains the decryption key and is shared separately by the Owner.
class LanInventorySession {
  LanInventorySession._(this._server, this.code) {
    _expiry = Timer(const Duration(minutes: 5), () => unawaited(close()));
  }

  final HttpServer _server;
  final String code;
  late final Timer _expiry;
  static final _cipher = AesGcm.with256bits();
  static const _inventoryLimit = 4 * 1024 * 1024;
  static const _recordCopyLimit = 16 * 1024 * 1024;
  static List<int> _binding(String shop, String path) => utf8.encode(
    path == '/inventory' ? shop : '$shop/customer-vehicle-copy-v1',
  );

  static bool _private(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  static Future<List<InternetAddress>> addresses() async => [
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    ))
      for (final address in interface.addresses)
        if (_private(address)) address,
  ];

  static Future<LanInventorySession> offer({
    required InternetAddress address,
    required String business,
    required List<LanInventoryEntry> inventory,
    Map<String, dynamic>? recordCopy,
  }) async {
    if (!_private(address)) throw StateError('Choose a private Wi-Fi address.');
    final shop = LanRecordInventory.shopFingerprint(business);
    final payload = utf8.encode(
      jsonEncode([
        shop,
        for (final item in inventory)
          [
            item.kind,
            item.identity,
            item.fingerprint,
            item.pending,
            item.hasDocumentDetail,
            item.review,
          ],
      ]),
    );
    if (payload.length > _inventoryLimit) {
      throw StateError('This inventory is too large for a preview.');
    }
    final key = await _cipher.newSecretKey();
    Future<List<int>> seal(List<int> plain, String path) async =>
        (await _cipher.encrypt(
          plain,
          secretKey: key,
          aad: _binding(shop, path),
        )).concatenation();
    final payloads = {'/inventory': await seal(payload, '/inventory')};
    if (recordCopy != null) {
      final plain = utf8.encode(jsonEncode(recordCopy));
      if (plain.length > _recordCopyLimit) {
        throw StateError('This copy is too large to share in one session.');
      }
      payloads['/customer-vehicle-copy'] = await seal(
        plain,
        '/customer-vehicle-copy',
      );
    }
    final server = await HttpServer.bind(address, 0);
    server.listen((request) async {
      final remote = request.connectionInfo?.remoteAddress;
      final bytes = payloads[request.uri.path];
      if (request.method == 'GET' &&
          bytes != null &&
          remote != null &&
          _private(remote)) {
        request.response.headers.contentType = ContentType.binary;
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final encodedKey = base64UrlEncode(await key.extractBytes());
    return LanInventorySession._(
      server,
      '${address.address}:${server.port}/$encodedKey',
    );
  }

  Future<void> close() async {
    _expiry.cancel();
    await _server.close(force: true);
  }

  static bool isComparisonCode(String code) {
    try {
      _parseComparisonCode(code);
      return true;
    } on FormatException {
      return false;
    }
  }

  static ({InternetAddress address, int port, String key}) _parseComparisonCode(
    String code,
  ) {
    final match = RegExp(r'^([0-9.]+):([0-9]{1,5})/([A-Za-z0-9_-]{43}=)$')
        .firstMatch(code.trim());
    if (match == null) {
      throw const FormatException('Enter the full comparison code.');
    }
    final address = InternetAddress.tryParse(match[1]!);
    final port = int.parse(match[2]!);
    if (address == null || !_private(address) || port < 1 || port > 65535) {
      throw const FormatException(
        'The comparison code must contain a private Wi-Fi address.',
      );
    }
    return (address: address, port: port, key: match[3]!);
  }

  static Future<List<LanInventoryEntry>> fetch(
    String code,
    String business,
  ) async {
    final shop = LanRecordInventory.shopFingerprint(business);
    final data = await _fetchPayload(code, shop, '/inventory', _inventoryLimit);
    if (data is! List || data.isEmpty || data.first != shop) {
      throw const FormatException('The inventory belongs to a different shop.');
    }
    final entries = <LanInventoryEntry>[];
    for (final item in data.skip(1)) {
      if (item is! List ||
          (item.length != 5 && item.length != 6) ||
          !const {
            'customer',
            'vehicle',
            'job',
            'estimate',
            'invoice',
          }.contains(item[0]) ||
          item[1] is! String ||
          item[2] is! String ||
          item[3] is! bool ||
          item[4] is! bool) {
        throw const FormatException('This inventory format is invalid.');
      }
      final review = <String, String>{};
      if (item.length == 6) {
        final values = item[5];
        if (values is! Map || values.length > 8) {
          throw const FormatException('Invalid record review fields.');
        }
        for (final field in values.entries) {
          final label = field.key;
          final value = field.value;
          if (label is! String ||
              label.length > 32 ||
              value is! String ||
              value.length > 97) {
            throw const FormatException('Invalid record review field.');
          }
          review[label] = value;
        }
      }
      entries.add((
        kind: item[0] as String,
        identity: item[1] as String,
        fingerprint: item[2] as String,
        pending: item[3] as bool,
        hasDocumentDetail: item[4] as bool,
        review: Map.unmodifiable(review),
      ));
    }
    return entries;
  }

  static Future<Map<String, dynamic>> fetchRecordCopy(
    String code,
    String business,
  ) async {
    final shop = LanRecordInventory.shopFingerprint(business);
    final data = await _fetchPayload(
      code,
      shop,
      '/customer-vehicle-copy',
      _recordCopyLimit,
    );
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid LAN record copy data.');
    }
    return data;
  }

  static Future<Object?> _fetchPayload(
    String code,
    String shop,
    String path,
    int limit,
  ) async {
    final (:address, :port, :key) = _parseComparisonCode(code);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..findProxy = ((_) => 'DIRECT');
    try {
      final request = await client
          .getUrl(
            Uri(scheme: 'http', host: address.address, port: port, path: path),
          )
          .timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          path == '/inventory' ? 'The inventory session is unavailable.' : 'The copy session is unavailable. Enable record copying on the source phone and share again.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        if (bytes.length + chunk.length > limit + 28) {
          throw const FormatException('Inventory is too large.');
        }
        bytes.add(chunk);
      }
      if (bytes.length < 28) {
        throw const FormatException('The inventory was incomplete.');
      }
      final plain = await _cipher.decrypt(
        SecretBox.fromConcatenation(
          bytes.takeBytes(), nonceLength: 12, macLength: 16,
        ),
        secretKey: SecretKey(base64Url.decode(key)),
        aad: _binding(shop, path),
      );
      return jsonDecode(utf8.decode(plain));
    } finally {
      client.close(force: true);
    }
  }
}
