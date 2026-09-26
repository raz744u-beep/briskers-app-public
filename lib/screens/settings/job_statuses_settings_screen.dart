import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../core/job_status_style.dart';
import '../../services/briskers_api.dart';

class JobStatusesSettingsScreen extends StatefulWidget {
  const JobStatusesSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<JobStatusesSettingsScreen> createState() =>
      _JobStatusesSettingsScreenState();
}

class _JobStatusesSettingsScreenState
    extends State<JobStatusesSettingsScreen> {
  static const _api = BriskersApi();

  List<Map<String, dynamic>>? _statuses;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.jobStatuses(
        widget.businessId,
        includeInactive: true,
      );
      if (!mounted) return;
      setState(() {
        _statuses = rows;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statuses = const [];
        _error = error.toString();
      });
    }
  }

  Future<void> _edit([Map<String, dynamic>? status]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _JobStatusDialog(
        businessId: widget.businessId,
        status: status,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> status) async {
    final name = status['name']?.toString() ?? 'this status';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete job status?'),
        content: Text(
          'Delete "$name"? This is only allowed for custom statuses that are not used by any jobs.',
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
      await _api.deleteJobStatus(
        widget.businessId,
        status['id'].toString(),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Status could not be deleted'),
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
        backgroundColor: BriskersColors.jobs.withValues(alpha: 0.10),
        title: const Text('Job statuses'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: BriskersColors.jobs,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Status'),
      ),
      body: _statuses == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
                    child: Text(
                      'Status names, colors and icons are used everywhere jobs appear. Built-in statuses can be renamed or recolored, but not deleted.',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ..._statuses!.map((status) {
                    final active = status['active'] != false;
                    final color = colorFromHex(status['color_hex']?.toString());
                    final icon = jobStatusIcon(status['icon_key']?.toString());
                    final system = status['is_system'] == true;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: active
                              ? color.withValues(alpha: 0.14)
                              : Colors.grey.withValues(alpha: 0.14),
                          child: Icon(
                            active ? icon : Icons.visibility_off_outlined,
                            color: active ? color : Colors.grey,
                          ),
                        ),
                        title: Text(
                          status['name']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: active ? color : Colors.grey,
                          ),
                        ),
                        subtitle: Text(
                          <String>[
                            if (system) 'Built in',
                            if (!active) 'Inactive',
                          ].join(' • '),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') _edit(status);
                            if (value == 'delete') _delete(status);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Edit'),
                              ),
                            ),
                            if (!system)
                              const PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('Delete'),
                                ),
                              ),
                          ],
                        ),
                        onTap: () => _edit(status),
                      ),
                    );
                  }),
                  const SizedBox(height: 90),
                ],
              ),
            ),
    );
  }
}

class _JobStatusDialog extends StatefulWidget {
  const _JobStatusDialog({
    required this.businessId,
    this.status,
  });

  final String businessId;
  final Map<String, dynamic>? status;

  @override
  State<_JobStatusDialog> createState() => _JobStatusDialogState();
}

class _JobStatusDialogState extends State<_JobStatusDialog> {
  static const _api = BriskersApi();

  late final TextEditingController _name;
  late final TextEditingController _sortOrder;
  late String _colorHex;
  late String _iconKey;
  late bool _active;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.status?['name']?.toString() ?? '',
    );
    _sortOrder = TextEditingController(
      text: widget.status?['sort_order']?.toString() ?? '60',
    );
    _colorHex = widget.status?['color_hex']?.toString() ?? '#1976D2';
    _iconKey = widget.status?['icon_key']?.toString() ?? 'work_outline';
    _active = widget.status?['active'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Status name is required.');
      return;
    }

    final sortOrder = int.tryParse(_sortOrder.text.trim()) ?? 0;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _api.saveJobStatus(
        widget.businessId,
        statusId: widget.status?['id']?.toString(),
        name: name,
        colorHex: _colorHex,
        iconKey: _iconKey,
        active: _active,
        sortOrder: sortOrder,
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
    final color = colorFromHex(_colorHex);

    return AlertDialog(
      title: Text(widget.status == null ? 'Add job status' : 'Edit job status'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Status name'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _iconKey,
              decoration: const InputDecoration(labelText: 'Icon'),
              items: jobStatusIconChoices
                  .map(
                    (choice) => DropdownMenuItem<String>(
                      value: choice['key']! as String,
                      child: Row(
                        children: [
                          Icon(choice['icon']! as IconData, color: color),
                          const SizedBox(width: 10),
                          Text(choice['label']! as String),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _iconKey = value);
                    },
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Color',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: jobStatusColorChoices.map((hex) {
                final itemColor = colorFromHex(hex);
                final selected = hex.toUpperCase() == _colorHex.toUpperCase();
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _saving ? null : () => setState(() => _colorHex = hex),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: itemColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _sortOrder,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sort order',
                helperText: 'Lower numbers appear first.',
              ),
            ),
            if (widget.status != null)
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
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: color),
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
