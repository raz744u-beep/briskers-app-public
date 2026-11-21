/// Reconcile a server Customer Notes snapshot without discarding local
/// drafts, edits or photos still queued for upload.
///
/// Server identity is authoritative for clean synced records. A locally pending
/// row with the same ID takes priority until its outbox is acknowledged.
List<Map<String, dynamic>> mergeCustomerNotesPreservingPending(
  List<Map<String, dynamic>> remote,
  List<Map<String, dynamic>> cached,
) {
  bool pending(Map<String, dynamic> row) {
    final state = row['sync_state']?.toString();
    if (state == 'pending' || state == 'conflict' || state == 'failed') {
      return true;
    }
    final attachments = row['attachments'];
    if (attachments is List) {
      for (final attachment in attachments.whereType<Map>()) {
        final upload = attachment['upload_state']?.toString();
        if (upload == 'pending' || upload == 'uploading' ||
            upload == 'failed' || upload == 'conflict') {
          return true;
        }
      }
    }
    return false;
  }

  final ordered = <String, Map<String, dynamic>>{};
  for (final row in remote) {
    final id = row['id']?.toString() ?? '';
    if (id.isNotEmpty) ordered[id] = Map<String, dynamic>.from(row);
  }

  final localOnly = <Map<String, dynamic>>[];
  for (final row in cached) {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty || !pending(row)) continue;
    final local = Map<String, dynamic>.from(row);
    if (ordered.containsKey(id)) {
      // Keep newly linked server attachments while preserving any unsynced
      // local photos and the locally edited note body.
      final server = ordered[id]!;
      final photos = <String, Map<String, dynamic>>{};
      void addPhotos(Object? source) {
        if (source is! List) return;
        for (final value in source.whereType<Map>()) {
          final item = Map<String, dynamic>.from(value);
          final key = (item['attachment_id'] ?? item['id'] ??
              item['key'])?.toString() ?? '';
          if (key.isNotEmpty) photos[key] = item;
        }
      }
      addPhotos(server['attachments']);
      addPhotos(local['attachments']);
      ordered[id] = {
        ...server,
        ...local,
        'attachments': photos.values.toList(),
      };
    } else {
      localOnly.add(local);
    }
  }
  return [...localOnly, ...ordered.values];
}
