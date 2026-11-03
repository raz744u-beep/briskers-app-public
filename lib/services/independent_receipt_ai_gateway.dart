import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// Optional, user-initiated cloud enhancement. Provider credentials live on
/// the independent gateway, never in this APK or Supabase Edge Functions.
/// The gateway URL is public configuration; access tokens are provisioned by
/// that gateway and stored in Android/iOS secure storage by the caller.
class IndependentReceiptAiGateway {
  const IndependentReceiptAiGateway();

  static const endpoint = String.fromEnvironment(
    'BRISKERS_RECEIPT_AI_GATEWAY_URL',
  );

  bool get configured {
    final uri = Uri.tryParse(endpoint);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
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
    if (accessToken.trim().isEmpty) {
      throw StateError('A gateway-issued access token is required.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader,
          'Bearer ' + accessToken.trim());
      request.add(utf8.encode(jsonEncode(<String, dynamic>{
        'business_id': businessId,
        'mime_type': mimeType,
        'image_base64': base64Encode(await receipt.readAsBytes()),
      })));
      final response = await request.close()
          .timeout(const Duration(seconds: 20));
      final raw = await utf8.decoder.bind(response).join()
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('AI gateway error: HTTP ' +
          response.statusCode.toString());
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Unexpected AI gateway response');
      }
      final result = decoded['extraction'] ?? decoded;
      if (result is! Map) {
        throw const FormatException('Gateway returned no extraction');
      }
      final extraction = Map<String, dynamic>.from(result);
      // The on-device source is never overwritten unless the user explicitly
      // accepts the separate review sheet.
      extraction['extraction_source'] = 'independent_online_ai';
      extraction['review_confirmed'] = false;
      return extraction;
    } finally {
      client.close(force: true);
    }
  }
}
