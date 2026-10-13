import 'package:flutter/material.dart';

import '../../core/briskers_i18n.dart';
import '../../core/standard_note_rules.dart';

/// Category-based note picker. The entire General category is always the
/// footer. Other categories and their notes may be reordered independently.
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
  late List<String> _categories;
  bool _saving = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _templates = orderStandardNotes(widget.templates);
    _categories = _categoryOrder(_templates);
  }

  List<String> _categoryOrder(List<Map<String, dynamic>> notes) {
    final defaultOrder = standardNoteCategoryKeys
        .where((key) => key != 'general').toList();
    // Sort order is shared across devices. A custom reorder produces distinct
    // ranks, so we can restore the previously chosen category ordering.
    final hasCustomOrder = notes.any(
      (note) => standardNoteSortOrder(note) != 100);
    if (!hasCustomOrder) return defaultOrder;
    final seen = <String>{};
    final ordered = <String>[];
    for (final note in orderStandardNotes(notes)) {
      final category = standardNoteCategory(note);
      if (category != 'general' && seen.add(category)) {
        ordered.add(category);
      }
    }
    return [...ordered, ...defaultOrder.where((key) => !seen.contains(key))];
  }

  List<Map<String, dynamic>> _inCategory(String category) {
    final search = _search.trim().toLowerCase();
    return _templates.where((note) {
      if (standardNoteCategory(note) != category) return false;
      if (search.isEmpty) return true;
      return ('${note['name'] ?? ''} ${note['body'] ?? ''}')
          .toLowerCase().contains(search);
    }).toList();
  }

  Future<void> _edit(Map<String, dynamic> note) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final templates = await widget.onEdit(note);
      if (mounted) {
        setState(() {
          _templates = orderStandardNotes(templates);
          _categories = _categoryOrder(_templates);
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyOrder(
    List<String> categoryOrder,
    Map<String, List<Map<String, dynamic>>> groups,
  ) async {
    if (_saving || !widget.canManage || _search.isNotEmpty) return;
    final previousNotes = _templates;
    final previousCategories = _categories;
    final ordered = [
      for (final category in categoryOrder) ...groups[category] ?? const <Map<String, dynamic>>[],
      ...groups['general'] ?? const <Map<String, dynamic>>[],
    ];
    setState(() {
      _templates = ordered;
      _categories = categoryOrder;
      _saving = true;
    });
    try {
      final saved = await widget.onReorder(
        ordered.map((note) => note['id'].toString()).toList());
      if (mounted) setState(() => _templates = orderStandardNotes(saved));
    } catch (error) {
      if (mounted) {
        setState(() {
          _templates = previousNotes;
          _categories = previousCategories;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reorderNotes(String category, int from, int to) async {
    if (_saving || _search.isNotEmpty || !widget.canManage) return;
    final groups = {
      for (final key in standardNoteCategoryKeys)
        key: _inCategory(key),
    };
    final notes = groups[category]!;
    final moved = notes.removeAt(from);
    notes.insert(to.clamp(0, notes.length).toInt(), moved);
    await _applyOrder(_categories, groups);
  }

  Future<void> _reorderCategories(int from, int to) async {
    if (_saving || _search.isNotEmpty || !widget.canManage) return;
    final order = [..._categories];
    final moved = order.removeAt(from);
    order.insert(to.clamp(0, order.length).toInt(), moved);
    await _applyOrder(order, {
      for (final key in standardNoteCategoryKeys)
        key: _inCategory(key),
    });
  }

  Widget _tile(Map<String, dynamic> template, {int? dragIndex}) {
    final hex = standardNoteColorHex(template['color_hex']);
    final color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
    final pinned = template['name']?.toString().trim().toLowerCase() == 'general';
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
            if (dragIndex != null && !pinned)
              ReorderableDragStartListener(
                key: ValueKey('reorder-standard-note-${template['id']}'),
                index: dragIndex,
                enabled: !_saving && _search.isEmpty,
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

  IconData _icon(String category) => switch (category) {
    'warranty' => Icons.verified_user_outlined,
    'inspection' => Icons.fact_check_outlined,
    'advisory' => Icons.warning_amber_outlined,
    'general' => Icons.description_outlined,
    _ => Icons.build_outlined,
  };

  Widget _group(String category, {int? index}) {
    final notes = _inCategory(category);
    final hex = standardNoteCategoryColors[category] ?? standardNoteDefaultColor;
    final color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
    final general = category == 'general';
    return Container(
      key: ValueKey('standard-note-group-$category'),
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        ListTile(
          leading: Icon(_icon(category), color: color),
          title: Text(standardNoteCategoryNames[category]!,
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          subtitle: Text('${notes.length} saved'),
          trailing: widget.canManage && !general && index != null
              ? ReorderableDragStartListener(
                  index: index,
                  enabled: !_saving && _search.isEmpty,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.drag_handle),
                  ),
                )
              : general ? const Icon(Icons.push_pin_outlined) : null,
        ),
        if (notes.isNotEmpty)
          ReorderableListView.builder(
            key: ValueKey(category == 'service'
                ? 'standard-note-list' : 'standard-note-list-$category'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: notes.length,
            itemBuilder: (_, noteIndex) => _tile(notes[noteIndex],
                dragIndex: widget.canManage ? noteIndex : null),
            onReorderItem: (from, to) => _reorderNotes(category, from, to),
          )
        else
          const Padding(
            padding: EdgeInsets.only(left: 16, right: 16, bottom: 10),
            child: Text('No notes yet. Create one and choose this category.'),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search notes',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (text) => setState(() => _search = text),
            ),
          ),
          if (widget.canManage) ListTile(
            key: const ValueKey('add-standard-note-template'),
            enabled: !_saving,
            leading: const Icon(Icons.add_circle_outline, color: Colors.green),
            title: Text(tr('standardNoteCreate')),
            onTap: _saving ? null : () => Navigator.pop(context,
                <String, dynamic>{'_create_template': true}),
          ),
          if (_saving) const LinearProgressIndicator(minHeight: 2)
          else const Divider(height: 2),
          Expanded(
            child: SingleChildScrollView(
              child: ReorderableListView.builder(
                key: const ValueKey('standard-note-categories'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _categories.length,
                itemBuilder: (_, index) => _group(_categories[index], index: index),
                onReorderItem: _reorderCategories,
                footer: _group('general'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
