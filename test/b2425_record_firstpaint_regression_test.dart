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

  test('Invoice Findings reuses customer photo-capable local-first UI', () {
    final invoice =
        File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final entry = invoice.indexOf('Future<void> _showInvoiceFindings()');
    final next = invoice.indexOf('Future<void> _emailPdf()', entry);
    expect(entry, greaterThanOrEqualTo(0));
    expect(next, greaterThan(entry));
    final code = invoice.substring(entry, next);
    expect(invoice,
        contains("import '../customers/customer_vehicle_findings_section.dart';"));
    expect(code, contains('CustomerVehicleFindingsSection('));
    expect(code, contains("cacheScopeKey: 'finding-vehicle-\$vehicleId'"));
    expect(code, contains('initiallyExpanded: true'));
    expect(code, contains('canDelete: widget.isOwner'));
    expect(code, contains('canManageCustomerActions(_navigationRoleCode)'));
    expect(code, isNot(contains('await _api.vehicleFindings(')),
      reason: 'Opening Invoice Findings should not wait for Supabase.');
    expect(code, isNot(contains('ListTile(\n                            onTap:')),
      reason: 'The stripped-down invoice-only list must not return.');

    final shared = File(
      'lib/screens/customers/customer_vehicle_findings_section.dart',
    ).readAsStringSync();
    expect(shared, contains('VehicleFindings('));
    expect(shared, contains("widget.cacheScopeKey ?? 'findings'"));
    expect(shared, contains('final scopedRows = rows.where((row)'));
    expect(shared, contains('vehicleIds.contains(vehicle)'));
    expect(shared, contains('_findingThumbnail('));
    expect(shared, contains('_showPhotoGallery('));
    expect(shared, contains('final local = await cachedFindings();'));
  });

  test('Customer tap supplies already-visible scoped row preview', () {
    final list = File('lib/screens/customers/customers_screen.dart')
        .readAsStringSync();
    final detail = File('lib/screens/customers/customer_detail_screen.dart')
        .readAsStringSync();
    expect(list, contains('initialCustomerSummary: Map<String, dynamic>.from(customer)'));
    expect(detail, contains('final Map<String, dynamic>? initialCustomerSummary'));
    expect(detail, contains("customer['name'] ??= customer['display_name']"));
    expect(detail, contains('Opening saved customer details'));
    expect(detail, contains('floatingActionButton: _data == null'));
  });

  test('Job and Invoice expense rows pass read-only previews on tap', () {
    final job = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    final invoice =
        File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    expect(job, contains('cachedDetail: cached,'));
    expect(invoice, contains('cachedDetail: Map<String, dynamic>.from(item)'));
    expect(invoice, contains('cachedDetail: Map<String, dynamic>.from(expense)'));
    final detail = File('lib/screens/expenses/expense_detail_screen.dart')
        .readAsStringSync();
    expect(detail, contains("..['editable'] = false"));
    expect(detail, contains("..['deletable'] = false"));
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
