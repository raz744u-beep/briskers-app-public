/// Copy trusted server lock flags into an otherwise current offline detail.
/// Never infer that an absent lock flag means an old imported invoice is editable.
/// Do not overwrite local pending edits or snapshots from a different version.
Map<String, dynamic>? withVerifiedDocumentEditMetadata(
  Map<String, dynamic> document,
  Map<String, dynamic>? cached,
) {
  if (cached == null ||
      document['id']?.toString() != cached['id']?.toString() ||
      document['kind']?.toString() != cached['kind']?.toString() ||
      cached['sync_state']?.toString() == 'pending') {
    return null;
  }
  final currentVersion = document['row_version']?.toString();
  if (currentVersion == null ||
      currentVersion != cached['row_version']?.toString()) {
    return null;
  }
  if (document['legacy_read_only'] is! bool ||
      document['legacy_editable'] is! bool ||
      !document.containsKey('origin') ||
      !document.containsKey('closed_at')) {
    return null;
  }
  // Metadata is safe to refresh without replacing historical line item details.
  const keys = [
    'legacy_read_only',
    'legacy_editable',
    'origin',
    'closed_at',
  ];
  if (keys.every((key) => cached[key] == document[key] &&
      cached.containsKey(key))) {
    return null;
  }
  return <String, dynamic>{
    ...cached,
    for (final key in keys) key: document[key],
  };
}
