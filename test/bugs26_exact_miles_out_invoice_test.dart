import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Miles Out remembers the exact invoice that supplied the reading',
      () {
    final source = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    expect(source, contains('departureInvoiceId = invoiceId;'));
    expect(source, contains('_mileageOutInvoiceId = departureInvoiceId;'));
    expect(source, contains('final id = _mileageOutInvoiceId ??'));
    expect(source, contains('_mileageOutInvoiceId = null;'));
    expect(source, contains('JobMileageSummary.mileageOutFromInvoice('));
  });

  test('same-Job/same-vehicle scope and editing route remain enforced',
      () {
    final source = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    expect(source, contains('projected, jobId: jobId, vehicleId: vehicleId'));
    expect(source, contains('Future<void> _openMileageOutInvoice() async'));
    expect(source, contains('if (id.isNotEmpty) await _openDocument(id);'));
  });
}
