import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/independent_receipt_ai_gateway.dart';

void main() {
  test('regular Briskers receipt reader targets the independent HTTPS gateway', () {
    const gateway = IndependentReceiptAiGateway();
    expect(gateway.configured, isTrue);
    expect(gateway.endpoint,
        'https://briskers-receipt-ai.raz744u.workers.dev/extract');
    expect(gateway.endpoint, isNot(contains('supabase')));
  });

  test('receipt gateway never permits an insecure HTTP endpoint', () {
    const gateway = IndependentReceiptAiGateway(
      endpoint: 'http://briskers-receipt-ai.example.test/extract',
    );
    expect(gateway.configured, isFalse);
  });

  test('receipt image size matches the deployed Worker limit', () {
    expect(IndependentReceiptAiGateway.maxImageBytes, 8 * 1024 * 1024);
  });
}
