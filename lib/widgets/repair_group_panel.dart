import 'package:flutter/material.dart';

import '../core/briskers_colors.dart';
import '../core/repair_group.dart';
import '../services/local_repair_groups.dart';
import 'briskers_dialog.dart';

/// Organizes the existing estimate rows without changing their pricing or actions.
class RepairGroupPanel extends StatefulWidget {
  const RepairGroupPanel({
    super.key,
    required this.business,
    required this.estimate,
    required this.lines,
    required this.editable,
    required this.buildLine,
    required this.store,
    this.lineRevision,
  });

  final String business, estimate;
  final List<Map<String, dynamic>> lines;
  final bool editable;
  final Widget Function(Map<String, dynamic>) buildLine;
  final LocalRepairGroups store;
  final Object? lineRevision;

  @override
  State<RepairGroupPanel> createState() => _RepairGroupPanelState();
}

class _RepairGroupPanelState extends State<RepairGroupPanel> {
  late Future<List<RepairGroup>> _groups = _load();
  bool _busy = false;

  Future<List<RepairGroup>> _load() => widget.store.groups(
    widget.business, widget.estimate, {'lines': widget.lines},
  );

  @override
  void didUpdateWidget(covariant RepairGroupPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.business != widget.business ||
        oldWidget.estimate != widget.estimate ||
        !identical(oldWidget.lineRevision ?? oldWidget.lines,
            widget.lineRevision ?? widget.lines)) {
      _groups = _load();
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !widget.editable) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save repair group. $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _groups = _load();
        });
      }
    }
  }

  Future<void> _edit([RepairGroup? group]) async {
    var name = group?.name ?? '';
    var description = group?.description ?? '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => BriskersDialog(
          title: group == null ? 'Add repair group' : 'Edit repair group',
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              initialValue: name,
              decoration: const InputDecoration(labelText: 'Repair group name'),
              onChanged: (value) => update(() => name = value),
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: description,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
              onChanged: (value) => description = value,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(
              style: BriskersDialog.confirmStyle(),
              onPressed: name.trim().isEmpty ? null : () => Navigator.pop(dialog, true),
              child: const Text('Save group'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted || !widget.editable) return;
    if (group == null) {
      await widget.store.add(widget.business, widget.estimate, name: name, description: description);
    } else {
      await widget.store.edit(
        widget.business, widget.estimate, group.id, name: name, description: description,
      );
    }
    _showMessage(group == null ? 'Repair group added.' : 'Repair group updated.');
  }

  Future<void> _moveItems(RepairGroup target, List<RepairGroup> groups) async {
    final items = [
      for (final group in groups)
        if (group.id != target.id)
          for (final line in group.lines)
            if (line['id'] case final String id)
              (id: id, name: line['name']?.toString() ?? 'Item', from: group.name),
    ];
    if (items.isEmpty) {
      _showMessage('There are no items outside ${target.name} to move here.');
      return;
    }

    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => BriskersDialog(
          title: 'Move items to ${target.name}',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                CheckboxListTile(
                  title: Text(item.name),
                  subtitle: Text(item.from),
                  value: selected.contains(item.id),
                  onChanged: (checked) => update(() {
                    if (checked == true) {
                      selected.add(item.id);
                    } else {
                      selected.remove(item.id);
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(
              style: BriskersDialog.confirmStyle(),
              onPressed: selected.isEmpty ? null : () => Navigator.pop(dialog, true),
              child: const Text('Move items'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted && widget.editable) {
      await widget.store.move(widget.business, widget.estimate, selected, target.id);
      _showMessage('Moved ${selected.length} ${selected.length == 1 ? 'item' : 'items'} to ${target.name}.');
    }
  }

  Future<void> _remove(RepairGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => BriskersDialog(
        title: 'Remove repair group?',
        content: const Text('Its items will move to Other Items.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(
            style: BriskersDialog.confirmStyle(destructive: true),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove group'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && widget.editable) {
      await widget.store.remove(widget.business, widget.estimate, group.id);
    }
  }

  Future<void> _action(String action, RepairGroup group, List<RepairGroup> groups) async {
    switch (action) {
      case 'items':
        await _moveItems(group, groups);
        return;
      case 'edit':
        await _edit(group);
        return;
      case 'remove':
        await _remove(group);
        return;
      case 'up':
      case 'down':
        final ids = groups.where((entry) => !entry.isOther).map((entry) => entry.id).toList();
        final from = ids.indexOf(group.id);
        final to = from + (action == 'up' ? -1 : 1);
        if (from < 0 || to < 0 || to >= ids.length) return;
        ids.removeAt(from);
        ids.insert(to, group.id);
        await widget.store.reorder(widget.business, widget.estimate, ids);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<RepairGroup>>(
    future: _groups,
    builder: (context, snapshot) {
      // Render the current estimate's lines while refreshing group membership.
      // In particular, a failed group read cannot hide the quote's items.
      final groups = snapshot.data;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (snapshot.hasError)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Repair groups could not be loaded. Refresh to try again.'),
          ),
        if (widget.editable && !snapshot.hasError)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy || snapshot.connectionState != ConnectionState.done
                  ? null : () => _run(() => _edit()),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Add repair group'),
            ),
          ),
        if (groups != null && snapshot.connectionState == ConnectionState.done &&
            groups.any((group) => !group.isOther))
          ..._sections(groups)
        else if (widget.lines.isEmpty)
          const Padding(
            padding: EdgeInsets.all(22),
            child: Center(child: Text('No items added yet.')),
          )
        else
          ...widget.lines.map(widget.buildLine),
      ]);
    },
  );

  Iterable<Widget> _sections(List<RepairGroup> groups) sync* {
    for (final group in groups) {
      if (group.isOther && group.lines.isEmpty && !widget.editable) continue;
      yield Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: BriskersColors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: PageStorageKey('repair-group-${widget.estimate}-${group.id}'),
            leading: const Icon(Icons.folder_outlined, color: BriskersColors.estimates),
            title: Text(group.name),
            subtitle: Text('${group.lines.length} items'),
            trailing: widget.editable
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    PopupMenuButton<String>(
                      tooltip: 'Repair group actions',
                      enabled: !_busy,
                      onSelected: (action) => _run(() => _action(action, group, groups)),
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'items', child: Text('Move items here')),
                        if (!group.isOther) ...const [
                          PopupMenuItem(value: 'edit', child: Text('Edit group')),
                          PopupMenuItem(value: 'up', child: Text('Move group up')),
                          PopupMenuItem(value: 'down', child: Text('Move group down')),
                          PopupMenuItem(value: 'remove', child: Text('Remove group')),
                        ],
                      ],
                    ),
                    const Icon(Icons.expand_more, size: 18),
                  ])
                : null,
            children: [
              if (group.description.isNotEmpty)
                Padding(padding: const EdgeInsets.all(12), child: Text(group.description)),
              ...group.lines.map(widget.buildLine),
              if (widget.editable)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : () => _run(() => _moveItems(group, groups)),
                      icon: const Icon(Icons.drive_file_move_outline),
                      label: const Text('Move items here'),
                    ),
                    if (!group.isOther)
                      TextButton.icon(
                        onPressed: _busy ? null : () => _run(() => _edit(group)),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit group'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    }
    yield* widget.lines.where(RepairGroup.isGeneralCharge).map(widget.buildLine);
  }
}
