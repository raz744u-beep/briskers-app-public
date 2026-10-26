/// Task origin and attachment policy for the isolated Tasks TEST app.
///
/// A customer record is not a task entry point. Estimates are proposals, not
/// work assignments. Job creation is always an explicit user choice when a
/// task is created from Tasks or Employee Work.
enum TaskEntryPoint { tasks, employee, invoiceLabor }
enum TaskJobChoice { existingOpenJob, createNewJob, shopInternal }
enum TaskAttachAction { attachExisting, createJob, internalOnly }

class TaskAttachmentDecision {
  const TaskAttachmentDecision({
    required this.action,
    this.jobId,
    this.customerId,
    this.vehicleId,
  });

  final TaskAttachAction action;
  final String? jobId;
  final String? customerId;
  final String? vehicleId;
}

class TaskAssignmentPolicy {
  const TaskAssignmentPolicy._();

  static TaskAttachmentDecision decide({
    required TaskEntryPoint origin,
    required TaskJobChoice choice,
    String? customerId,
    String? vehicleId,
    String? selectedJobId,
    bool selectedJobIsOpen = false,
    bool originatesFromUnapprovedEstimate = false,
  }) {
    if (originatesFromUnapprovedEstimate) {
      throw StateError('Unapproved estimates cannot create assigned tasks.');
    }
    if (choice == TaskJobChoice.shopInternal) {
      if (selectedJobId != null || customerId != null || vehicleId != null) {
        throw StateError('Internal shop tasks must not create a customer job.');
      }
      return const TaskAttachmentDecision(action: TaskAttachAction.internalOnly);
    }
    if (customerId == null || customerId.trim().isEmpty ||
        vehicleId == null || vehicleId.trim().isEmpty) {
      throw StateError('Customer-related tasks require a customer and vehicle.');
    }
    if (choice == TaskJobChoice.existingOpenJob) {
      if (selectedJobId == null || selectedJobId.trim().isEmpty ||
          !selectedJobIsOpen) {
        throw StateError('Select a verified open job before attaching a task.');
      }
      return TaskAttachmentDecision(
        action: TaskAttachAction.attachExisting,
        jobId: selectedJobId,
        customerId: customerId,
        vehicleId: vehicleId,
      );
    }
    if (selectedJobId != null) {
      throw StateError('A new job request cannot also select an existing job.');
    }
    return TaskAttachmentDecision(
      action: TaskAttachAction.createJob,
      customerId: customerId,
      vehicleId: vehicleId,
    );
  }

  /// Inherited allocations may follow the lead; manually chosen mechanics
  /// must not be overwritten when the Main Mechanic changes.
  static String? mechanicFor({
    required String? mainMechanicId,
    required String? existingMechanicId,
    required bool explicitlyAssigned,
  }) => explicitlyAssigned ? existingMechanicId : mainMechanicId;
}

class OpenJobChoice {
  const OpenJobChoice({
    required this.jobId,
    required this.customerId,
    required this.vehicleId,
    required this.isOpen,
  });

  final String jobId;
  final String customerId;
  final String vehicleId;
  final bool isOpen;
}

/// Return only open jobs for the exact customer AND vehicle. A task creator
/// must still explicitly choose one or request a new job. No silent linking.
class TaskJobChooser {
  const TaskJobChooser._();

  static List<OpenJobChoice> eligible({
    required String customerId,
    required String vehicleId,
    required Iterable<OpenJobChoice> jobs,
  }) {
    final result = <OpenJobChoice>[];
    final ids = <String>{};
    for (final job in jobs) {
      if (!job.isOpen || job.customerId != customerId ||
          job.vehicleId != vehicleId) { continue; }
      if (job.jobId.trim().isEmpty || !ids.add(job.jobId)) {
        throw StateError('Duplicate or invalid open job identity');
      }
      result.add(job);
    }
    return result;
  }
}
