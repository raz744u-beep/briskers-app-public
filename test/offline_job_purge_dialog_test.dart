import 'package:briskers_app/screens/jobs/offline_job_purge_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('synthetic payment label does not append missing fields', () {
    expect(offlinePurgeItemLabel({
      'kind': 'payment',
      'label': 'FAKE payment • 200.00 • TEST cash',
    }), 'FAKE payment • 200.00 • TEST cash');
  });

  test('structured payment details render once', () {
    expect(offlinePurgeItemLabel({
      'kind': 'payment',
      'label': 'Queued payment',
      'amount_cents': 20000,
      'method_name': 'Cash',
      'currency': 'USD',
    }), 'Queued payment · USD 200.00 · Cash');
  });

  test('already formatted payment amount and method are never duplicated', () {
    expect(offlinePurgeItemLabel({
      'kind': 'payment',
      'label': 'FAKE payment • 200.00 • TEST cash',
      'amount_cents': 20000,
      'method_name': 'TEST cash',
      'currency': 'USD',
    }), 'FAKE payment • 200.00 • TEST cash');
  });

  test('partially formatted labels receive only the missing detail', () {
    expect(offlinePurgeItemLabel({
      'kind': 'transaction',
      'label': 'Payment via Cash',
      'amount_cents': 12345,
      'method_name': 'Cash',
      'currency': 'USD',
    }), 'Payment via Cash · USD 123.45');
  });

  test('payment edit audit labels are unchanged', () {
    expect(offlinePurgeItemLabel({
      'kind': 'payment_edit_audit',
      'label': 'FAKE payment edit audit',
    }), 'FAKE payment edit audit');
  });
}
