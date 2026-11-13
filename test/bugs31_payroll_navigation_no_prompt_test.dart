import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/screens/payroll/owner_payroll_screen.dart')
      .readAsStringSync();

  test('Owner navigation and local refresh never use a payment unlock', () {
    // Opening a task form, returning from the weekly review, changing
    // employees and refreshing after General Tasks must not call _run.
    expect(source, isNot(contains('_run(() async {})')));
    expect(source, contains('if (!mounted || !_canView) return;'));
    expect(source, contains('if (mounted && _canView) await _load();'));
    expect(source, contains('if (_canView) unawaited(_load());'));
  });

  test('General Task status changes use Owner identity rather than payment grant', () {
    final start = source.indexOf('Future<void> _changeGeneralTaskStatus(');
    final end = source.indexOf('Future<void> _refreshLan()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final action = source.substring(start, end);
    expect(action, contains('_runOwnerTaskEdit'));
    expect(action, contains('_taskEditRepository.setShopTaskStatus'));
    expect(action, isNot(contains('authorizeLocal')));
    expect(action, isNot(contains('_run(')));
    expect(source, contains('Widget _tasksTab() => EmployeeWorkReview('));
    expect(source, isNot(contains('_updateEmployeeGeneralTask(')));
    expect(source, contains("_changeGeneralTaskStatus(row['employee_id'] as String, id, status)"));
    expect(source, contains("if (!_canView) throw StateError('Sign in as Owner to edit tasks.')"));
  });

  test('editing mechanic hours and accepting unpaid work use Owner identity', () {
    final editStart = source.indexOf('Future<void> _runOwnerTaskEdit(');
    final editEnd = source.indexOf('Future<void> _changeGeneralTaskStatus(', editStart);
    expect(editStart, greaterThanOrEqualTo(0));
    expect(editEnd, greaterThan(editStart));
    final guarded = source.substring(editStart, editEnd);
    expect(guarded, contains('if (_busy || !_canView) return;'));
    expect(guarded, isNot(contains('authorizeLocal')));
    expect(source, contains("_taskEditRepository.recordAllocatedTime("));
    expect(source, contains("await _runOwnerTaskEdit(() => _taskEditRepository.editAllocation("));
    expect(source, contains("_taskEditRepository.acceptChangedAssignment("));
    expect(source, isNot(contains('_taskStatusRepository')));
  });

  test('opening mechanic assignment picker never requires payment unlock', () {
    final start = source.indexOf('Future<void> _assign(');
    final end = source.indexOf('Future<void> _recordTaskProgress(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final assign = source.substring(start, end);
    final picker = assign.substring(0, assign.indexOf('final employee = await showTaskSelection'));
    expect(picker, contains('if (!_canView) return;'));
    expect(picker, contains('_viewRepository.employees()'));
    expect(picker, isNot(contains('_run(')));
    expect(picker, isNot(contains('authorizeLocal')));
    // The original TEST's local assignment is an Owner task edit.
    // Only the paired LAN writer uses the extra OS payment grant.
    final write = assign.substring(assign.indexOf('final employee = await showTaskSelection'));
    expect(write, contains('await _runOwnerTaskEdit(() => assign(pairedDevice: false))'));
    expect(write, contains('await _run(() => assign(pairedDevice: true))'));
    expect(write, contains('_taskEditRepository.assignExistingService('));
    expect(write, contains('await _db.transaction(apply)'));
    expect(write, contains('await workflow.assign('));
    expect(write, contains('if (pairedDevice) {'));
    expect(write, contains('await apply();'));
    expect(write, contains("if (!_canView) throw StateError('Owner account changed during assignment.')"));
  });

  test('local recheck uses signed-in Owner task edit; paired LAN stays protected', () {
    final begin = source.indexOf('Future<void> _addRecheck(');
    final end = source.indexOf('Future<void> _recordWeekly(', begin);
    expect(begin, greaterThanOrEqualTo(0));
    expect(end, greaterThan(begin));
    final action = source.substring(begin, end);
    expect(action, contains('if (!mounted || !_canView) return;'));
    expect(action, contains('if (!paired) {'));
    expect(action, contains('_runOwnerTaskEdit(() => _taskEditRepository.createRecheck('));
    expect(action, contains('await _run(() async {'));
    expect(action, contains('await workflow.assignRecheck('));
    expect(action, contains('if (mounted) setState(() => _error = error.toString())'));
    expect(action, contains('PayrollLanEnrollment(identity)'));
    expect(action, contains('operation: operation'));
  });

  test('one General Task editor saves locally under Owner identity, not payment grant', () {
    final start=source.indexOf('Future<void> _generalEditor(');
    final end=source.indexOf('Widget _tasksTab()',start);
    expect(start,greaterThanOrEqualTo(0));expect(end,greaterThan(start));
    final action=source.substring(start,end);
    expect(action,contains('GeneralTaskEditor('));
    expect(action,contains('_taskEditRepository.saveGeneralTask('));
    expect(action,contains("if(!_canView)throw StateError('Owner account changed.')"));
    expect(action,isNot(contains('authorizeLocal(')));
    expect(action,isNot(contains('await _run(')));
    expect(source,contains('assertOwnerGrant: () {'));
    expect(source,contains("if (!_canView) throw StateError('Sign in as Owner to edit tasks.')"));
  });

  test('one Service Task editor reads and saves locally without payment unlock', () {
    final start=source.indexOf('Future<void> _serviceEditor(');
    final end=source.indexOf('Future<void> _createEmployeeGeneralTask()',start);
    expect(start,greaterThanOrEqualTo(0));expect(end,greaterThan(start));
    final task=source.substring(start,end);
    expect(task,contains('_viewRepository.employees()'));
    expect(task,contains('ServiceTaskEditor('));
    expect(task,contains('_taskEditRepository.saveServiceTask('));
    expect(task,contains("if (!_canView) throw StateError('Owner account changed.')"));
    expect(task,isNot(contains('await _repository.employees()')));
    expect(task,isNot(contains('await _run(')));
    final repo=File('lib/services/local_payroll_repository.dart').readAsStringSync();
    final editor=repo.substring(repo.indexOf('Future<void> saveServiceTask('),repo.indexOf('Future<void> applyOwnerNov13WorkDates()'));
    expect(editor,contains('db.transaction('));expect(editor,contains('_authorize()'));expect(editor,contains('createRecheck('));
  });

  test('payment, repayments and opening advances still require owner proof', () {
    final weeklyStart = source.indexOf('Future<void> _recordWeekly(');
    final weeklyEnd = source.indexOf('String _operationId()', weeklyStart);
    expect(weeklyStart, greaterThanOrEqualTo(0));
    expect(weeklyEnd, greaterThan(weeklyStart));
    expect(source.substring(weeklyStart, weeklyEnd),
        contains('verifyPayment: true, rethrowError: true'));

    final ledgerStart = source.indexOf(
        'Future<LocalPayrollRepository> _localPaymentLedger(');
    final ledgerEnd = source.indexOf('Future<void> _saveOpening()', ledgerStart);
    expect(ledgerStart, greaterThanOrEqualTo(0));
    expect(ledgerEnd, greaterThan(ledgerStart));
    final ledger = source.substring(ledgerStart, ledgerEnd);
    expect(ledger, contains('_assertOwner();'));
    expect(ledger, contains('assertOwnerGrant: _assertOwner'));

    for (final startMarker in [
      'Future<void> _saveOpening()',
      'Future<void> _saveRepayment()',
    ]) {
      final start = source.indexOf(startMarker);
      expect(start, greaterThanOrEqualTo(0));
      final next = source.indexOf('\n  }', start);
      expect(source.substring(start, next), contains('verifyPayment: true'));
    }
  });
}
