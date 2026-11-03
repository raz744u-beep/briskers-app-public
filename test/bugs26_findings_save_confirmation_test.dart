import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Customer finding success is acknowledged before optional refresh', () {
    final source =
        File('lib/screens/customers/customer_vehicle_findings_section.dart')
            .readAsStringSync();
    final start = source.indexOf('await _offlineWrites.createFinding(');
    final success = source.indexOf('Finding saved on this device.', start);
    final refresh = source.indexOf('await _refresh(cacheOnly: true);', start);
    expect(start, greaterThan(0));
    expect(success, greaterThan(start));
    expect(refresh, greaterThan(success));
    expect(source, contains(
      'Finding saved locally. Reopen Findings to refresh the list.',
    ));
    expect(source, contains('body: body,'));
  });
}
