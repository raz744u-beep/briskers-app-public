import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/labor_task_reconciler.dart';
import 'package:briskers_app/core/task_labor_link_planner.dart';

void main() {
  const oil = LaborLineCandidate(lineId: 'line-a', jobId: 'job-12',
    name: 'Labor', description: 'Replace oil pan', lineKind: 'item', quantity: 2);
  const part = LaborLineCandidate(lineId: 'line-p', jobId: 'job-12',
    name: 'Oil pan', lineKind: 'item', quantity: 1);

  test('existing job task reused instead of duplicated', () {
    final decisions = LaborTaskReconciler.plan(
      lines: [oil, oil, part],
      existing: [const ExistingTaskLink(taskId: 'task-12', jobId: 'job-12', sourceLineId: 'line-a')],
    );
    expect(decisions, hasLength(1));
    expect(decisions.single.needsCreation, false);
    expect(decisions.single.existingTaskId, 'task-12');
  });

  test('same source line in another job does not incorrectly reuse task', () {
    final decisions = LaborTaskReconciler.plan(
      lines: [oil],
      existing: [const ExistingTaskLink(taskId: 'other-task', jobId: 'other-job', sourceLineId: 'line-a')],
    );
    expect(decisions.single.needsCreation, true);
  });

  test('unknown eligible labor line proposes one new task', () {
    final decisions = LaborTaskReconciler.plan(lines: [oil], existing: []);
    expect(decisions.single.needsCreation, true);
  });
}
