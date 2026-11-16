import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/expenses/expense_entry_screen.dart';

void main() {
  test('receipt AI auth failure explains local manual recovery', () {
    final message = receiptAiFailureMessage(StateError('Receipt AI unavailable (HTTP 401).'));
    expect(message, contains('sign-in'));
    expect(message, contains('manual'));
    expect(message, isNot(contains('HTTP 401')));
  });

  test('receipt AI rate limit and timeout have distinct guidance', () {
    expect(
      receiptAiFailureMessage(StateError('Receipt AI unavailable (HTTP 429).')),
      contains('request limit'),
    );
    expect(
      receiptAiFailureMessage(Exception('TimeoutException')),
      contains('service or internet'),
    );
  });

  test('receipt AI malformed response preserves safe explanation', () {
    expect(
      receiptAiFailureMessage(const FormatException('Gateway returned no extraction.')),
      contains('did not return readable'),
    );
  });

  test('receipt AI never repeats raw receipt or token data', () {
    final message = receiptAiFailureMessage(
      StateError('private_receipt.jpg bearer secret-xyz failed'),
    );
    expect(message, isNot(contains('private_receipt')));
    expect(message, isNot(contains('secret-xyz')));
    expect(message, contains('photo is still attached'));
  });
}
