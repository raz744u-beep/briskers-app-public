import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../core/invoice_status_style.dart';
import '../../services/briskers_api.dart';
import '../../services/local_invoice_status_styles_cache.dart';

class InvoiceStatusesSettingsScreen extends StatefulWidget {
  const InvoiceStatusesSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<InvoiceStatusesSettingsScreen> createState() =>
      _InvoiceStatusesSettingsScreenState();
}

class _InvoiceStatusesSettingsScreenState
    extends State<InvoiceStatusesSettingsScreen> {
  static const _api = BriskersApi();
  final LocalInvoiceStatusStylesCache _localStyles =
      LocalInvoiceStatusStylesCache();

  List<Map<String, dynamic>>? _statuses;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.invoiceStatusStyles(widget.businessId);
      await _localStyles.save(widget.businessId, rows);
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

  Future<void> _edit(Map<String, dynamic> status) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _InvoiceStatusDialog(
        businessId: widget.businessId,
        status: status,
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.invoices.withValues(alpha: 0.10),
        title: const Text('Invoice statuses'),
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
                      'Rename, recolor, change the icon, and reorder the invoice statuses used throughout Briskers. The underlying payment state remains automatic.',
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
                    final color = invoiceStatusColorFromHex(
                      status['color_hex']?.toString(),
                    );
                    final icon =
                        invoiceStatusIcon(status['icon_key']?.toString());
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.14),
                          child: Icon(icon, color: color),
                        ),
                        title: Text(
                          status['name']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        subtitle: Text(
                          'Built in • ${status['code']?.toString() ?? ''}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _edit(status),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _InvoiceStatusDialog extends StatefulWidget {
  const _InvoiceStatusDialog({
    required this.businessId,
    required this.status,
  });

  final String businessId;
  final Map<String, dynamic> status;

  @override
  State<_InvoiceStatusDialog> createState() => _InvoiceStatusDialogState();
}

class _InvoiceStatusDialogState extends State<_InvoiceStatusDialog> {
  static const _api = BriskersApi();

  late final TextEditingController _name;
  late final TextEditingController _sortOrder;
  late String _colorHex;
  late String _iconKey;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.status['name']?.toString() ?? '',
    );
    _sortOrder = TextEditingController(
      text: widget.status['sort_order']?.toString() ?? '0',
    );
    _colorHex = widget.status['color_hex']?.toString() ?? '#2E7D32';
    _iconKey = widget.status['icon_key']?.toString() ?? 'receipt';
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

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _api.saveInvoiceStatusStyle(
        widget.businessId,
        code: widget.status['code'].toString(),
        name: name,
        colorHex: _colorHex,
        iconKey: _iconKey,
        sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
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
    final color = invoiceStatusColorFromHex(_colorHex);

    return AlertDialog(
      title: const Text('Edit invoice status'),
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
              items: invoiceStatusIconChoices
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
              children: invoiceStatusColorChoices.map((hex) {
                final itemColor = invoiceStatusColorFromHex(hex);
                final selected =
                    hex.toUpperCase() == _colorHex.toUpperCase();
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _saving
                      ? null
                      : () => setState(() => _colorHex = hex),
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
                        ? const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 20,
                          )
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
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
