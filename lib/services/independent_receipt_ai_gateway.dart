import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../core/supabase_config.dart';

typedef ReceiptAiTransport = Future<Map<String, dynamic>> Function(
  Uri endpoint,
  String token,
  Map<String, dynamic> body,
);

/// Bounded, receipt-only HTTP transport. The optional independent endpoint
/// uses a device token. The existing service uses the current app session.
class IndependentReceiptAiGateway {
  const IndependentReceiptAiGateway({
    this.endpoint = const String.fromEnvironment(
      'BRISKERS_RECEIPT_AI_GATEWAY_URL',
      defaultValue:
          'https://briskers-receipt-ai.raz744u.workers.dev/extract',
    ),
    ReceiptAiTransport? transport,
  }) : _transport = transport, _existingService = false;

  const IndependentReceiptAiGateway.existingService({
    ReceiptAiTransport? transport,
  })  : endpoint = '$supabaseUrl/functions/v1/receipt-parse',
        _transport = transport,
        _existingService = true;

  final String endpoint;
  final ReceiptAiTransport? _transport;
  final bool _existingService;
  static const maxImageBytes = 8 * 1024 * 1024;
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
      throw StateError(_existingService
          ? 'Receipt AI needs an active Briskers sign-in.'
          : 'Receipt AI device authorization is not configured.');
    }
    if (!const {
      'image/jpeg',
      'image/png',
      'image/webp',
    }.contains(mimeType)) {
      throw const FormatException('Unsupported receipt photo type.');
    }
    final size = await receipt.length();
    if (size == 0 || size > maxImageBytes) {
      throw const FormatException(
        'Receipt photo must be between 1 byte and 8 MB.',
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
    // A proxy or provider sometimes returns HTTP 200 with an error object.
    // Never treat such a response as extracted receipt fields or persist it.
    final gatewayError = decoded['error']?.toString().toLowerCase() ?? '';
    if (gatewayError == 'unauthorized' || gatewayError == 'invalid_token' ||
        gatewayError == 'invalid_gateway_token') {
      throw StateError('Receipt AI unavailable (HTTP 401).');
    }
    if (gatewayError == 'invalid_business') {
      throw StateError('Receipt AI rejected business identity.');
    }
    if (gatewayError.isNotEmpty || decoded['success'] == false) {
      throw const FormatException('Gateway returned no extraction.');
    }
    // The original Cloudflare Worker and the older receipt parser use
    // slightly different successful JSON wrappers. Normalize only known
    // receipt fields; never interpret an error or unrelated response as OCR.
    final result = decoded['extraction'] ?? decoded['receipt'] ??
        decoded['data'] ?? decoded['result'] ?? decoded;
    if (result is! Map || result.isEmpty) {
      throw const FormatException('Gateway returned no extraction.');
    }
    final fields = Map<String, dynamic>.from(result);
    void alias(String canonical, List<String> keys) {
      if (fields[canonical] != null) return;
      for (final key in keys) {
        if (fields[key] != null) {
          fields[canonical] = fields[key];
          return;
        }
      }
    }
    alias('vendor_name', const ['merchant_name', 'merchant', 'vendor', 'payee']);
    alias('receipt_total', const ['total', 'total_amount', 'amount_paid']);
    alias('receipt_date', const ['date', 'invoice_date']);
    alias('vendor_invoice_number', const ['invoice_number', 'receipt_number']);
    alias('items', const ['line_items', 'parts']);
    alias('subtotal', const ['sub_total']);
    final amount = fields['receipt_total'];
    if (amount is String) {
      final parsed = num.tryParse(
        amount.trim().replaceAll(',', '').replaceAll('\u0024', ''),
      );
      if (parsed != null && parsed.isFinite && parsed > 0) {
        fields['receipt_total'] = parsed;
      }
    }
    const recognizedFields = <String>{
      'vendor_name', 'receipt_total', 'receipt_date',
      'vendor_invoice_number', 'items', 'subtotal',
    };
    if (!fields.keys.any((key) =>
            recognizedFields.contains(key) && fields[key] != null) ||
        fields.values.every((value) => value == null)) {
      throw const FormatException('Gateway returned no extraction.');
    }
    return <String, dynamic>{
      ...fields,
      'extraction_source': _existingService
          ? 'existing_online_receipt_ai'
          : 'independent_online_ai',
      'review_confirmed': false,
    };
  }

  Future<Map<String, dynamic>> _send(
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
        if (_existingService) {
          request.headers.set('apikey', supabasePublishableKey);
        }
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
