import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:briskers_app/services/independent_receipt_ai_gateway.dart';

XFile sampleReceipt() => XFile.fromData(
  Uint8List.fromList([1, 2, 3, 4]),
  mimeType: 'image/jpeg',
  name: 'test-receipt.jpg',
);

void main() {
  final endpoint = 'https://receipts.example.test/extract';

  test('receipt AI rejects HTTP 200 error object before operator review', () async {
    final gateway = IndependentReceiptAiGateway(
      endpoint: endpoint,
      transport: (_, _, _) async => <String, dynamic>{
        'error': 'upstream unavailable',
      },
    );
    await expectLater(
      gateway.enhance(
        receipt: sampleReceipt(),
        businessId: 'synthetic-business',
        accessToken: 'synthetic-token',
        mimeType: 'image/jpeg',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('receipt AI rejects unrelated HTTP 200 JSON and empty extraction', () async {
    for (final payload in <Map<String, dynamic>>[
      {'message': 'ok'},
      {'extraction': <String, dynamic>{}},
    ]) {
      final gateway = IndependentReceiptAiGateway(
        endpoint: endpoint,
        transport: (_, _, _) async => payload,
      );
      await expectLater(
        gateway.enhance(
          receipt: sampleReceipt(),
          businessId: 'synthetic-business',
          accessToken: 'synthetic-token',
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('valid receipt fields reach review but never claim confirmation', () async {
    final gateway = IndependentReceiptAiGateway(
      endpoint: endpoint,
      transport: (uri, token, body) async {
        expect(uri.toString(), endpoint);
        expect(token, 'synthetic-token');
        expect(body['business_id'], 'synthetic-business');
        return <String, dynamic>{
          'extraction': {
            'vendor_name': 'Synthetic Parts Supplier',
            'receipt_total': 31.25,
            'items': [
              {'description': 'Synthetic water pump'},
            ],
          },
        };
      },
    );
    final result = await gateway.enhance(
      receipt: sampleReceipt(),
      businessId: 'synthetic-business',
      accessToken: 'synthetic-token',
      mimeType: 'image/jpeg',
    );
    expect(result['vendor_name'], 'Synthetic Parts Supplier');
    expect(result['receipt_total'], 31.25);
    expect(result['extraction_source'], 'independent_online_ai');
    expect(result['review_confirmed'], false);
  });

  test('missing device authorization fails before network transport', () async {
    var calls = 0;
    final gateway = IndependentReceiptAiGateway(
      endpoint: endpoint,
      transport: (_, _, _) async {
        calls++;
        return {'receipt_total': 2.0};
      },
    );
    await expectLater(
      gateway.enhance(
        receipt: sampleReceipt(),
        businessId: 'synthetic-business',
        accessToken: '',
        mimeType: 'image/jpeg',
      ),
      throwsA(isA<StateError>()),
    );
    expect(calls, 0);
  });
}
