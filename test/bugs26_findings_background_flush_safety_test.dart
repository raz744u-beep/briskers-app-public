import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('background finding replay failures cannot escape unawaited futures', () {
    final src =
        File('lib/screens/customers/customer_vehicle_findings_section.dart')
            .readAsStringSync();
    expect(src, contains('_offlineWrites.flush(widget.businessId)'));
    expect(src, contains('_workFindings.flush(widget.businessId).catchError('));
    expect(src, contains('.then((_) => _refresh())'));
    expect(src, contains('.catchError((Object _) {'));
    expect(src, isNot(contains(
      'unawaited(_offlineWrites.flush(widget.businessId));',
    )));
    expect(src, isNot(contains(
      'unawaited(_workFindings.flush(widget.businessId));',
    )));
    expect(src, contains('await _offlineWrites.createFinding('));
  });
}
