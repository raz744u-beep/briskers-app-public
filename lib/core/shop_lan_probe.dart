import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A deliberately non-sensitive reachability probe for the LAN transport lab.
///
/// NO shop or device identifiers, authentication credentials, or business data
/// are exchanged. Do not expose any record-sync endpoint until encrypted
/// pairing and authorization are implemented.
class ShopLanProbeServer {
  ShopLanProbeServer._(this._server) {
    _server.listen((request) {
      unawaited(_respond(request));
    });
  }

  static const String probePath = '/.well-known/briskers-lan/v1/probe';
  static const String serviceName = 'briskers-lan';
  static const int protocolVersion = 1;

  final HttpServer _server;

  /// The caller must explicitly choose an interface. Tests use loopback;
  /// production must not bind to a shop interface without secure enrollment.
  static Future<ShopLanProbeServer> bind({
    required InternetAddress address,
    int port = 0,
  }) async {
    final server = await HttpServer.bind(address, port, shared: false);
    return ShopLanProbeServer._(server);
  }

  int get port => _server.port;
  InternetAddress get address => _server.address;

  Future<void> _respond(HttpRequest request) async {
    final response = request.response;
    try {
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (request.method != 'GET' || request.uri.path != probePath) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(const <String, Object>{
        'service': serviceName,
        'protocol_version': protocolVersion,
        'mode': 'probe-only',
      }));
    } finally {
      await response.close();
    }
  }

  Future<void> close() => _server.close(force: true);
}

/// Checks only that a compatible read-only probe is reachable.
///
/// A successful probe does NOT authenticate or pair the remote device.
class ShopLanProbeClient {
  const ShopLanProbeClient();

  Future<bool> isCompatible({
    required InternetAddress address,
    required int port,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = Uri(
        scheme: 'http',
        host: address.address,
        port: port,
        path: ShopLanProbeServer.probePath,
      );
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().timeout(timeout);
        return false;
      }
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      final value = jsonDecode(body);
      if (value is! Map<String, dynamic>) return false;
      return value['service'] == ShopLanProbeServer.serviceName &&
          value['protocol_version'] == ShopLanProbeServer.protocolVersion &&
          value['mode'] == 'probe-only';
    } on Exception {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
