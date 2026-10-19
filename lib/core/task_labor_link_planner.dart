/// Pure planning logic. Persistence and offline synchronization are deliberately
/// separate so existing invoices are never modified just by viewing them.
class LaborLineCandidate {
  const LaborLineCandidate({
    required this.lineId,
    required this.jobId,
    required this.name,
    required this.lineKind,
    required this.quantity,
    this.description,
    this.containsLabor = false,
    this.defaultPayrollHours,
  });

  final String lineId;
  final String jobId;
  final String name;
  final String? description;
  final String lineKind;
  final double quantity;
  final bool containsLabor;
  final double? defaultPayrollHours;
}

class ProposedJobTask {
  const ProposedJobTask({
    required this.key,
    required this.jobId,
    required this.description,
    required this.payrollHours,
    required this.sourceLineId,
  });

  final String key;
  final String jobId;
  final String description;
  final double payrollHours;
  final String sourceLineId;
}

class TaskLaborLinkPlanner {
  /// Explicit labor types, catalog-flagged services, and named legacy
  /// 'Labor' lines are eligible. Ordinary parts, supplies, tax and discount
  /// lines never create tasks.
  static bool isLaborBearing(LaborLineCandidate line) {
    if (line.containsLabor) return true;
    if (line.lineKind.toLowerCase() == 'labor') return true;
    return line.lineKind.toLowerCase() == 'item' &&
        line.name.trim().toLowerCase() == 'labor';
  }

  /// The key deliberately ignores invoice number. A single source line
  /// must map to the same task after retries/restarts.
  static ProposedJobTask? propose(LaborLineCandidate line) {
    if (!isLaborBearing(line)) return null;
    final fallback = line.name.trim();
    final detail = line.description?.trim();
    return ProposedJobTask(
      key: '${line.jobId}:line:${line.lineId}',
      jobId: line.jobId,
      sourceLineId: line.lineId,
      description: detail != null && detail.isNotEmpty ? detail : fallback,
      payrollHours: line.defaultPayrollHours ?? line.quantity,
    );
  }
}
