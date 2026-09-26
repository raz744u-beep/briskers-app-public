import 'package:flutter/material.dart';

import '../../core/employee_role_style.dart';
import '../../services/briskers_api.dart';

class EmployeePositionsScreen extends StatefulWidget {
  const EmployeePositionsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<EmployeePositionsScreen> createState() =>
      _EmployeePositionsScreenState();
}

class _EmployeePositionsScreenState
    extends State<EmployeePositionsScreen> {
  static const _api = BriskersApi();

  List<Map<String, dynamic>>? _positions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.employeePositions(
        widget.businessId,
        includeInactive: true,
      );
      if (!mounted) return;
      setState(() {
        _positions = rows;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _edit([Map<String, dynamic>? position]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PositionEditDialog(
        businessId: widget.businessId,
        position: position,
      ),
    );

    if (saved == true) await _load();
  }

  Future<void> _deletePosition(Map<String, dynamic> position) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete position?'),
        content: Text(
          'Delete "${position['name']}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _api.deleteEmployeePosition(
        widget.businessId,
        position['id'].toString(),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Position could not be deleted'),
          content: Text(error.toString()),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Positions'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Position'),
      ),
      body: _positions == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
                    child: Text(
                      'These positions populate the employee position dropdown.',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ..._positions!.map((position) {
                    final name = position['name']?.toString() ?? '';
                    final active = position['active'] != false;
                    final roleStyle = employeeRoleStyle(name);

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: active
                              ? roleStyle.color.withValues(alpha: 0.14)
                              : Colors.grey.withValues(alpha: 0.14),
                          child: Icon(
                            active
                                ? roleStyle.icon
                                : Icons.person_off_outlined,
                            color: active ? roleStyle.color : Colors.grey,
                          ),
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            color: active ? roleStyle.color : Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          position['active'] == false ? 'Inactive' : 'Active',
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Position options',
                          onSelected: (value) {
                            if (value == 'edit') _edit(position);
                            if (value == 'delete') _deletePosition(position);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Edit'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.delete_outline),
                                title: Text('Delete'),
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _edit(position),
                      ),
                    );
                  }),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}

class _PositionEditDialog extends StatefulWidget {
  const _PositionEditDialog({
    required this.businessId,
    this.position,
  });

  final String businessId;
  final Map<String, dynamic>? position;

  @override
  State<_PositionEditDialog> createState() => _PositionEditDialogState();
}

class _PositionEditDialogState extends State<_PositionEditDialog> {
  static const _api = BriskersApi();

  late final TextEditingController _name;
  late bool _active;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.position != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.position?['name']?.toString() ?? '',
    );
    _active = widget.position?['active'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Position name is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _api.saveEmployeePosition(
        widget.businessId,
        positionId: widget.position?['id']?.toString(),
        name: name,
        active: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit position' : 'Add position'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Position name',
            ),
            onSubmitted: (_) {
              if (!_saving) _save();
            },
          ),
          if (_editing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _active,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _active = value),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
