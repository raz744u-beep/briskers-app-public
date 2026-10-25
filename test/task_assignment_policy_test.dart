import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/task_assignment_policy.dart';

void main() {
  test('unapproved estimate does not assign labor tasks', () {
    expect(() => TaskAssignmentPolicy.decide(
      origin: TaskEntryPoint.invoiceLabor,
      choice: TaskJobChoice.createNewJob,
      customerId: 'c', vehicleId: 'v',
      originatesFromUnapprovedEstimate: true,
    ), throwsStateError);
  });

  test('existing job must be verified open', () {
    expect(() => TaskAssignmentPolicy.decide(
      origin: TaskEntryPoint.tasks,
      choice: TaskJobChoice.existingOpenJob,
      customerId: 'c', vehicleId: 'v',
      selectedJobId: 'closed-job',
    ), throwsStateError);
    final choice = TaskAssignmentPolicy.decide(
      origin: TaskEntryPoint.employee,
      choice: TaskJobChoice.existingOpenJob,
      customerId: 'c', vehicleId: 'v',
      selectedJobId: 'open-job', selectedJobIsOpen: true,
    );
    expect(choice.action, TaskAttachAction.attachExisting);
    expect(choice.jobId, 'open-job');
  });

  test('new job requires customer and vehicle, never auto-creates invoice', () {
    final decision = TaskAssignmentPolicy.decide(
      origin: TaskEntryPoint.tasks,
      choice: TaskJobChoice.createNewJob,
      customerId: 'c', vehicleId: 'v',
    );
    expect(decision.action, TaskAttachAction.createJob);
    expect(decision.jobId, isNull);
    expect(() => TaskAssignmentPolicy.decide(
      origin: TaskEntryPoint.tasks,
      choice: TaskJobChoice.createNewJob, customerId: 'c',
    ), throwsStateError);
  });

  test('internal task has no customer or job', () {
    final decision = TaskAssignmentPolicy.decide(
      origin: TaskEntryPoint.employee,
      choice: TaskJobChoice.shopInternal,
    );
    expect(decision.action, TaskAttachAction.internalOnly);
    expect(() => TaskAssignmentPolicy.decide(
      origin: TaskEntryPoint.employee,
      choice: TaskJobChoice.shopInternal, customerId: 'c',
    ), throwsStateError);
  });

  test('lead assignment cannot overwrite explicit mechanic override', () {
    expect(TaskAssignmentPolicy.mechanicFor(
      mainMechanicId: 'chris', existingMechanicId: 'kam',
      explicitlyAssigned: true,
    ), 'kam');
    expect(TaskAssignmentPolicy.mechanicFor(
      mainMechanicId: 'chris', existingMechanicId: null,
      explicitlyAssigned: false,
    ), 'chris');
  });
}
