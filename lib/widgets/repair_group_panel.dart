import 'dart:async';
import 'package:flutter/material.dart';
import '../core/briskers_colors.dart';
import '../core/repair_group.dart';
import '../services/local_repair_groups.dart';
import '../screens/jobs/repair_authorization_screen.dart';
import '../screens/jobs/repair_authorization_history_screen.dart';
import 'briskers_dialog.dart';

/// Embedded in the current editor. Parts/labor still open its existing editor.
class RepairGroupPanel extends StatefulWidget {
  const RepairGroupPanel({super.key, required this.business, required this.estimate,
    required this.detail, required this.editable, required this.onEnabled,
    required this.onEditLine, required this.onAddItems, this.owner = false, this.store});
  final String business, estimate;
  final Map<String, dynamic> detail;
  final bool editable;
  final bool owner;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<Map<String, dynamic>> onEditLine;
  final Future<void> Function() onAddItems;
  final LocalRepairGroups? store;
  @override State<RepairGroupPanel> createState() => _RepairGroupPanelState();
}

class _RepairGroupPanelState extends State<RepairGroupPanel> {
  late final LocalRepairGroups store = widget.store ?? LocalRepairGroups();
  late Future<({bool enabled, List<RepairGroup> groups, Map<String, RepairDecision> states})> view;
  bool busy = false;
  @override void initState() { super.initState(); view = _load(); }
  @override void didUpdateWidget(covariant RepairGroupPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.detail, widget.detail)) view = _load();
  }
  Future<({bool enabled, List<RepairGroup> groups, Map<String, RepairDecision> states})> _load() async {
    final enabled = await store.enabled(widget.business, widget.estimate);
    final groups = enabled ? await store.groups(widget.business, widget.estimate, widget.detail) : <RepairGroup>[];
    final states = enabled ? await store.decisions(widget.business, widget.estimate, widget.detail) : <String, RepairDecision>{};
    if (mounted) widget.onEnabled(enabled);
    return (enabled: enabled, groups: groups, states: states);
  }
  Future<void> _run(Future<void> Function() action) async {
    if (busy) { return; }
    setState(() => busy = true);
    try { await action(); }
    catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() { busy = false; view = _load(); });
    }
  }
  Future<void> _edit([RepairGroup? group]) async {
    final name = TextEditingController(text: group?.name ?? '');
    final description = TextEditingController(text: group?.description ?? '');
    final available = await store.availableEvidence(widget.business, widget.detail);
    final evidence = [...?group?.evidence];
    if (!mounted) { return; }
    final saved = await showDialog<bool>(context: context, builder: (dialog) => BriskersDialog(
      title: group == null ? 'Add repair group' : 'Edit repair group',
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Repair group name')),
        TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
        if (available.isNotEmpty) StatefulBuilder(builder: (context, update) => Column(children: [
          const Text('Linked findings and photos'),
          for (final finding in available) CheckboxListTile(dense: true,
            title: Text('${finding['body']}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${(finding['photos'] as List).length} photos'),
            value: evidence.any((item) => item['id'] == finding['id']),
            onChanged: (selected) => update(() {
              evidence.removeWhere((item) => item['id'] == finding['id']);
              if (selected == true) evidence.add(finding);
            })),
        ])),
      ]), actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(style: BriskersDialog.confirmStyle(), onPressed: () => Navigator.pop(dialog, true), child: const Text('Save'))]));
    final title = name.text;
    final body = description.text;
    // Dialog removal animates; controllers stay valid until its route closes.
    if (saved == true) {
      if (group == null) {
        final id = await store.add(widget.business, widget.estimate, title);
        if (body.trim().isNotEmpty || evidence.isNotEmpty) await store.edit(widget.business, widget.estimate, id, name: title, description: body, evidence: evidence);
      } else {
        await store.edit(widget.business, widget.estimate, group.id, name: title, description: body, evidence: evidence);
      }
    }
  }
  Future<void> _move(Map<String, dynamic> line, List<RepairGroup> groups) async {
    final id = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Move item to repair group')),
        for (final group in groups) ListTile(title: Text(group.name), onTap: () => Navigator.pop(sheet, group.id)),
      ])));
    if (id != null) await store.move(widget.business, widget.estimate, line['id'] as String, id);
  }
  Future<void> _action(String action, RepairGroup group, List<RepairGroup> groups) async {
    if (action == 'edit') { return _edit(group); }
    if (action == 'remove') {
      final remove = await showDialog<bool>(context: context, builder: (dialog) => BriskersDialog(
        title: 'Remove repair group?', content: const Text('Its items move to Other Items. Authorization history is preserved.'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(style: BriskersDialog.confirmStyle(), onPressed: () => Navigator.pop(dialog, true), child: const Text('Remove'))]));
      if (remove == true) await store.remove(widget.business, widget.estimate, group.id);
      return;
    }
    final ids = groups.where((item) => !item.isOther).map((item) => item.id).toList();
    final from = ids.indexOf(group.id);
    final to = from + (action == 'up' ? -1 : 1);
    if (to < 0 || to >= ids.length) { return; }
    ids.removeAt(from); ids.insert(to, group.id);
    await store.reorder(widget.business, widget.estimate, ids);
  }
  String _status(RepairDecision? decision) => switch (decision) {
    RepairDecision.approved => 'Approved', RepairDecision.declined => 'Declined', _ => 'Awaiting Decision',
  };
  Future<void> _review() async {
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RepairAuthorizationScreen(
      business: widget.business, estimate: widget.estimate, detail: widget.detail, store: store)));
  }
  Future<void> _addItems(String group) async {
    final before = await store.cache.loadReadOnly(widget.business, widget.estimate);
    final ids = (before?['lines'] as List? ?? const []).whereType<Map>().map((line) => line['id']).toSet();
    await widget.onAddItems();
    final after = await store.cache.loadReadOnly(widget.business, widget.estimate);
    for (final raw in (after?['lines'] as List? ?? const []).whereType<Map>()) {
      final line = Map<String, dynamic>.from(raw);
      if (!ids.contains(line['id']) && !RepairGroup.isGeneralCharge(line)) {
        await store.move(widget.business, widget.estimate, line['id'] as String, group);
      }
    }
  }
  @override Widget build(BuildContext context) => FutureBuilder(
    future: view, builder: (context, snapshot) {
      if (snapshot.hasError) { return Padding(padding: const EdgeInsets.all(12), child: Text('Repair groups unavailable: ${snapshot.error}')); }
      final data = snapshot.data;
      if (data == null) { return const SizedBox.shrink(); }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (data.enabled) Align(alignment: Alignment.centerLeft, child: TextButton.icon(
          onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => RepairAuthorizationHistoryScreen(
            business: widget.business, estimate: widget.estimate, owner: widget.owner, store: store))),
          icon: const Icon(Icons.history_outlined), label: const Text('Authorization history'))),
        if (widget.editable) Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(spacing: 8, children: [
            TextButton.icon(style: TextButton.styleFrom(foregroundColor: BriskersColors.confirm),
              onPressed: busy ? null : () => _run(() => _edit()),
              icon: const Icon(Icons.create_new_folder_outlined), label: const Text('Add repair group')),
            if (data.enabled) TextButton.icon(style: TextButton.styleFrom(foregroundColor: BriskersColors.confirm),
              onPressed: busy ? null : () => _run(_review), icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Record authorization')),
          ])),
        for (final group in data.groups)
          if (!group.isOther || group.lines.isNotEmpty) Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(width: 3, color: switch (data.states[group.id]) {
                RepairDecision.approved => BriskersColors.confirm,
                RepairDecision.declined => BriskersColors.destructive, _ => BriskersColors.estimates}))),
            child: Material(color: Colors.white, borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(key: PageStorageKey('repair-group-${widget.estimate}-${group.id}'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text('${_status(data.states[group.id])} · ${group.lines.length} items'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_amount(group), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (widget.editable && !group.isOther) PopupMenuButton<String>(
                  onSelected: (action) => unawaited(_run(() => _action(action, group, data.groups))),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit group')),
                    PopupMenuItem(value: 'up', child: Text('Move up')), PopupMenuItem(value: 'down', child: Text('Move down')),
                    PopupMenuItem(value: 'remove', child: Text('Remove group'))]),
                const Icon(Icons.expand_more, size: 18),
              ]),
              children: [
                if (group.description.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(group.description)),
                for (final line in group.lines) ListTile(dense: true,
                  title: Text('${line['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('Qty ${line['quantity']}'),
                  onTap: widget.editable ? () => widget.onEditLine(line) : null,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('\$${(RepairGroup.lineCents(line) / 100).toStringAsFixed(2)}'),
                    if (widget.editable) IconButton(tooltip: 'Move item', icon: const Icon(Icons.drive_file_move_outline),
                      onPressed: busy ? null : () => _run(() => _move(line, data.groups))),
                  ])),
                if (widget.editable) TextButton.icon(onPressed: busy ? null : () => _run(() => _addItems(group.id)),
                  icon: const Icon(Icons.add, color: BriskersColors.confirm), label: const Text('Add parts or labor')),
              ]))),
      ]);
    });
  String _amount(RepairGroup group) {
    try { return '\$${(group.quotedCents / 100).toStringAsFixed(2)}'; }
    on StateError { return 'Review amounts'; }
  }
}
