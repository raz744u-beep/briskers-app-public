import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Job detail paints a verified local record before linked documents', () {
    final source =
        File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    final loadStart = source.indexOf('Future<void> _load() async {');
    final loadEnd = source.indexOf('if (forceOffline) {', loadStart);
    expect(loadStart, greaterThanOrEqualTo(0));
    expect(loadEnd, greaterThan(loadStart));
    final localPath = source.substring(loadStart, loadEnd);
    expect(localPath, contains('_localJobs.jobDetail('));
    expect(localPath, contains('_loading = false;'));
    expect(localPath, contains('unawaited(_hydrateLocalJobDocuments(epoch));'));
    expect(
      localPath,
      isNot(contains('await _localDocumentsForJob()')),
      reason: 'The linked-documents lookup must not gate Job first paint.',
    );
    expect(source, contains('if (!_currentLoad(epoch) || !_showingLocal || _onlineReady ||'));
  });

  test('Primary New buttons stay above the dock and use rounded rectangles', () {
    final entries = <String, String>{
      'lib/screens/jobs_screen.dart': 'BriskersColors.jobs',
      'lib/screens/customers/customers_screen.dart':
          'BriskersColors.actionBlue',
    };
    for (final entry in entries.entries) {
      final source = File(entry.key).readAsStringSync();
      expect(source, contains('FloatingActionButton.extended('),
          reason: entry.key);
      expect(source, contains('shape: RoundedRectangleBorder('),
          reason: entry.key);
      expect(source, contains('borderRadius: BorderRadius.circular(14)'),
          reason: entry.key);
      expect(source, contains('right: 16,'),
          reason: entry.key);
      expect(source, contains('bottom: 16,'),
          reason: entry.key);
      expect(source, contains('MediaQuery.viewInsetsOf(context).bottom == 0'),
          reason: entry.key);
      expect(source, contains('backgroundColor: ${entry.value}'),
          reason: entry.key);
      expect(source, contains("label: const Text('New'"),
          reason: entry.key);
    }
    expect(File('lib/screens/jobs_screen.dart').readAsStringSync(),
        isNot(contains("tooltip: 'New Job',\n                        style: IconButton.styleFrom(")));
    expect(File('lib/screens/customers/customers_screen.dart').readAsStringSync(),
        isNot(contains('onPressed: _canManageCustomers ? _add : null')));
  });

  test('Appointments, Documents and Expenses retain the approved New action', () {
    const paths = <String>[
      'lib/screens/appointments_screen.dart',
      'lib/screens/documents_screen.dart',
      'lib/screens/expenses_screen.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, contains('FloatingActionButton.extended('), reason: path);
      expect(source, contains('shape: RoundedRectangleBorder('), reason: path);
      expect(source, contains('borderRadius: BorderRadius.circular(14)'),
          reason: path);
      expect(source, contains('MediaQuery.viewInsetsOf(context).bottom == 0'),
          reason: path);
      expect(source, contains("label: const Text('New'"), reason: path);
    }
    final appointments =
        File('lib/screens/appointments_screen.dart').readAsStringSync();
    expect(appointments, contains('backgroundColor: BriskersColors.appointments'));
    expect(appointments, isNot(contains("tooltip: 'Add appointment',\\n                      style: IconButton.styleFrom(")));

    final documents =
        File('lib/screens/documents_screen.dart').readAsStringSync();
    expect(documents, contains('backgroundColor: accent'));
    expect(documents, isNot(contains('IconButton.filled(\\n                    tooltip: _estimate')));

    final expenses =
        File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(expenses, contains('backgroundColor: BriskersColors.expenses'));
    expect(expenses, isNot(contains("tooltip: 'Add transaction',\\n                        style: IconButton.styleFrom(")));
  });

  test('Auto customer Findings paints cache before network and photos', () {
    final source = File(
      'lib/screens/customers/customer_vehicle_findings_section.dart',
    ).readAsStringSync();
    final begin = source.indexOf('Future<List<Map<String, dynamic>>> _allFindings(');
    final end = source.indexOf('String _vehicleLabel(', begin);
    expect(begin, greaterThanOrEqualTo(0));
    expect(end, greaterThan(begin));
    final path = source.substring(begin, end);
    expect(path, contains('final local = await cachedFindings();'));
    expect(path, contains('final remote = await loadRemote();'));
    expect(path, contains('Future<List<Map<String, dynamic>>>.value(remote)'));
    expect(path, contains('unawaited(() async {'));
    expect(path, contains('_attachmentCache.getOrDownload(bucket, key)'));
    expect(path.indexOf('final local = await cachedFindings();'),
        lessThan(path.lastIndexOf('final remote = await loadRemote();')));
  });
}
