/// Shared note-editing decisions used by the invoice screen and regression
/// tests. The invoice's saved memo is distinct from the unsaved text field.
enum InvoiceNoteDraftAction { none, save, clear }

InvoiceNoteDraftAction invoiceNoteDraftAction(
  String draft,
  String? saved,
) {
  final current = draft.trim();
  final persisted = (saved ?? '').trim();
  if (current == persisted) return InvoiceNoteDraftAction.none;
  if (current.isEmpty) {
    return persisted.isEmpty
        ? InvoiceNoteDraftAction.none
        : InvoiceNoteDraftAction.clear;
  }
  return InvoiceNoteDraftAction.save;
}

/// Append a standard note to the user's *current editor text* rather than
/// the older server memo. Never lose an unsaved manual note.
String mergeStandardNoteIntoDraft(
  String draft,
  String standardBody,
) {
  final current = draft.trim();
  final addition = standardBody.trim();
  if (addition.isEmpty) return current;
  if (current.isEmpty) return addition;
  final sections = current
      .split(RegExp(r'\\n\\s*\\n'))
      .map((section) => section.trim());
  if (sections.contains(addition)) return current;
  return '$current\\n\\n$addition';
}

bool canSaveStandardNoteText(String name, String body) =>
    name.trim().isNotEmpty && body.trim().isNotEmpty;
