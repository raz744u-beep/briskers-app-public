import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Standard Note actions honor system navigation and keyboard insets', () {
    final source =
        File('lib/screens/jobs/standard_note_editor_sheet.dart').readAsStringSync();
    expect(source, contains('MediaQuery.viewInsetsOf(context).bottom'));
    expect(source, contains('maintainBottomViewPadding: false'));
    expect(source, contains('minimum: EdgeInsets.only(bottom: keyboardOpen ? 0 : 8)'));
    final footer = source.indexOf('standard-note-submit');
    expect(source.lastIndexOf('SafeArea(', footer), greaterThan(0));
  });

  test('Jobs quick edits publish local data before a network flush', () {
    final source = File('lib/screens/jobs_screen.dart').readAsStringSync();
    final mechanic = source.substring(
      source.indexOf('Future<void> _quickEditMechanic('),
      source.indexOf('Future<void> _quickEditPlannedTime('),
    );
    expect(
      mechanic.indexOf('cachedEmployees(widget.businessId)'),
      lessThan(mechanic.indexOf('refreshEmployees(widget.businessId)')),
    );
    final hours = source.substring(
      source.indexOf('Future<void> _quickEditPlannedTime('),
      source.indexOf('Future<void> _changeStatus('),
    );
    for (final code in [mechanic, hours]) {
      expect(code, contains('_patchQuickAdminCard('));
      expect(code, isNot(contains('await _load(refreshRemote: false)')));
      expect(code, contains('_scheduleQuickEditSync();'));
      expect(code, isNot(contains('await _offlineJobAdmin.flush(')));
    }
    expect(source, contains('bool _quickEditSyncRunning = false'));
    expect(source, contains('bool _quickEditSyncRequested = false'));
  });

  test('Primary creation actions use rounded rectangle FABs above dock', () {
    const paths = <String>[
      'lib/screens/jobs_screen.dart',
      'lib/screens/customers/customers_screen.dart',
      'lib/screens/appointments_screen.dart',
      'lib/screens/documents_screen.dart',
      'lib/screens/expenses_screen.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, contains('FloatingActionButton.extended('), reason: path);
      expect(source, contains('shape: RoundedRectangleBorder('), reason: path);
      expect(source, contains("label: const Text('New'"), reason: path);
      expect(source, contains('MediaQuery.viewInsetsOf(context).bottom == 0'),
          reason: path);
    }
  });
  test('Auto Jobs keeps initial list render separate from network refresh', () {
    final source = File('lib/screens/jobs_screen.dart').readAsStringSync();
    expect(source, contains('_jobsRemoteRefreshRunning'));
    expect(source, contains('await readSavedJobs(online: !refreshRemote && _onlineReady)'));
    expect(source, contains('unawaited(() async {'));
  });

  test('New Estimate form does not prefetch customers before first paint', () {
    final source =
        File('lib/screens/jobs/blank_invoice_setup_screen.dart').readAsStringSync();
    final init = source.substring(
      source.indexOf('void initState()'),
      source.indexOf('void dispose()'),
    );
    expect(init, contains('_loading = false;'));
    expect(init, isNot(contains('_loadCustomers();')));
    expect(source, contains('const Duration(milliseconds: 60)'));
    expect(source, contains('await _localCustomers.customers('));
    expect(source, contains('unawaited(_searchUnsyncedCustomers('));
  });

  test('Expenses restores verified complete-period totals during refresh', () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(source, contains('VerifiedExpenseTotalsCache().load(scope)'));
    expect(source, contains('Refreshing previously verified totals'));
    expect(source, contains('ExpensesPeriodTotals.calculate('));
  });

}
