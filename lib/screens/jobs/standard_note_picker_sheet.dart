import 'package:flutter/material.dart';

import '../../core/briskers_i18n.dart';
import '../../core/standard_note_rules.dart';

/// Template selection and owner-only management. General has no drag handle
/// and is the list footer, so even a drop below it cannot move it upward.
class StandardNotePickerSheet extends StatefulWidget {
  const StandardNotePickerSheet({
    super.key,
    required this.templates,
    required this.canManage,
    required this.onEdit,
    required this.onReorder,
  });

  final List<Map<String, dynamic>> templates;
  final bool canManage;
  final Future<List<Map<String, dynamic>>> Function(Map<String, dynamic>) onEdit;
  final Future<List<Map<String, dynamic>>> Function(List<String>) onReorder;

  @override
  State<StandardNotePickerSheet> createState() => _StandardNotePickerSheetState();
}

class _StandardNotePickerSheetState extends State<StandardNotePickerSheet> {
  late List<Map<String, dynamic>> _templates;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _templates = orderStandardNotes(widget.templates);
  }

  Future<void> _edit(Map<String, dynamic> note) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final templates = await widget.onEdit(note);
      if (mounted) setState(() => _templates = orderStandardNotes(templates));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_saving || !widget.canManage) return;
    final before = _templates;
    final movable = _templates.where((note) => !isGeneralStandardNote(note)).toList();
    // onReorderItem already accounts for removing the old item.
    // Decrementing a downward destination again would cancel a one-row move.
    final moved = movable.removeAt(oldIndex);
    movable.insert(newIndex.clamp(0, movable.length).toInt(), moved);
    final reordered = [...movable, ..._templates.where(isGeneralStandardNote)];
    setState(() {
      _templates = reordered;
      _saving = true;
    });
    try {
      final saved = await widget.onReorder(
        reordered.map((note) => note['id'].toString()).toList());
      if (mounted) setState(() => _templates = orderStandardNotes(saved));
    } catch (error) {
      if (mounted) {
        setState(() => _templates = before);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tile(Map<String, dynamic> template, {int? dragIndex}) {
    final hex = standardNoteColorHex(template['color_hex']);
    final color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
    final pinned = isGeneralStandardNote(template);
    return Card(
      key: ValueKey('standard-note-${template['id']}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: color.withValues(alpha: 0.09),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: ListTile(
        enabled: !_saving,
        leading: Icon(Icons.notes_outlined, color: color),
        title: Text(template['name']?.toString() ?? ''),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(template['body']?.toString() ?? '', maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (pinned) Text(tr('standardNotePinned'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (template['pending_sync'] == true)
              Text(tr(template['sync_error'] == null
                  ? 'standardNotePending' : 'standardNoteSyncProblem'),
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: widget.canManage ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: ValueKey('edit-standard-note-${template['id']}'),
              tooltip: tr('standardNoteEdit'),
              onPressed: _saving ? null : () => _edit(template),
              icon: const Icon(Icons.edit_outlined),
            ),
            if (dragIndex != null)
              ReorderableDragStartListener(
                key: ValueKey('reorder-standard-note-${template['id']}'),
                index: dragIndex,
                enabled: !_saving,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Tooltip(message: tr('standardNoteReorder'),
                      child: const Icon(Icons.drag_handle)),
                ),
              )
            else
              Tooltip(message: tr('standardNotePinned'),
                child: const Padding(padding: EdgeInsets.all(12),
                  child: Icon(Icons.push_pin_outlined, size: 20))),
          ],
        ) : null,
        onTap: _saving ? null : () => Navigator.pop(context, template),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movable = _templates.where((note) => !isGeneralStandardNote(note)).toList();
    final pinned = _templates.where(isGeneralStandardNote).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.76,
        child: Column(children: [
          ListTile(
            title: Text(tr('standardNotes'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            subtitle: Text(tr(widget.canManage
                ? 'standardNoteReorderHelp' : 'standardNoteChooseOrCreate')),
            trailing: IconButton(tooltip: tr('cancel'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close)),
          ),
          if (widget.canManage) ListTile(
            key: const ValueKey('add-standard-note-template'),
            enabled: !_saving,
            leading: const Icon(Icons.add_circle_outline),
            title: Text(tr('standardNoteCreate')),
            onTap: _saving ? null : () => Navigator.pop(context,
                <String, dynamic>{'_create_template': true}),
          ),
          if (_saving) const LinearProgressIndicator(minHeight: 2)
          else const Divider(height: 2),
          Expanded(child: _templates.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(16),
                  child: Text(tr('standardNoteEmptyList'))))
              : ReorderableListView.builder(
                  key: const ValueKey('standard-note-list'),
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: movable.length,
                  itemBuilder: (_, index) => _tile(movable[index], dragIndex: index),
                  onReorderItem: _reorder,
                  footer: Column(children: pinned.map((note) => _tile(note)).toList()),
                )),
        ]),
      ),
    );
  }
}
