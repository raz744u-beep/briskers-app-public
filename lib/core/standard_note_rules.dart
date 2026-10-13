/// Shared storage/display rules for reusable invoice notes.
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
    note['name']?.toString().trim().toLowerCase() == 'general';

int standardNoteSortOrder(Map<String, dynamic> note) =>
    int.tryParse(note['sort_order']?.toString() ?? '') ?? 100;

/// General is last regardless of server order, case, or an older cached order.
/// Equal ranks retain their input order, making offline refreshes predictable.
List<Map<String, dynamic>> orderStandardNotes(
    Iterable<Map<String, dynamic>> notes) {
  final indexed = notes.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final aGeneral = isGeneralStandardNote(a.value);
    final bGeneral = isGeneralStandardNote(b.value);
    if (aGeneral != bGeneral) return aGeneral ? 1 : -1;
    final rank = standardNoteSortOrder(a.value)
        .compareTo(standardNoteSortOrder(b.value));
    return rank == 0 ? a.key.compareTo(b.key) : rank;
  });
  return indexed.map((entry) => Map<String, dynamic>.from(entry.value)).toList();
}
