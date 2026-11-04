import 'dart:convert';

import 'package:briskers_app/services/independent_receipt_ai_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:typed_data';

void main() {
  XFile photo() =>
      XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'receipt.jpg');

  test('requires HTTPS configuration without credentials in URL', () {
    for (final url in [
      '',
      'http://receipt.example/scan',
      'https://user:pass@receipt.example/scan',
    ]) {
      expect(IndependentReceiptAiGateway(endpoint: url).configured, false);
    }
    expect(
      const IndependentReceiptAiGateway(
        endpoint: 'https://receipt.example/scan',
      ).configured,
      true,
    );
  });

  test(
    'Force Offline AI uses independent transport and requires review',
    () async {
      var calls = 0;
      final gateway = IndependentReceiptAiGateway(
        endpoint: 'https://receipt.example/scan',
        transport: (uri, token, body) async {
          calls++;
          expect(uri.host, 'receipt.example');
          expect(token, 'device-token');
          expect(body['business_id'], 'shop');
          expect(base64Decode(body['image_base64'] as String), [1, 2, 3]);
          return {
            'extraction': {
              'vendor_invoice_number': '00123',
              'receipt_total': 191.35,
              'review_confirmed': true,
            },
          };
        },
      );
      final result = await gateway.enhance(
        receipt: photo(),
        businessId: 'shop',
        accessToken: 'device-token',
        mimeType: 'image/jpeg',
      );
      expect(calls, 1);
      expect(result['vendor_invoice_number'], '00123');
      expect(result['receipt_total'], 191.35);
      expect(result['review_confirmed'], false);
      expect(result['extraction_source'], 'independent_online_ai');
    },
  );

  test('missing authorization and unsupported photos never upload', () async {
    var calls = 0;
    final gateway = IndependentReceiptAiGateway(
      endpoint: 'https://receipt.example/scan',
      transport: (_, _, _) async {
        calls++;
        return {};
      },
    );
    await expectLater(
      gateway.enhance(
        receipt: photo(),
        businessId: 'shop',
        accessToken: '',
        mimeType: 'image/jpeg',
      ),
      throwsStateError,
    );
    await expectLater(
      gateway.enhance(
        receipt: photo(),
        businessId: 'shop',
        accessToken: 'device',
        mimeType: 'application/pdf',
      ),
      throwsFormatException,
    );
    expect(calls, 0);
  });

  test('gateway failures retain original and do not silently retry', () async {
    var calls = 0;
    final original = photo();
    final gateway = IndependentReceiptAiGateway(
      endpoint: 'https://receipt.example/scan',
      transport: (_, _, _) async {
        calls++;
        throw const FormatException('Invalid response');
      },
    );
    await expectLater(
      gateway.enhance(
        receipt: original,
        businessId: 'shop',
        accessToken: 'device',
        mimeType: 'image/jpeg',
      ),
      throwsFormatException,
    );
    expect(await original.readAsBytes(), [1, 2, 3]);
    expect(calls, 1);
  });
}
