import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Jobs header has a flexible spacer before right-side total', () {
    final s = File('lib/screens/jobs_screen.dart').readAsStringSync();
    expect(s, contains("const Spacer(),\n                    if (_rows != null)"));
  });

  test('Job finding Resolve explicitly selects the repairing Job', () {
    final s = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    final chooser = s.indexOf('Future<String?> _chooseFindingResolutionJob(');
    final resolver = s.indexOf('Future<void> _resolveFinding(', chooser);
    expect(chooser, greaterThan(0));
    expect(resolver, greaterThan(chooser));
    final code = s.substring(chooser, resolver + 850);
    expect(code, contains('customer_id=? AND vehicle_id=?'));
    expect(code, contains('FindingJobChoice.completedHistory'));
    expect(code, isNot(contains('Confirm repairing repair')));
    expect(code, contains('Confirm repair'));
    expect(code, contains('repairJobId'));
    expect(code, contains('await _chooseFindingResolutionJob(finding)'));
    expect(code, isNot(contains(
      'widget.businessId, finding, widget.jobId));')));
  });

  test('Finding cards use a solid surface and never force a stale backdrop', () {
    final s = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    final start = s.lastIndexOf('class _JobDrawerSurface');
    final code = s.substring(start);
    expect(code, contains('Theme.of(context).colorScheme.surface'));
    expect(code, isNot(contains('color.withValues(alpha: 0.045)')));
  });

  test('Invoice Findings actions are awaited after modal dismissal', () {
    final s = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final start = s.indexOf('Future<void> _showInvoiceFindings()');
    final end = s.indexOf('Future<void> _emailPdf()', start);
    final code = s.substring(start, end);
    expect(code, contains('final requestedAction = await showModalBottomSheet<String>'));
    expect(code, contains("Navigator.pop(sheetContext, 'add')"));
    expect(code, contains("await _addInvoiceFinding();"));
    expect(code, contains('await _runInvoiceFindingMutation('));
    expect(code, contains('await _refreshInvoiceFindingsBanner();'));
  });
}
