import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('Job Expense opens local cached detail rather than network when offline', () {
    final detail = source('lib/screens/expenses/expense_detail_screen.dart');
    final jobs = source('lib/screens/jobs/job_detail_screen.dart');
    expect(detail, contains('BriskersConnectionModeController.instance.forceOffline'));
    expect(detail, contains('final detail = saved ?? widget.cachedDetail;'));
    expect(detail, contains('Future<void> _loadOffline() async'));
    expect(jobs, contains('cachedDetail: cached,'));
    expect(jobs, contains('Future<void> _openExpense(String transactionId)'));
  });

  test('Jobs status filter precedes Sort and expenses return without loader', () {
    final jobs = source('lib/screens/jobs_screen.dart');
    expect(jobs.indexOf("tooltip: tr('filterJobs')"),
        lessThan(jobs.indexOf("tooltip: 'Sort jobs'")));
    final expenses = source('lib/screens/expenses_screen.dart');
    final open = expenses.substring(expenses.indexOf('Future<void> _openTransaction('),
      expenses.indexOf('Future<void> _editTransactionFromList'));
    expect(open, contains('unawaited(_load(showLoading: false));'));
  });

  test('Test cleanup uses bounded Owner-only server discovery', () {
    final gateway = source('lib/services/test_job_cleanup_gateway.dart');
    expect(gateway, contains('briskers_test_job_cleanup_candidates_v1'));
    expect(gateway, isNot(contains('const BriskersApi().jobs(businessId)')));
    expect(gateway, contains('verifyOwner'));
  });

  test('sync status names queued expense photo uploads clearly', () {
    final status = source('lib/screens/settings/local_sync_status_screen.dart');
    expect(status, contains("case 'financial_photo':"));
    expect(status, contains('Expense receipt photo upload'));
  });

  test('Standard Notes support persistent category selection and reordering', () {
    final rules = source('lib/core/standard_note_rules.dart');
    for (final key in ['service','warranty','inspection','advisory','general']) {
      expect(rules, contains("'$key'"));
    }
    final picker = source('lib/screens/jobs/standard_note_picker_sheet.dart');
    expect(picker, contains("footer: _group('general')"));
    expect(picker, contains('onReorderItem: _reorderCategories'));
    expect(picker, contains('_reorderNotes('));
    expect(picker, contains('Search notes'));
    final editor = source('lib/screens/jobs/standard_note_editor_sheet.dart');
    expect(editor, contains("'category_key': _category"));
    expect(editor, contains('standard-note-category'));
    final service = source('lib/services/local_standard_notes_service.dart');
    expect(service, contains("'category_key'"));
  });
}
