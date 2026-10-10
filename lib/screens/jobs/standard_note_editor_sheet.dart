import 'package:flutter/material.dart';

import '../../core/briskers_i18n.dart';
import 'invoice_note_draft_rules.dart';

/// Keyboard-aware template editor matching the invoice item sheet.
/// Returns the edited name/body; the caller chooses whether to also add
/// the saved template text to this invoice.
class StandardNoteEditorSheet extends StatefulWidget {
  const StandardNoteEditorSheet({
    super.key,
    required this.accent,
    this.initialBody = '',
    this.addToInvoice = false,
  });

  final Color accent;
  final String initialBody;
  final bool addToInvoice;

  @override
  State<StandardNoteEditorSheet> createState() =>
      _StandardNoteEditorSheetState();
}

class _StandardNoteEditorSheetState extends State<StandardNoteEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _body;

  bool get _valid => canSaveStandardNoteText(_name.text, _body.text);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _body = TextEditingController(text: widget.initialBody);
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  void _save() {
    if (!_valid) return;
    Navigator.pop(context, <String, String>{
      'name': _name.text.trim(),
      'body': _body.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final accent = widget.accent;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: keyboardOpen ? 0.94 : 0.76,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 12, 10),
                child: Row(
                  children: [
                    Icon(Icons.bookmark_add_outlined, color: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.addToInvoice
                            ? tr('standardNoteCreateAndAdd')
                            : tr('standardNoteSaveAs'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('cancel'),
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('standard-note-name'),
                        controller: _name,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        scrollPadding: const EdgeInsets.only(bottom: 170),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: tr('standardNoteName'),
                          border: const OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: accent, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const ValueKey('standard-note-body'),
                        controller: _body,
                        minLines: 4,
                        maxLines: 10,
                        textCapitalization: TextCapitalization.sentences,
                        scrollPadding: const EdgeInsets.only(bottom: 170),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: tr('standardNoteBody'),
                          alignLabelWithHint: true,
                          border: const OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: accent, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(tr('cancel')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        key: const ValueKey('standard-note-submit'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _valid ? _save : null,
                        icon: const Icon(Icons.check),
                        label: Text(widget.addToInvoice
                            ? tr('standardNoteCreateAndAddButton')
                            : tr('standardNoteSaveTemplate')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
