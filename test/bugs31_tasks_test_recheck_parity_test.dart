import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('original TEST Service Tasks per-job Add Recheck is restored', () {
    final workspace = File('lib/screens/payroll/tasks_workspace.dart')
        .readAsStringSync();
    final payroll = File('lib/screens/payroll/owner_payroll_screen.dart')
        .readAsStringSync();

    expect(workspace, contains('final ValueChanged<String>? onAddRecheck;'));
    expect(workspace, contains("title: const Text('Add Recheck')"));
    expect(workspace, contains("widget.onAddRecheck!(task['job_id'] as String)"));
    expect(payroll, contains('onAddRecheck: (jobId) => _addRecheck(jobId: jobId)'));
    expect(payroll, contains('final job = jobId ?? widget.jobId;'));
    expect(payroll, contains("(employee['employee_id'] ?? employee['id']) as String"));
    expect(payroll, contains('_runOwnerTaskEdit(() => _taskEditRepository.createRecheck('));
    expect(payroll, contains('await _run(() async {'));
    expect(payroll, contains('await workflow.assignRecheck('));
  });
}
