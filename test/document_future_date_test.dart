import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/core/document_future_date.dart';

void main() {
  final today = DateTime(2026, 10, 8);

  test('flags an actual future date when old local metadata lacks a marker',
      () {
    expect(isFutureDatedDocument({
      'document_number': '5180',
      'document_date': '2026-12-25',
      'future_date_flag': false,
    }, asOf: today), isTrue);
    expect(isFutureDatedDocument({
      'document_number': '4199',
      'document_date': '2026-12-24',
    }, asOf: today), isTrue);
  });

  test('keeps intentional MobileBiz marker after its date passes', () {
    expect(isFutureDatedDocument({
      'document_date': '2025-12-24',
      'future_date_flag': true,
    }, asOf: today), isTrue);
    expect(isFutureDatedDocument({
      'document_date': '2025-12-24',
      'future_date_flag': 'true',
    }, asOf: today), isTrue);
  });

  test('past, same-day, and invalid dates are not automatically flagged', () {
    for (final date in ['2026-10-07', '2026-10-08', 'bad']) {
      expect(isFutureDatedDocument({
        'document_date': date,
        'future_date_flag': false,
      }, asOf: today), isFalse);
    }
  });
}
