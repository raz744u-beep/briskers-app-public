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
  List<Map<String, dynamic>> _categories = const [];
  String? _error;
  bool _includeInactive = true;
  bool _busy = false;
  int _searchGeneration = 0;

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
    final generation = ++_searchGeneration;
    try {
      final query = _search.text.trim();
      final results = await Future.wait<dynamic>([
        _api.catalogItemsSettings(
          widget.businessId,
          search: query.isEmpty ? null : query,
          includeInactive: _includeInactive,
        ),
        _api.itemCategories(widget.businessId, includeInactive: true),
      ]);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(results[0] as List);
        _categories = List<Map<String, dynamic>>.from(results[1] as List);
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
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CatalogItemDialog(
        item: item,
        categories: _categories,
      ),
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
              onChanged: (_) {
                setState(() {});
                _load();
              },
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
                            separatorBuilder: (context, index) =>
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
  const _CatalogItemDialog({
    this.item,
    required this.categories,
  });

  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>> categories;

  @override
  State<_CatalogItemDialog> createState() => _CatalogItemDialogState();
}

class _CatalogItemDialogState extends State<_CatalogItemDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _unit;
  late final TextEditingController _cost;
  late final TextEditingController _barcode;
  late String _category;
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
    _category = item?['category']?.toString() ?? '';
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
        'category': _category.trim().isEmpty ? null : _category.trim(),
        'barcode': _emptyToNull(_barcode.text),
        'active': _active,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);

    const fieldBorder = OutlineInputBorder();

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.item == null
                            ? 'Add catalog item'
                            : 'Edit catalog item',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Item name',
                          border: fieldBorder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _description,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Optional invoice description',
                          border: fieldBorder,
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _itemType,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: fieldBorder,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'non_inventory',
                            child: Text('Part / Item'),
                          ),
                          DropdownMenuItem(
                            value: 'service',
                            child: Text('Service'),
                          ),
                          DropdownMenuItem(
                            value: 'labor',
                            child: Text('Labor'),
                          ),
                          DropdownMenuItem(
                            value: 'fee',
                            child: Text('Fee'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _itemType = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _price,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Default price',
                                prefixText: '\$ ',
                                border: fieldBorder,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _unit,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                                hintText: 'pc, hr, gal.',
                                border: fieldBorder,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _cost,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Default cost',
                          prefixText: '\$ ',
                          border: fieldBorder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: fieldBorder,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('No category'),
                          ),
                          ...widget.categories.map((category) {
                            final name =
                                category['name']?.toString() ?? '';
                            final active = category['active'] == true;
                            return DropdownMenuItem(
                              value: name,
                              child: Text(
                                active ? name : '$name (inactive)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) =>
                            setState(() => _category = value ?? ''),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _barcode,
                        decoration: const InputDecoration(
                          labelText: 'Barcode',
                          border: fieldBorder,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Taxable'),
                        subtitle: const Text(
                          'Apply the invoice tax rate to this item',
                        ),
                        value: _taxable,
                        onChanged: (value) =>
                            setState(() => _taxable = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active'),
                        subtitle: const Text(
                          'Inactive items stay in history but are hidden from normal invoice search',
                        ),
                        value: _active,
                        onChanged: (value) =>
                            setState(() => _active = value),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check),
                        label: const Text('Save Item'),
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
