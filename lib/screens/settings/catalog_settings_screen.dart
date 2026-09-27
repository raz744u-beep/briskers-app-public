import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class CatalogSettingsScreen extends StatefulWidget {
  const CatalogSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<CatalogSettingsScreen> createState() => _CatalogSettingsScreenState();
}

class _CatalogSettingsScreenState extends State<CatalogSettingsScreen> {
  static const _api = BriskersApi();

  final _search = TextEditingController();
  List<Map<String, dynamic>>? _items;
  String? _error;
  bool _includeInactive = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final query = _search.text.trim();
      final items = await _api.catalogItemsSettings(
        widget.businessId,
        search: query.isEmpty ? null : query,
        includeInactive: _includeInactive,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(value);
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'service':
        return 'Service';
      case 'labor':
        return 'Labor';
      case 'fee':
        return 'Fee';
      case 'other':
        return 'Other';
      default:
        return 'Part / Item';
    }
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    if (_busy) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CatalogItemDialog(item: item),
    );
    if (result == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _api.saveCatalogItem(
        widget.businessId,
        itemId: item?['id']?.toString(),
        name: result['name'].toString(),
        description: result['description']?.toString(),
        itemType: result['item_type'].toString(),
        sellingPrice: result['selling_price'] as num,
        pricingUnit: result['pricing_unit']?.toString(),
        cost: result['cost'] as num,
        taxable: result['taxable'] == true,
        category: result['category']?.toString(),
        barcode: result['barcode']?.toString(),
        active: result['active'] == true,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> item) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.saveCatalogItem(
        widget.businessId,
        itemId: item['id'].toString(),
        name: item['name']?.toString() ?? '',
        description: item['description']?.toString(),
        itemType: item['item_type']?.toString() ?? 'non_inventory',
        sellingPrice: num.tryParse(item['selling_price']?.toString() ?? '') ?? 0,
        pricingUnit: item['pricing_unit']?.toString(),
        cost: num.tryParse(item['cost']?.toString() ?? '') ?? 0,
        taxable: item['taxable'] == true,
        category: item['category']?.toString(),
        barcode: item['barcode']?.toString(),
        active: item['active'] != true,
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
    final items = _items ?? const <Map<String, dynamic>>[];
    final activeCount = items.where((item) => item['active'] == true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Items / Catalog'),
        actions: [
          IconButton(
            tooltip: 'Add item',
            onPressed: _busy ? null : () => _edit(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: SearchBar(
              controller: _search,
              hintText: 'Search items, descriptions or categories',
              leading: const Icon(Icons.search),
              trailing: [
                if (_search.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      _search.clear();
                      _load();
                    },
                    icon: const Icon(Icons.close),
                  ),
              ],
              onSubmitted: (_) => _load(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: Row(
              children: [
                Text(
                  _items == null
                      ? 'Loading catalog...'
                      : '${items.length} shown • $activeCount active',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                FilterChip(
                  label: const Text('Include inactive'),
                  selected: _includeInactive,
                  onSelected: (value) {
                    setState(() => _includeInactive = value);
                    _load();
                  },
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _items == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: items.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 100),
                              Center(child: Text('No catalog items found.')),
                            ],
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final active = item['active'] == true;
                              final category =
                                  item['category']?.toString() ?? '';
                              final description =
                                  item['description']?.toString() ?? '';
                              final unit =
                                  item['pricing_unit']?.toString() ?? '';
                              final price = _money(item['selling_price']);

                              return ListTile(
                                enabled: active,
                                leading: CircleAvatar(
                                  backgroundColor: BriskersColors.invoices
                                      .withValues(alpha: 0.12),
                                  child: Icon(
                                    item['item_type']?.toString() == 'service'
                                        ? Icons.build_circle_outlined
                                        : Icons.inventory_2_outlined,
                                    color: BriskersColors.invoices,
                                  ),
                                ),
                                title: Text(
                                  item['name']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  <String>[
                                    if (category.isNotEmpty) category,
                                    _typeLabel(
                                      item['item_type']?.toString() ??
                                          'non_inventory',
                                    ),
                                    if (description.isNotEmpty) description,
                                    if (!active) 'Inactive',
                                  ].join(' • '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          price,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (unit.isNotEmpty)
                                          Text(
                                            '/ $unit',
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') _edit(item);
                                        if (value == 'toggle') {
                                          _toggleActive(item);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                        PopupMenuItem(
                                          value: 'toggle',
                                          child: Text(
                                            active
                                                ? 'Make inactive'
                                                : 'Reactivate',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                onTap: _busy ? null : () => _edit(item),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
    );
  }
}

class _CatalogItemDialog extends StatefulWidget {
  const _CatalogItemDialog({this.item});

  final Map<String, dynamic>? item;

  @override
  State<_CatalogItemDialog> createState() => _CatalogItemDialogState();
}

class _CatalogItemDialogState extends State<_CatalogItemDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _unit;
  late final TextEditingController _cost;
  late final TextEditingController _category;
  late final TextEditingController _barcode;
  late String _itemType;
  late bool _taxable;
  late bool _active;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?['name']?.toString() ?? '');
    _description =
        TextEditingController(text: item?['description']?.toString() ?? '');
    _price =
        TextEditingController(text: item?['selling_price']?.toString() ?? '0');
    _unit =
        TextEditingController(text: item?['pricing_unit']?.toString() ?? '');
    _cost = TextEditingController(text: item?['cost']?.toString() ?? '0');
    _category =
        TextEditingController(text: item?['category']?.toString() ?? '');
    _barcode =
        TextEditingController(text: item?['barcode']?.toString() ?? '');
    _itemType = item?['item_type']?.toString() ?? 'non_inventory';
    _taxable = item?['taxable'] != false;
    _active = item?['active'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _unit.dispose();
    _cost.dispose();
    _category.dispose();
    _barcode.dispose();
    super.dispose();
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _save() {
    final price = num.tryParse(_price.text.trim());
    final cost = num.tryParse(_cost.text.trim());

    if (_name.text.trim().isEmpty ||
        price == null ||
        cost == null ||
        price < 0 ||
        cost < 0) {
      setState(() => _error = 'Enter a valid name, price and cost.');
      return;
    }

    Navigator.pop(
      context,
      <String, dynamic>{
        'name': _name.text.trim(),
        'description': _emptyToNull(_description.text),
        'item_type': _itemType,
        'selling_price': price,
        'pricing_unit': _emptyToNull(_unit.text),
        'cost': cost,
        'taxable': _taxable,
        'category': _emptyToNull(_category.text),
        'barcode': _emptyToNull(_barcode.text),
        'active': _active,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Add catalog item' : 'Edit catalog item'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _itemType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(
                    value: 'non_inventory',
                    child: Text('Part / Item'),
                  ),
                  DropdownMenuItem(value: 'service', child: Text('Service')),
                  DropdownMenuItem(value: 'labor', child: Text('Labor')),
                  DropdownMenuItem(value: 'fee', child: Text('Fee')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _itemType = value);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Default selling price',
                        prefixText: '\$ ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _unit,
                      decoration: const InputDecoration(
                        labelText: 'Pricing unit',
                        hintText: 'pc, hr, gal.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Default cost',
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _category,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _barcode,
                decoration: const InputDecoration(labelText: 'Barcode'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Taxable'),
                value: _taxable,
                onChanged: (value) =>
                    setState(() => _taxable = value == true),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
