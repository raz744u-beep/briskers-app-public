/// Projects server/display rows together with the current local repository.
/// Local provisional IDs are valid only while the repository still owns them.
List<Map<String, dynamic>> mergeWorkFindings(
  List<Map<String, dynamic>> server,
  List<Map<String, dynamic>> local,
) {
  final localById = _byId(local);
  final serverById = _byId(server)
    ..removeWhere((id, _) =>
        id.startsWith('local-finding-') && !localById.containsKey(id));
  final result = <Map<String, dynamic>>[];

  for (final entry in localById.entries) {
    final localFinding = entry.value;
    final serverFinding = serverById.remove(entry.key);
    if (serverFinding == null) {
      result.add(Map<String, dynamic>.from(localFinding));
      continue;
    }

    final localVersion = _version(localFinding);
    final serverVersion = _version(serverFinding);
    final serverNewer = serverVersion > localVersion;
    final preferred = serverNewer ? serverFinding : localFinding;
    final other = serverNewer ? localFinding : serverFinding;
    final merged = <String, dynamic>{...other, ...preferred};
    final dirty = localFinding['sync_state'] == 'pending' ||
        localFinding['sync_state'] == 'conflict';
    if (dirty) {
      // A newer server row may carry repair status, but cannot acknowledge or
      // replace an unsent edit. The repository/outbox keeps its concurrency
      // base; the display keeps the newer version for repeated refreshes.
      merged['body'] = localFinding['body'];
      merged['sync_state'] = localFinding['sync_state'];
    }
    merged['attachments'] = _mergePhotos(
      preferred['attachments'],
      localFinding['attachments'],
    );
    result.add(merged);
  }

  result.addAll(serverById.values.map(Map<String, dynamic>.from));
  return result;
}

Map<String, Map<String, dynamic>> _byId(
  List<Map<String, dynamic>> rows,
) => {
  for (final row in rows)
    if ((row['id']?.toString() ?? '').isNotEmpty) row['id'].toString(): row,
};

int _version(Map<String, dynamic> row) =>
    int.tryParse(row['row_version']?.toString() ?? '') ?? -1;

List<Map<String, dynamic>> _mergePhotos(dynamic preferred, dynamic local) {
  List<Map<String, dynamic>> photos(dynamic raw) => raw is List
      ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];
  String id(Map<String, dynamic> photo) =>
      (photo['attachment_id'] ?? photo['id'])?.toString() ?? '';

  final localPhotos = {for (final photo in photos(local)) id(photo): photo};
  final merged = <String, Map<String, dynamic>>{};
  for (final photo in photos(preferred)) {
    final photoId = id(photo);
    if (photoId.isEmpty ||
        (photoId.startsWith('local-finding-photo-') &&
            !localPhotos.containsKey(photoId))) {
      continue;
    }
    merged[photoId] = {
      ...photo,
      if (localPhotos[photoId]?['local_file_path'] != null)
        'local_file_path': localPhotos[photoId]!['local_file_path'],
    };
  }
  for (final photo in localPhotos.values) {
    if (id(photo).isNotEmpty &&
        ((photo['upload_state']?.toString() ?? 'synced') != 'synced' ||
            (!merged.containsKey(id(photo)) &&
                (photo['local_file_path']?.toString() ?? '').isNotEmpty))) {
      // A completed upload can remap its photo ID while the display still
      // carries a newer repair version than the dirty finding's local base.
      merged[id(photo)] = Map<String, dynamic>.from(photo);
    }
  }
  return merged.values.toList();
}
