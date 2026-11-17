/// Display only: never replace saved invoice labor or requested work.
String jobDisplayDescription(Map<String, dynamic> job) {
  bool meaningful(String text) =>
      text.isNotEmpty &&
      !RegExp(
        r'^(invoice|job)(\s*#?\s*[0-9-]+)?$',
        caseSensitive: false,
      ).hasMatch(text);
  for (final key in ['title', 'work_summary', 'requested_work']) {
    final text = job[key]?.toString().trim() ?? '';
    if (meaningful(text)) return text;
  }
  return '';
}
