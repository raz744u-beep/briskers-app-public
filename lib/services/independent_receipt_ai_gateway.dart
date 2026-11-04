import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';

typedef ReceiptAiTransport = Future<Map<String, dynamic>> Function(
  Uri endpoint,
  String token,
  Map<String, dynamic> body,
);

/// Receipt recognition has no Supabase dependency. The endpoint is public
/// configuration; the revocable shop token is supplied from secure storage.
class IndependentReceiptAiGateway {
  const IndependentReceiptAiGateway({
    this.endpoint = const String.fromEnvironment(
      'BRISKERS_RECEIPT_AI_GATEWAY_URL',
    ),
    ReceiptAiTransport? transport,
  }) : _transport = transport;

  final String endpoint;
  final ReceiptAiTransport? _transport;
  static const maxImageBytes = 20 * 1024 * 1024;
  static const maxResponseBytes = 1024 * 1024;

  bool get configured {
    final uri = Uri.tryParse(endpoint);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment;
  }

  Future<Map<String, dynamic>> enhance({
    required XFile receipt,
    required String businessId,
    required String accessToken,
    required String mimeType,
  }) async {
    if (!configured) {
      throw StateError('Independent online AI gateway is not configured.');
    }
    if (accessToken.trim().isEmpty || businessId.trim().isEmpty) {
      throw StateError('Receipt AI device authorization is not configured.');
    }
    if (!const {
      'image/jpeg',
      'image/png',
      'image/heic',
      'image/webp',
    }.contains(mimeType)) {
      throw const FormatException('Unsupported receipt photo type.');
    }
    final size = await receipt.length();
    if (size == 0 || size > maxImageBytes) {
      throw const FormatException(
        'Receipt photo must be between 1 byte and 20 MB.',
      );
    }
    final bytes = await receipt.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxImageBytes) {
      throw const FormatException('Receipt photo exceeds the upload limit.');
    }
    final decoded = await (_transport ?? _send)(
      Uri.parse(endpoint),
      accessToken.trim(),
      <String, dynamic>{
        'business_id': businessId,
        'mime_type': mimeType,
        'image_base64': base64Encode(bytes),
      },
    ).timeout(const Duration(seconds: 30));
    final result = decoded['extraction'] ?? decoded;
    if (result is! Map || result.isEmpty) {
      throw const FormatException('Gateway returned no extraction.');
    }
    return <String, dynamic>{
      ...Map<String, dynamic>.from(result),
      'extraction_source': 'independent_online_ai',
      'review_confirmed': false,
    };
  }

  static Future<Map<String, dynamic>> _send(
    Uri endpoint,
    String token,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      // Bound the entire exchange and close sockets on timeout. Never forward
      // the device credential or receipt to a redirect destination.
      return await (() async {
        final request = await client.postUrl(endpoint);
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        request.add(utf8.encode(jsonEncode(body)));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw StateError(
            'Receipt AI unavailable (HTTP ${response.statusCode}).',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw const FormatException('Receipt AI response exceeds limit.');
          }
          bytes.addAll(chunk);
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) {
          throw const FormatException('Unexpected receipt AI response.');
        }
        return Map<String, dynamic>.from(decoded);
      })().timeout(const Duration(seconds: 30));
    } finally {
      client.close(force: true);
    }
  }
}
