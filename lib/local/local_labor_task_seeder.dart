import '../core/saved_document_labor_mapper.dart';
import '../core/task_labor_link_planner.dart';
import 'local_job_task_store.dart';

/// Opt-in, local-only bridge for previously saved labor rows. The caller
/// must pass the correct persistent job UUID and canonical source-line IDs.
/// It never updates invoices, payroll ledger, or SyncOutbox.
class LocalLaborTaskSeeder {
  const LocalLaborTaskSeeder(this.store);
  final LocalJobTaskStore store;

  Future<int> seed({
    required String businessId,
    required String jobId,
    required List<Map<String, dynamic>> savedLines,
    Map<String, double> serviceHoursByCatalogItem = const {},
  }) async {
    if (businessId.trim().isEmpty || jobId.trim().isEmpty) {
      throw ArgumentError('Shop and job IDs are required');
    }
    final existing = await store.listForJob(businessId, jobId);
    final linked = existing.map((task) => task['source_line_id']).whereType<String>().toSet();
    final candidates = SavedDocumentLaborMapper.candidates(
      jobId: jobId, lines: savedLines,
      serviceHoursByCatalogItem: serviceHoursByCatalogItem,
    );
    var created = 0;
    final seen = <String>{};
    for (final line in candidates) {
      if (!seen.add(line.lineId) || linked.contains(line.lineId)) continue;
      final proposal = TaskLaborLinkPlanner.propose(line);
      if (proposal == null) continue;
      // Local-only deterministic ID; always scoped by business and job.
      final key = Uri.encodeComponent(
        '$businessId|$jobId|${line.lineId}',
      );
      await store.createIfMissing(
        id: 'task-line-$key',
        businessId: businessId,
        jobId: jobId,
        description: proposal.description,
        sourceLineId: line.lineId,
        billedHours: line.quantity,
        payrollHours: proposal.payrollHours,
      );
      linked.add(line.lineId);
      created++;
    }
    return created;
  }
}
