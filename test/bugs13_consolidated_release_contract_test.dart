import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Jobs shows rows before secondary counts and blocks retired Jobs', () {
    final source = File('lib/screens/jobs_screen.dart').readAsStringSync();
    final start = source.indexOf('Future<void> readSavedJobs({required bool online})');
    final end = source.indexOf('if (!mode.forceOnline || !refreshRemote)',start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final read = source.substring(start, end);
    expect(read, contains('final rows = await _localJobs.listJobs('));
    expect(read, contains('final visibleRows = await visibility.filter(rows);'));
    expect(read, contains('_rows = visibleRows;'));
    expect(read, contains('unawaited(metadata);'));
    expect(read, contains('visibility.blockedJobIds()'));
    expect(read, contains('visibility.isCurrent(generation)'));
    // Metadata is intentionally started and detached before the primary
    // awaited rows query completes; current-load guards apply to both.
    expect(read.indexOf('unawaited(metadata);'),
        lessThan(read.indexOf('final rows = await _localJobs.listJobs(')));
  });

  test('Saved Jobs banner is not confused with Auto cached-first paint', () {
    final src = File('lib/screens/jobs_screen.dart').readAsStringSync();
    expect(src, contains('if (_showingLocal &&'));
    expect(src, contains('instance.forceOffline ||'));
    expect(src, contains('_refreshFailed'));
    expect(src, contains('Offline · showing saved jobs'));
    expect(src, contains('Showing saved jobs · refresh needs attention'));
    expect(src, isNot(contains('changes sync when connected')));
  });

  test('Expenses confirms cloud icon only from an actual server ID', () {
    final src = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(src, contains('_serverConfirmedTransactionIds'));
    expect(src, contains('_serverConfirmedTransactionIds.clear()'));
    expect(src, contains('_serverConfirmedBusinessId'));
    expect(src, contains('rows.map((row) => row[\'id\']'));
    expect(src, contains('snapshot.map((row) => row[\'id\']'));
    expect(src, contains('(!pending && !failed &&'));
    expect(src, contains('.contains(verifiedId)'));
    expect(src, contains('Transaction confirmed in shop database'));
    expect(src, contains('Transaction sync not verified'));
    expect(src, contains('Transaction awaiting sync'));
    expect(src, contains('Transaction sync needs attention'));
  });

  test('Consolidated release retains financial fixes and approved Save colors', () {
    final expense = File('lib/screens/expenses_screen.dart').readAsStringSync();
    final invoice = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final customer = File('lib/screens/customers/edit_customer_screen.dart').readAsStringSync();
    expect(expense, contains('ExpensesPeriodTotals.calculate('));
    expect(expense, contains('unawaited(_refreshInvoiceReceipts(businessId))'));
    expect(invoice, contains("ValueKey('invoice-notes-automatic-mileage')"));
    expect(invoice, contains('fontSize: 17.5'));
    expect(customer, contains('backgroundColor: BriskersColors.customerSave'));
  });
}
