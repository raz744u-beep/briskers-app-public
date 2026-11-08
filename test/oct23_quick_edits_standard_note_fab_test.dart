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

  test('Jobs list displays local allocations without standalone hour edits', () {
    final jobs = File('lib/screens/jobs_screen.dart').readAsStringSync();
    expect(jobs,contains('_localJobs.allocationHours('));
    expect(jobs,isNot(contains('_quickEditPlannedTime(')));
    expect(jobs,isNot(contains('_quickEditMechanic(')));
  });
  test('Primary New actions stay in approved positions with rounded styling', () {
    for (final path in const [
      'lib/screens/jobs_screen.dart',
      'lib/screens/customers/customers_screen.dart',
      'lib/screens/appointments_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('FloatingActionButton.extended('), reason: path);
      expect(source, contains('shape: RoundedRectangleBorder('), reason: path);
      expect(source, contains("label: const Text('New'"), reason: path);
      expect(source, contains('MediaQuery.viewInsetsOf(context).bottom == 0'),
          reason: path);
    }
    final documents=File('lib/screens/documents_screen.dart').readAsStringSync();
    expect(documents, contains("ValueKey('documents-inline-new')"));
    expect(documents, contains('shape: RoundedRectangleBorder('));
    expect(documents, contains("label: const Text('New'"));
    expect(documents, isNot(contains('FloatingActionButton.extended(')));

    // Owner-approved Nov 6 Expenses change: dedicated full-width Search
    // and the main New action floating at the lower right.
    final expenses=File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(expenses, contains("ValueKey('expenses-new-floating')"));
    expect(expenses, contains("label: const Text('New'"));
    expect(expenses, contains('FloatingActionButton.extended('));
    expect(expenses, contains('FloatingActionButtonLocation.endFloat'));
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
