import 'dart:convert';

import 'package:briskers_app/services/independent_receipt_ai_gateway.dart';
import 'package:briskers_app/core/supabase_config.dart';
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

  test('existing service sends only photo and shop to the receipt endpoint', () async {
    final gateway = IndependentReceiptAiGateway.existingService(
      transport: (uri, token, body) async {
        expect(uri, Uri.parse('$supabaseUrl/functions/v1/receipt-parse'));
        expect(token, 'app-session');
        expect(body.keys, unorderedEquals(['business_id', 'mime_type', 'image_base64']));
        return {'extraction': {'receipt_total': 105.29}};
      },
    );
    final result = await gateway.enhance(
      receipt: photo(),
      businessId: 'shop',
      accessToken: 'app-session',
      mimeType: 'image/jpeg',
    );
    expect(result['extraction_source'], 'existing_online_receipt_ai');
    expect(result['review_confirmed'], false);
    expect(result['receipt_total'], 105.29);
  });

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

  test('existing deployed Worker response wrappers normalize receipt details for review', () async {
    final gateway=IndependentReceiptAiGateway(
      endpoint:'https://briskers-receipt-ai.example/extract',
      transport:(_,token,body)async{
        expect(token,'synthetic-test-device-token');
        expect(body.keys,unorderedEquals([
          'business_id','mime_type','image_base64',
        ]));
        return {
          'success':true,
          'data':{
            'vendor':'Premier Volkswagen of Harvey',
            'invoice_number':'089164',
            'date':'2026-11-03',
            'total':'\u0024714.80',
            'line_items':[{'description':'VW turbo'}],
          },
        };
      },
    );
    final result=await gateway.enhance(receipt:photo(),
      businessId:'synthetic-shop',
      accessToken:'synthetic-test-device-token',mimeType:'image/jpeg');
    expect(result['vendor_name'],'Premier Volkswagen of Harvey');
    expect(result['vendor_invoice_number'],'089164');
    expect(result['receipt_total'],714.80);
    expect(result['receipt_date'],'2026-11-03');
    expect(result['items'],isA<List>());
    expect(result['review_confirmed'],false);
  });

  test('Worker HTTP 200 error payload is rejected and never shown as recognized receipt', () async {
    final gateway=IndependentReceiptAiGateway(
      endpoint:'https://receipt.example/extract',
      transport:(_, _, _) async => {'success':false,'error':'invalid_business'},
    );
    await expectLater(gateway.enhance(receipt:photo(),
      businessId:'shop',accessToken:'synthetic-test-device-token',
      mimeType:'image/jpeg'),throwsFormatException);
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
