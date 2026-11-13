import '../services/invoice_labor_work_summary.dart';
/// A compact, factual preview for an estimate list row.
/// Never fabricate text when neither the index nor the local detail has it.
String estimateListDescription(
  Map<String, dynamic> index, {
  Map<String, dynamic>? detail,
}) {
  final labor=detail==null ? '' : invoiceLaborWorkSummary(detail).replaceAll(RegExp(r'\s+'),' ').trim();
  if(labor.isNotEmpty) return labor;
  final isInvoice=index['kind']=='invoice' || detail?['kind']=='invoice';
  final title=(index['title'] ?? index['job_title'] ?? '').toString().trim();
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
    if (value.isNotEmpty && (isInvoice || value!=title) && !RegExp(r'^(invoice|estimate)(\s*#?\s*[\w-]+)?$',caseSensitive:false).hasMatch(value)) {
      return value;
    }
  }
  // Existing estimate line names are a useful preview for old imported jobs
  // that have no separate description field in the document index.
  final rawLines = detail?['lines'];
  if (rawLines is! List) return '';
  final names = <String>[];
  final ordered=[...rawLines.whereType<Map>().where((r)=>r['line_kind']=='labor'), ...rawLines.whereType<Map>().where((r)=>r['line_kind']!='labor')];
  for (final raw in ordered) {
    if (raw['line_kind']?.toString() == 'discount') continue;
    final name = (raw['description'] ?? raw['name'] ?? '').toString()
        .replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
    if (names.length == 2) break;
  }
  return names.join(' • ');
}
