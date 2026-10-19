/// Non-persistent helpers for the Tasks & Payroll migration.
 ///
 /// These deliberately do not modify invoice data, job assignments, or
 /// payment records. Wire into the current application only after the
 /// source/version and local-first schema have been verified.
class EmployeeNickname {
  static String display({
    required String fullName,
    String? nickname,
  }) {
    final preferred = nickname?.trim() ?? '';
    if (preferred.isNotEmpty) return preferred;
    final normalized = fullName.trim();
    if (normalized.isEmpty) return 'Unassigned';
    return normalized.split(RegExp(r'\s+')).first;
  }

  static String jobSummary({
    required String leadName,
    String? leadNickname,
    Iterable<String> additionalEmployeeIds = const [],
  }) {
    final name = display(fullName: leadName, nickname: leadNickname);
    final count = additionalEmployeeIds.where((id) => id.trim().isNotEmpty).toSet().length;
    return count == 0 ? name : '$name +$count';
  }
}

/// Stable linkage for one work task across an estimate and its invoice.
/// Tasks must retain their own UUID, independent of a document number.
class TaskDocumentLink {
  const TaskDocumentLink({
    required this.taskId,
    required this.jobId,
    required this.sourceLineId,
    required this.sourceKind,
  });

  final String taskId;
  final String jobId;
  final String sourceLineId;
  final String sourceKind;

  /// Stable import key: repeated offline replays don't create new tasks.
  String get importKey => '$jobId:$sourceKind:$sourceLineId';
}

/// Customer billed hours and approved mechanic hours are independent.
/// This is a value object only; it is not a payroll accounting ledger.
class LaborHours {
  const LaborHours({
    required this.billedHours,
    required this.payrollHours,
  }) : assert(billedHours >= 0), assert(payrollHours >= 0);

  final double billedHours;
  final double payrollHours;

  LaborHours withChangedBilling(double hours) =>
      LaborHours(billedHours: hours, payrollHours: payrollHours);

  LaborHours withChangedPayroll(double hours) =>
      LaborHours(billedHours: billedHours, payrollHours: hours);
}

/// Catalog service defaults; instance overrides do not change the catalog.
class ServiceLaborDefaults {
  static const serviceA = 1.0;
  static const serviceB = 3.0;

  static double defaultFor(String serviceName, {double? catalogHours}) {
    if (catalogHours != null) return catalogHours;
    final normalized = serviceName.trim().toLowerCase();
    if (normalized == 'service a') return serviceA;
    if (normalized == 'service b') return serviceB;
    return 0;
  }
}
