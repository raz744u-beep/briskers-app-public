/// Shared storage/display rules for reusable invoice notes.
const standardNoteCategoryKeys = <String>[
  'service',
  'warranty',
  'inspection',
  'advisory',
  'general',
];
const standardNoteCategoryLabelKeys = <String, String>{
  'service': 'standardNoteCategoryService',
  'warranty': 'standardNoteCategoryWarranty',
  'inspection': 'standardNoteCategoryInspection',
  'advisory': 'standardNoteCategoryAdvisory',
  'general': 'standardNoteCategoryGeneral',
};

/// Empty categories also retain their chosen position. General is a footer.
List<String> orderStandardNoteCategories(Iterable<String> requested) {
  final movable = <String>{
    ...requested.where(
      (key) => standardNoteCategoryKeys.contains(key) && key != 'general',
    ),
    ...standardNoteCategoryKeys.where((key) => key != 'general'),
  };
  return [...movable, 'general'];
}

bool isProtectedGeneralNoteName(String name) => const {
  'general',
  'general note',
  'general notes',
  'thank you',
  'nota general',
  'gracias',
}.contains(name.trim().toLowerCase());

const standardNoteCategoryColors = <String, String>{
  'service': '#1565C0',
  'warranty': '#2E7D32',
  'inspection': '#EF6C00',
  'advisory': '#C62828',
  'general': '#6A1B9A',
};

String standardNoteCategory(Map<String, dynamic> note) {
  final name = note['name']?.toString().trim().toLowerCase() ?? '';
  if (isProtectedGeneralNoteName(name)) return 'general';
  final key = note['category_key']?.toString().trim().toLowerCase();
  if (key != null && standardNoteCategoryKeys.contains(key)) return key;
  // Older offline caches did not have category metadata.
  if (name.contains('thank')) return 'general';
  if (name.contains('warranty')) return 'warranty';
  if (name.contains('inspect')) return 'inspection';
  if (name.contains('advis') || name.contains('warning')) return 'advisory';
  return 'service';
}

const standardNoteDefaultColor = '#1565C0';
const standardNotePalette = <String, String>{
  '#1565C0': 'standardNoteBlue',
  '#00796B': 'standardNoteTeal',
  '#2E7D32': 'standardNoteGreen',
  '#EF6C00': 'standardNoteOrange',
  '#C62828': 'standardNoteRed',
  '#6A1B9A': 'standardNotePurple',
  '#455A64': 'standardNoteSlate',
};

String standardNoteColorHex(Object? value) {
  final hex = value?.toString().trim().toUpperCase() ?? '';
  return RegExp(r'^#[0-9A-F]{6}$').hasMatch(hex)
      ? hex
      : standardNoteDefaultColor;
}

bool isGeneralStandardNote(Map<String, dynamic> note) =>
    standardNoteCategory(note) == 'general';

int standardNoteSortOrder(Map<String, dynamic> note) =>
    int.tryParse(note['sort_order']?.toString() ?? '') ?? 100;

/// General is last regardless of server order, case, or an older cached order.
/// Equal ranks retain their input order, making offline refreshes predictable.
List<Map<String, dynamic>> orderStandardNotes(
  Iterable<Map<String, dynamic>> notes,
) {
  final indexed = notes.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final aGeneral = isGeneralStandardNote(a.value);
    final bGeneral = isGeneralStandardNote(b.value);
    if (aGeneral != bGeneral) return aGeneral ? 1 : -1;
    final rank = standardNoteSortOrder(a.value)
        .compareTo(standardNoteSortOrder(b.value));
    return rank == 0 ? a.key.compareTo(b.key) : rank;
  });
  return indexed
      .map((entry) => Map<String, dynamic>.from(entry.value))
      .toList();
}
