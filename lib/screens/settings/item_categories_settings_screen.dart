import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class ItemCategoriesSettingsScreen extends StatefulWidget {
  const ItemCategoriesSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<ItemCategoriesSettingsScreen> createState() =>
      _ItemCategoriesSettingsScreenState();
}

class _ItemCategoriesSettingsScreenState
    extends State<ItemCategoriesSettingsScreen> {
  static const _api = BriskersApi();

  List<Map<String, dynamic>>? _rows;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.itemCategories(
        widget.businessId,
        includeInactive: true,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final controller =
        TextEditingController(text: row?['name']?.toString() ?? '');
    var active = row?['active'] != false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(row == null ? 'Add item category' : 'Edit item category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Category name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged: (value) =>
                    setDialogState(() => active = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(dialogContext, {
                  'name': name,
                  'active': active,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (result == null) return;
    final rows = _rows ?? const <Map<String, dynamic>>[];
    final sortOrder = row == null
        ? (rows.isEmpty
            ? 10
            : rows
                    .map((item) =>
                        int.tryParse(item['sort_order']?.toString() ?? '') ?? 0)
                    .reduce((a, b) => a > b ? a : b) +
                10)
        : int.tryParse(row['sort_order']?.toString() ?? '') ?? 0;

    await _save(
      row,
      name: result['name'].toString(),
      active: result['active'] == true,
      sortOrder: sortOrder,
    );
  }

  Future<void> _save(
    Map<String, dynamic>? row, {
    required String name,
    required bool active,
    required int sortOrder,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.saveItemCategory(
        widget.businessId,
        categoryId: row?['id']?.toString(),
        name: name,
        active: active,
        sortOrder: sortOrder,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(int index, int delta) async {
    final rows = _rows;
    if (rows == null) return;
    final other = index + delta;
    if (other < 0 || other >= rows.length || _busy) return;

    final a = rows[index];
    final b = rows[other];
    final aSort = int.tryParse(a['sort_order']?.toString() ?? '') ?? index * 10;
    final bSort = int.tryParse(b['sort_order']?.toString() ?? '') ?? other * 10;

    setState(() => _busy = true);
    try {
      await _api.saveItemCategory(
        widget.businessId,
        categoryId: a['id'].toString(),
        name: a['name'].toString(),
        active: a['active'] == true,
        sortOrder: bSort,
      );
      await _api.saveItemCategory(
        widget.businessId,
        categoryId: b['id'].toString(),
        name: b['name'].toString(),
        active: b['active'] == true,
        sortOrder: aSort,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows ?? const <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Categories'),
        actions: [
          IconButton(
            tooltip: 'Add category',
            onPressed: _busy ? null : () => _edit(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 84),
                itemCount: rows.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final active = row['active'] == true;
                  return ListTile(
                    enabled: active,
                    leading: CircleAvatar(
                      backgroundColor:
                          BriskersColors.invoices.withValues(alpha: 0.12),
                      child: const Icon(
                        Icons.category_outlined,
                        color: BriskersColors.invoices,
                      ),
                    ),
                    title: Text(
                      row['name']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: active ? null : const Text('Inactive'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _edit(row);
                        if (value == 'up') _move(index, -1);
                        if (value == 'down') _move(index, 1);
                        if (value == 'toggle') {
                          _save(
                            row,
                            name: row['name'].toString(),
                            active: !active,
                            sortOrder: int.tryParse(
                                  row['sort_order']?.toString() ?? '',
                                ) ??
                                index * 10,
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        PopupMenuItem(
                          value: 'up',
                          enabled: index > 0,
                          child: const Text('Move up'),
                        ),
                        PopupMenuItem(
                          value: 'down',
                          enabled: index < rows.length - 1,
                          child: const Text('Move down'),
                        ),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(active ? 'Make inactive' : 'Reactivate'),
                        ),
                      ],
                    ),
                    onTap: _busy ? null : () => _edit(row),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add Category'),
      ),
      bottomSheet: _error == null
          ? null
          : Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(_error!),
              ),
            ),
    );
  }
}
