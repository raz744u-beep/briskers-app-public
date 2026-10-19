import 'task_labor_link_planner.dart';

/// Converts actual saved document-line maps into labor-task candidates.
/// Read-only: invoice prices, quantities and payment records are untouched.
class SavedDocumentLaborMapper {
  static List<LaborLineCandidate> candidates({
    required String jobId,
    required Iterable<Map<String, dynamic>> lines,
    Map<String, double> serviceHoursByCatalogItem = const {},
  }) {
    if (jobId.trim().isEmpty) return const [];
    final result = <LaborLineCandidate>[];
    for (final line in lines) {
      final id = line['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue; // no stable line identity yet
      final name = line['name']?.toString() ?? '';
      final kind = line['line_kind']?.toString() ?? 'item';
      final itemId = line['item_id']?.toString();
      final catalogHours = itemId == null ? null : serviceHoursByCatalogItem[itemId];
      final quantity = _number(line['quantity']);
      if (quantity == null || quantity < 0) continue;
      final candidate = LaborLineCandidate(
        lineId: id, jobId: jobId, name: name,
        description: line['description']?.toString(), lineKind: kind,
        quantity: quantity,
        containsLabor: catalogHours != null,
        defaultPayrollHours: catalogHours,
      );
      if (TaskLaborLinkPlanner.isLaborBearing(candidate)) result.add(candidate);
    }
    return result;
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble().isFinite ? value.toDouble() : null;
    final n = double.tryParse(value?.toString() ?? '');
    return n != null && n.isFinite ? n : null;
  }
}
