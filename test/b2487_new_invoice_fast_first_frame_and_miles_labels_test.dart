import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('New server invoice bypasses unrelated receipt flush only on initial load', () {
    final source = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    expect(source, contains('this.freshlyCreated = false'));
    expect(source, contains('final bool freshlyCreated;'));
    expect(source, contains('if (!(widget.freshlyCreated && generation == 1)) {'));
    expect(source, contains('await _offlinePayments.flush(widget.businessId);'));
    expect(source, contains('final detail = await _api.documentDetail('));
    // A new invoice's remote detail is still obtained authoritatively.
    final before = source.indexOf('if (!(widget.freshlyCreated && generation == 1))');
    final detail = source.indexOf('final detail = await _api.documentDetail(', before);
    expect(detail, greaterThan(before));
  });

  test('Verified invoice paints after safe cache write but before optional metadata RPCs', () {
    final source = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final origin = source.indexOf("debugPrint('PERF-001 document detail RPC:");
    final section = source.indexOf('final openWatch = Stopwatch()..start();');
    final first = source.indexOf('setState(() {\n        _detail = projected;', section);
    final cache = source.indexOf('final cachedWarranty = _cachedWarrantyDetail(', section);
    final extras = source.indexOf('final results = await Future.wait<dynamic>([', section);
    expect(first, greaterThan(section));
    expect(first, greaterThan(origin));
    expect(first, greaterThan(cache),
      reason: 'The exact verified snapshot must persist before editing is enabled');
    expect(first, lessThan(extras),
      reason: 'Optional metadata must never delay first invoice content');
    expect(source.substring(first, extras), contains('_loading = false;'));
    // Optional metadata updates the same authorized document after the first
    // frame, without fabricating payment amounts or skipping the exact scope.
    expect(source, contains('if (!mounted || generation != _loadGeneration) return;'));
  });

  test('Only immediate create routes can skip unrelated payment queue replay', () {
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    final list = File('lib/screens/documents_screen.dart').readAsStringSync();
    final job = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    expect(home, contains('await _openDocument(documentId, freshlyCreated: true);'));
    expect(home, contains('documentId: invoiceId,'));
    expect(home, contains('freshlyCreated: true,'));
    expect(list, contains('freshlyCreated: true,'));
    expect(job, contains('await _openDocument(id!, freshlyCreated: true);'));
    expect(job, contains('freshlyCreated: freshlyCreated,'));
  });

  test('User-facing miles wording never changes persisted schema keys', () {
    final workflow = File('lib/core/mileage_workflow.dart').readAsStringSync();
    final document = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final row = File('lib/widgets/job_mileage_row.dart').readAsStringSync();
    expect(workflow, contains("('Miles In', incoming)"));
    expect(workflow, contains("('Miles Out', outgoing)"));
    expect(workflow, contains("('Miles', legacy)"));
    expect(document, contains("final mileageName = _usesInvoiceMileageOut ? 'Miles Out' : 'Miles'"));
    expect(row, contains("reading('Miles In', mileageIn, onEditIn)"));
    expect(row, contains("reading('Miles Out', mileageOut, onOpenOut)"));
    expect(document, contains("detail['mileage_out']"));
    expect(document, contains("detail['odometer_in']"));
  });
}
