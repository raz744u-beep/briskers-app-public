import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/shop_lan_probe.dart';

void main() {
  test('read-only LAN probe works over loopback with no cloud dependency', () async {
    final server = await ShopLanProbeServer.bind(
      address: InternetAddress.loopbackIPv4,
    );
    addTearDown(server.close);

    expect(
      await const ShopLanProbeClient().isCompatible(
        address: InternetAddress.loopbackIPv4,
        port: server.port,
      ),
      isTrue,
    );

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        path: ShopLanProbeServer.probePath,
      ),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    expect(json['service'], 'briskers-lan');
    expect(json['protocol_version'], 1);
    expect(json['mode'], 'probe-only');
    expect(json.keys.toSet(), {'service', 'protocol_version', 'mode'});
    expect(body, isNot(contains('business_id')));
    expect(body, isNot(contains('customer')));
  });

  test('unknown LAN path cannot expose a business endpoint', () async {
    final server = await ShopLanProbeServer.bind(
      address: InternetAddress.loopbackIPv4,
    );
    addTearDown(server.close);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        path: '/records',
      ),
    );
    final response = await request.close();
    expect(response.statusCode, HttpStatus.notFound);
    await response.drain<void>();
  });
}
