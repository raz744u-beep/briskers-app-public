import 'task_labor_link_planner.dart';

/// Pure, side-effect-free reconciliation of invoice/estimate labor rows
/// against previously linked job tasks. No database writes occur here.
class ExistingTaskLink {
  const ExistingTaskLink({
    required this.taskId,
    required this.jobId,
    required this.sourceLineId,
  });
  final String taskId;
  final String jobId;
  final String sourceLineId;
}

class LaborTaskDecision {
  const LaborTaskDecision({
    required this.proposal,
    required this.existingTaskId,
  });
  final ProposedJobTask proposal;
  final String? existingTaskId;
  bool get needsCreation => existingTaskId == null;
}

class LaborTaskReconciler {
  /// Only accepted line IDs may link tasks. An estimate converted to an
  /// invoice should pass the original estimate-line ID as the canonical
  /// sourceLineId when available, preventing duplicate tasks.
  static List<LaborTaskDecision> plan({
    required Iterable<LaborLineCandidate> lines,
    required Iterable<ExistingTaskLink> existing,
  }) {
    final byKey = <String, String>{};
    for (final entry in existing) {
      byKey['${entry.jobId}:${entry.sourceLineId}'] = entry.taskId;
    }
    final seen = <String>{};
    final result = <LaborTaskDecision>[];
    for (final line in lines) {
      final proposal = TaskLaborLinkPlanner.propose(line);
      if (proposal == null) continue;
      final key = '${line.jobId}:${line.lineId}';
      if (!seen.add(key)) continue;
      result.add(LaborTaskDecision(
        proposal: proposal,
        existingTaskId: byKey[key],
      ));
    }
    return result;
  }
}
