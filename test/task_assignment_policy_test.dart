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

  test('job chooser excludes other vehicles and closed jobs', () {
    final eligible = TaskJobChooser.eligible(
      customerId: 'customer-1', vehicleId: 'vehicle-1',
      jobs: const [
        OpenJobChoice(jobId: 'J1', customerId: 'customer-1',
          vehicleId: 'vehicle-1', isOpen: true),
        OpenJobChoice(jobId: 'J2', customerId: 'customer-1',
          vehicleId: 'vehicle-1', isOpen: false),
        OpenJobChoice(jobId: 'J3', customerId: 'customer-1',
          vehicleId: 'vehicle-2', isOpen: true),
        OpenJobChoice(jobId: 'J4', customerId: 'customer-2',
          vehicleId: 'vehicle-1', isOpen: true),
      ],
    );
    expect(eligible.map((job) => job.jobId).toList(), ['J1']);
  });

  test('job chooser rejects duplicate identities instead of guessing', () {
    expect(() => TaskJobChooser.eligible(
      customerId: 'c', vehicleId: 'v',
      jobs: const [
        OpenJobChoice(jobId: 'J1', customerId: 'c',
          vehicleId: 'v', isOpen: true),
        OpenJobChoice(jobId: 'J1', customerId: 'c',
          vehicleId: 'v', isOpen: true),
      ],
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
