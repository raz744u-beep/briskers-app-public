/// A compact, factual preview for an estimate list row.
/// Never fabricate text when neither the index nor the local detail has it.
String estimateListDescription(
  Map<String, dynamic> index, {
  Map<String, dynamic>? detail,
}) {
  final title = (index['title'] ?? index['job_title'] ?? '').toString().trim();
  final candidates = <Object?>[
    index['estimate_description'],
    index['description'],
    index['work_summary'],
    index['summary'],
    detail?['estimate_description'],
    detail?['description'],
    detail?['work_summary'],
  ];
  for (final raw in candidates) {
    final value = raw?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (value.isNotEmpty && value.toLowerCase() != title.toLowerCase()) {
      return value;
    }
  }
  // Existing estimate line names are a useful preview for old imported jobs
  // that have no separate description field in the document index.
  final rawLines = detail?['lines'];
  if (rawLines is! List) return '';
  final names = <String>[];
  for (final raw in rawLines) {
    if (raw is! Map || raw['line_kind']?.toString() == 'discount') continue;
    final name = (raw['name'] ?? '').toString()
        .replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
    if (names.length == 2) break;
  }
  return names.join(' • ');
}
