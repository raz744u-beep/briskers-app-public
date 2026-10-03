import 'package:flutter/services.dart';

class GmailComposeService {
  const GmailComposeService._();

  static const MethodChannel _channel =
      MethodChannel('com.briskers/gmail');

  static Future<void> composePdf({
    required Uint8List bytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    await _channel.invokeMethod<void>(
      'composeGmailPdf',
      <String, dynamic>{
        'bytes': bytes,
        'filename': filename,
        'to': to,
        'subject': subject,
        'body': body,
      },
    );
  }
}
