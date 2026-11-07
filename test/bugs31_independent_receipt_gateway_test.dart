import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:briskers_app/services/independent_receipt_ai_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  XFile receipt() => XFile.fromData(
    Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
    name: 'test-receipt.jpg',
    mimeType: 'image/jpeg',
  );

  test('Force Offline receipt scan uses private HTTPS Worker without Supabase',
      () async {
    var calls = 0;
    final gateway = IndependentReceiptAiGateway(
      transport: (endpoint, token, body) async {
        calls++;
        expect(endpoint.scheme, 'https');
        expect(endpoint.host, 'briskers-receipt-ai.raz744u.workers.dev');
        expect(endpoint.path, '/extract');
        expect(token, 'synthetic-private-gateway-credential');
        expect(body['business_id'], 'synthetic-shop');
        expect(body['mime_type'], 'image/jpeg');
        expect(base64Decode(body['image_base64'] as String),
            [0xff, 0xd8, 0xff, 0xd9]);
        return {
          'success': true,
          'extraction': {
            'merchant': 'Synthetic Parts Vendor',
            'total': '1,282.19',
            'invoice_number': 'SYN-1234',
            'date': '2026-11-07',
            'line_items': [
              {'description': 'Synthetic starter motor', 'price': 1180.00}
            ],
          },
        };
      },
    );

    final suggestion = await gateway.enhance(
      receipt: receipt(),
      businessId: 'synthetic-shop',
      accessToken: 'synthetic-private-gateway-credential',
      mimeType: 'image/jpeg',
    );
    expect(calls, 1);
    expect(suggestion['vendor_name'], 'Synthetic Parts Vendor');
    expect(suggestion['receipt_total'], 1282.19);
    expect(suggestion['vendor_invoice_number'], 'SYN-1234');
    expect(suggestion['receipt_date'], '2026-11-07');
    expect(suggestion['items'], isNotEmpty);
    expect(suggestion['extraction_source'], 'independent_online_ai');
    expect(suggestion['review_confirmed'], false);
  });

  test('gateway 200 error is never mistaken for a scanned receipt', () async {
    final gateway = IndependentReceiptAiGateway(
      transport: (_, __, ___) async => {
        'success': false, 'error': 'invalid_gateway_token',
        'data': {'merchant': 'Misleading Vendor'},
      },
    );
    await expectLater(
      gateway.enhance(
        receipt: receipt(), businessId: 'synthetic-shop',
        accessToken: 'synthetic-private-gateway-credential',
        mimeType: 'image/jpeg',
      ),
      throwsStateError,
    );
  });

  test('garbage success response cannot create financial suggestions', () async {
    final gateway = IndependentReceiptAiGateway(
      transport: (_, __, ___) async => {
        'success': true, 'data': {'unrelated': 'not a receipt'},
      },
    );
    await expectLater(
      gateway.enhance(
        receipt: receipt(), businessId: 'synthetic-shop',
        accessToken: 'synthetic-private-gateway-credential',
        mimeType: 'image/jpeg',
      ),
      throwsFormatException,
    );
  });
}
