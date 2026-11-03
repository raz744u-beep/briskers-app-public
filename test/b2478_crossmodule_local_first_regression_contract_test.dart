import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();
String section(String text, String from, String until) {
  final a = text.indexOf(from);
  final b = text.indexOf(until, a);
  if (a < 0 || b < a) {
    throw StateError('Missing section: $from -> $until');
  }
  return text.substring(a, b);
}

void main() {
  test('Job Detail mechanic, hours and complaint commit locally before sync',
      () {
    final s = source('lib/screens/jobs/job_detail_screen.dart');
    final sections = [
      section(s, 'Future<void> _changeAssignment() async {',
          'Future<void> _requestJob() async {'),
      section(s, 'Future<void> _changePlannedHours() async {',
          'Future<String?> _editTextSheet('),
      section(s, 'Future<void> _editComplaint() async {',
          'Future<void> _editWorkSummary('),
    ];
    for (final code in sections) {
      expect(code, contains('++_loadEpoch;'));
      expect(code, contains('_scheduleJobAdminSync();'));
      expect(code, contains('setState(() {'));
      expect(code, isNot(contains('await _offlineJobAdmin.flush(')));
      expect(code, isNot(contains('await _load();')));
    }
    final employees = sections.first;
    expect(employees,
        isNot(contains('await _offlineJobAdmin.refreshEmployees(')));
  });

  test('Jobs list mechanic and hours do not perform full list re-query',
      () {
    final s = source('lib/screens/jobs_screen.dart');
    final from = s.indexOf('Future<void> _quickEditMechanic(');
    final time = s.indexOf('Future<void> _quickEditPlannedTime(', from);
    final end = s.indexOf('void _applyLocalStatus(', time);
    expect(from, greaterThanOrEqualTo(0));
    expect(time, greaterThan(from));
    expect(end, greaterThan(time));
    for (final code in [s.substring(from, time), s.substring(time, end)]) {
      expect(code, contains('_patchQuickAdminCard('));
      expect(code, contains('_scheduleQuickEditSync();'));
      expect(code, isNot(contains('await _load(refreshRemote: false)')));
      expect(code, isNot(contains('await _offlineJobAdmin.flush(')));
    }
  });

  test('Expenses create/edit/copy opens saved first frame and refreshes in '
      'background', () {
    final entry = source('lib/screens/expenses/expense_entry_screen.dart');
    expect(entry, contains('_loading = _editing || _copying;'));
    expect(entry, contains('await _localFinancial.loadOptions('));
    final list = source('lib/screens/expenses_screen.dart');
    final a = list.indexOf('Future<void> _editTransactionFromList(');
    final b = list.indexOf('Future<void> _deleteTransactionFromList(', a);
    expect(a, greaterThanOrEqualTo(0));
    expect(b, greaterThan(a));
    final editors = list.substring(a, b);
    expect(
      'unawaited(_load(showLoading: false, forceTotals: true))'
          .allMatches(editors).length,
      2,
    );
    expect(editors, isNot(contains('await _load(forceTotals: true)')));
  });

  test('Appointments additions and edits paint local list independently',
      () {
    final sourceCode = source('lib/screens/appointments_screen.dart');
    final paths = section(sourceCode, 'Future<void> _addAppointment() async {',
        'Future<bool> _confirm(');
    expect('await _loadLocal(reportError: true)'.allMatches(paths).length, 2);
    expect('unawaited(_load(afterMutation: true))'.allMatches(paths).length, 2);
    expect(paths, isNot(contains('await _load(afterMutation: true)')));
  });

  test('Invoices retain local-first line save, permission guards and replay',
      () {
    final detail = source('lib/screens/jobs/job_document_screen.dart');
    expect(detail, contains('Future<void> _runAddLine('));
    expect(detail, contains('_startLineBackgroundSync();'));
    expect(detail, contains('++_loadGeneration;'));
    final documentEdit = source(
        'lib/services/offline_document_edit_service.dart');
    expect(documentEdit, contains('await _database.transaction(() async {'));
    expect(documentEdit, contains("'add_line'"));
    final journal = source(
        'lib/services/local_financial_totals_journal.dart');
    expect(journal, contains('reconcileAndSaveBaseline('));
  });

  test('A newer queued Job edit cannot be acknowledged by an older RPC',
      () {
    final code = source('lib/services/offline_job_admin_service.dart');
    expect(code, contains("current.single.read<String>('payload_json') !="));
    expect(code, contains("row.read<String>('payload_json')"));
    expect(code, contains('AND NOT EXISTS ('));
  });
}
