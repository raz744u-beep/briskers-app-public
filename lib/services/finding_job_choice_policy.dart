/// An unfinished finding can be worked on in an active Job, while a
/// completed Job is valid only as the historical repair that resolved it.
enum FindingJobChoice { active, completedHistory, unavailable }

FindingJobChoice findingJobChoice(
  Object? rawStatus, {
  required bool resolving,
}) {
  final status = rawStatus?.toString().trim().toLowerCase() ?? '';
  if (const {'cancelled', 'canceled', 'deleted', 'void', 'voided'}
      .contains(status)) {
    return FindingJobChoice.unavailable;
  }
  if (const {'completed', 'closed'}.contains(status)) {
    return resolving
        ? FindingJobChoice.completedHistory
        : FindingJobChoice.unavailable;
  }
  return FindingJobChoice.active;
}
