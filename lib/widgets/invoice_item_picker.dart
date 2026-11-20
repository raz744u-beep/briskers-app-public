import 'package:flutter/material.dart';

/// Searches the saved catalog without waiting for a network bootstrap.
class InvoiceItemPicker extends StatefulWidget {
  const InvoiceItemPicker({super.key, required this.items, required this.accent});
  final List<Map<String, dynamic>> items;
  final Color accent;

  @override
  State<InvoiceItemPicker> createState() => _InvoiceItemPickerState();
}

class _InvoiceItemPickerState extends State<InvoiceItemPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    // Provisional catalog keys are replaced during their own sync and cannot
    // be used as the UUID catalog link of an existing document line.
    final items = widget.items.where((item) =>
      !(item['id']?.toString().startsWith('local-catalog-') ?? false) &&
      (query.isEmpty || ['name', 'description', 'barcode', 'category'].any((key) =>
        (item[key]?.toString() ?? '').toLowerCase().contains(query)))).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 4, 10, 12),
            child: Row(children: [
              const Expanded(child: Text('Replace invoice item',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
            ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(autofocus: true,
              decoration: InputDecoration(labelText: 'Search saved items',
                prefixIcon: Icon(Icons.search, color: widget.accent),
                border: const OutlineInputBorder()),
              onChanged: (value) => setState(() => _query = value))),
          const SizedBox(height: 8),
          Expanded(child: items.isEmpty
            ? const Center(child: Text('No matching saved items.'))
            : ListView.builder(itemCount: items.length, itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  title: Text(item['name']?.toString() ?? 'Item'),
                  subtitle: Text(item['description']?.toString() ?? ''),
                  trailing: Text('\$${(num.tryParse(item['selling_price']?.toString() ?? '') ?? 0).toStringAsFixed(2)}'),
                  onTap: () => Navigator.pop(context, item),
                );
              })),
        ]),
      ),
    );
  }
}
