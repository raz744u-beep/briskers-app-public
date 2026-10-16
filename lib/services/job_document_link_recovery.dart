/// Only the legacy cache fallback uses this policy. Authoritative online sync
/// remains free to apply a verified reassignment to another Job.
bool canRecoverLegacyJobDocumentLink({
  required String requestedJobId,
  required Object? indexedJobId,
}) {
  if (requestedJobId.trim().isEmpty) return false;
  final indexed = indexedJobId?.toString().trim() ?? '';
  return indexed.isEmpty || indexed == requestedJobId;
}

/// A known newer index (including an explicit unlink) wins over cached detail.
/// Missing detail freshness is not evidence that it can replace a dated index.
bool isLegacyJobDocumentDetailCurrent({
  required Map<String, dynamic> index,
  required Map<String, dynamic> detail,
}) {
  final indexVersion = int.tryParse('${index['row_version'] ?? ''}');
  final detailVersion = int.tryParse('${detail['row_version'] ?? ''}');
  final indexedUnlink = index.containsKey('job_id') &&
      '${index['job_id'] ?? ''}'.trim().isEmpty;
  if (indexVersion != null &&
      (detailVersion == null || detailVersion < indexVersion ||
          (indexedUnlink && detailVersion == indexVersion))) {
    return false;
  }
  final indexTime = DateTime.tryParse('${index['updated_at'] ?? ''}');
  final detailTime = DateTime.tryParse('${detail['updated_at'] ?? ''}');
  if (indexTime != null &&
      (detailTime == null || detailTime.isBefore(indexTime) ||
          (indexedUnlink && detailTime.isAtSameMomentAs(indexTime) &&
              (indexVersion == null || detailVersion == null ||
                  detailVersion <= indexVersion)))) {
    return false;
  }
  return true;
}

/// Display-only legacy recovery. Never writes cached detail into the index.
/// Re-read after awaits so an arriving reassignment or unlink wins.
Future<List<Map<String, dynamic>>> recoverLegacyJobDocuments({
  required String requestedJobId,
  required List<Map<String, dynamic>> candidates,
  required Future<Map<String, dynamic>?> Function(String id) readDetail,
  required Future<List<Map<String, dynamic>>> Function() readCurrentIndex,
}) async {
  final recovered = <Map<String, dynamic>>[];
  for (final row in candidates) {
    if (!canRecoverLegacyJobDocumentLink(
      requestedJobId: requestedJobId, indexedJobId: row['job_id'],
    )) {
      continue;
    }
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    final detail = await readDetail(id);
    if (detail == null || detail['id'] != id || detail['job_id'] != requestedJobId ||
        !isLegacyJobDocumentDetailCurrent(index: row, detail: detail)) {
      continue;
    }
    recovered.add({...row, ...detail,
      'total_amount': detail['total_amount'] ?? row['total_amount'] ?? 0,
      '_local_snapshot': true,
    });
  }
  if (recovered.isEmpty) return recovered;
  final current = {for (final row in await readCurrentIndex()) row['id']: row};
  return recovered.where((detail) {
    final row = current[detail['id']];
    return row != null && canRecoverLegacyJobDocumentLink(
      requestedJobId: requestedJobId, indexedJobId: row['job_id'],
    ) && isLegacyJobDocumentDetailCurrent(index: row, detail: detail);
  }).toList();
}
