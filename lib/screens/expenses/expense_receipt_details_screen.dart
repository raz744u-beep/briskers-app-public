import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/briskers_api.dart';

class ExpenseReceiptDetailsScreen extends StatefulWidget {
  const ExpenseReceiptDetailsScreen({
    super.key,
    required this.businessId,
    required this.transactionId,
  });

  final String businessId;
  final String transactionId;

  @override
  State<ExpenseReceiptDetailsScreen> createState() =>
      _ExpenseReceiptDetailsScreenState();
}

class _ExpenseReceiptDetailsScreenState
    extends State<ExpenseReceiptDetailsScreen> {
  static const _api = BriskersApi();

  Map<String, dynamic>? _receipt;
  bool _loading = true;
  bool _busy = false;
  bool _canDelete = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  num _number(Object? raw) =>
      num.tryParse(raw?.toString() ?? '') ?? 0;

  String _money(Object? raw) =>
      NumberFormat.currency(symbol: r'$').format(_number(raw));

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.expenseReceiptStructure(
          widget.businessId,
          widget.transactionId,
        ),
        _api.myPermissions(widget.businessId),
      ]);

      if (!mounted) return;
      setState(() {
        _receipt = Map<String, dynamic>.from(results[0] as Map);
        final permissions = List<String>.from(results[1] as List);
        _canDelete = permissions.contains('records.delete');
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _editHeader() async {
    final receipt = _receipt;
    if (receipt == null || receipt['editable'] == false || _busy) return;

    final invoice = TextEditingController(
      text: receipt['vendor_invoice_number']?.toString() ?? '',
    );
    final total = TextEditingController(
      text: receipt['receipt_total']?.toString() ?? '',
    );
    DateTime? date = DateTime.tryParse(
      receipt['receipt_date']?.toString() ?? '',
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final keyboard =
              MediaQuery.viewInsetsOf(sheetContext).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              keyboard + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Receipt details',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: invoice,
                  decoration: const InputDecoration(
                    labelText: 'Vendor invoice / receipt number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Receipt date'),
                  subtitle: Text(
                    date == null
                        ? 'Not entered'
                        : DateFormat.yMMMd().format(date!),
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: sheetContext,
                      initialDate: date ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(
                        const Duration(days: 365),
                      ),
                    );
                    if (picked != null) {
                      setSheetState(() => date = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: total,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Receipt total',
                    prefixText: r'$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(sheetContext, true),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved != true) {
      invoice.dispose();
      total.dispose();
      return;
    }

    final totalValue = total.text.trim().isEmpty
        ? null
        : num.tryParse(total.text.trim());

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _api.saveExpenseReceiptHeader(
        widget.businessId,
        widget.transactionId,
        vendorInvoiceNumber:
            invoice.text.trim().isEmpty ? null : invoice.text.trim(),
        receiptDate: date,
        receiptTotal: totalValue,
        itemSummary: receipt['item_summary']?.toString(),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      invoice.dispose();
      total.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editItem([Map<String, dynamic>? item]) async {
    final receipt = _receipt;
    if (receipt == null || receipt['editable'] == false || _busy) return;

    final description = TextEditingController(
      text: item?['description']?.toString() ?? '',
    );
    final sku = TextEditingController(
      text: item?['sku']?.toString() ?? '',
    );
    final quantity = TextEditingController(
      text: item?['quantity']?.toString() ?? '',
    );
    final unitPrice = TextEditingController(
      text: item?['unit_price']?.toString() ?? '',
    );
    final total = TextEditingController(
      text: item?['total_amount']?.toString() ?? '',
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  item == null ? 'Add receipt item' : 'Edit receipt item',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: description,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Example: Water pump',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sku,
                decoration: const InputDecoration(
                  labelText: 'SKU / part number (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: quantity,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: unitPrice,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Unit cost',
                        prefixText: r'$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: total,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Item total',
                  prefixText: r'$ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (description.text.trim().isEmpty) return;
                    Navigator.pop(sheetContext, true);
                  },
                  child: const Text('Save item'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true || description.text.trim().isEmpty) {
      description.dispose();
      sku.dispose();
      quantity.dispose();
      unitPrice.dispose();
      total.dispose();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _api.saveExpenseReceiptItem(
        widget.businessId,
        widget.transactionId,
        itemId: item?['id']?.toString(),
        expectedRowVersion: int.tryParse(
          item?['row_version']?.toString() ?? '',
        ),
        description: description.text.trim(),
        sku: sku.text.trim().isEmpty ? null : sku.text.trim(),
        quantity: quantity.text.trim().isEmpty
            ? null
            : num.tryParse(quantity.text.trim()),
        unitPrice: unitPrice.text.trim().isEmpty
            ? null
            : num.tryParse(unitPrice.text.trim()),
        totalAmount: total.text.trim().isEmpty
            ? null
            : num.tryParse(total.text.trim()),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      description.dispose();
      sku.dispose();
      quantity.dispose();
      unitPrice.dispose();
      total.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    if (!_canDelete || _busy) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete receipt item?'),
        content: Text(
          'Delete "${item['description'] ?? 'this item'}"? '
          'Any invoice receipt link to this item will also be removed.',
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
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _api.deleteExpenseReceiptItem(
        widget.businessId,
        widget.transactionId,
        item['id'].toString(),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAttachment(
    Map<String, dynamic> attachment,
  ) async {
    try {
      final url = await _api.signedAttachmentUrl(
        attachment['bucket']?.toString() ?? 'briskers-private',
        attachment['key']?.toString() ?? '',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: IconButton.filled(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final receipt = _receipt;
    if (receipt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt Details')),
        body: Center(child: Text(_error ?? 'Receipt not found.')),
      );
    }

    final editable = receipt['editable'] == true;
    final items = List<dynamic>.from(receipt['items'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final attachments =
        List<dynamic>.from(receipt['attachments'] ?? const [])
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList();
    final vendor = receipt['vendor']?.toString() ?? 'Vendor';
    final invoice =
        receipt['vendor_invoice_number']?.toString().trim() ?? '';
    final receiptDate =
        receipt['receipt_date']?.toString().trim() ?? '';
    final itemSummary =
        receipt['item_summary']?.toString().trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Details'),
        actions: [
          if (editable)
            IconButton(
              tooltip: 'Edit receipt header',
              onPressed: _busy ? null : _editHeader,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      floatingActionButton: editable
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _editItem(),
              icon: const Icon(Icons.add),
              label: const Text('Receipt item'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor,
                      style:
                          Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 10),
                    if (invoice.isNotEmpty)
                      _ReceiptRow(
                        label: 'Vendor invoice',
                        value: invoice,
                      ),
                    if (receiptDate.isNotEmpty)
                      _ReceiptRow(
                        label: 'Receipt date',
                        value: receiptDate,
                      ),
                    _ReceiptRow(
                      label: 'Transaction',
                      value:
                          receipt['transaction_date']?.toString() ?? '',
                    ),
                    _ReceiptRow(
                      label: 'Expense total',
                      value: _money(receipt['transaction_total']),
                    ),
                    if (receipt['receipt_total'] != null)
                      _ReceiptRow(
                        label: 'Receipt total',
                        value: _money(receipt['receipt_total']),
                      ),
                    if (itemSummary.isNotEmpty)
                      _ReceiptRow(
                        label: 'Items',
                        value: itemSummary,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Structured receipt items',
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                ),
                Text('${items.length}'),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No receipt items entered yet. Add the parts from the receipt that may need to be matched to customer invoice items.',
                  ),
                ),
              )
            else
              ...items.map(
                (item) {
                  final linked = List<dynamic>.from(
                    item['linked_invoice_lines'] ?? const [],
                  );
                  return Card(
                    child: ListTile(
                      title: Text(
                        item['description']?.toString() ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        <String>[
                          if ((item['sku']?.toString() ?? '').isNotEmpty)
                            'SKU ${item['sku']}',
                          if (item['quantity'] != null)
                            'Qty ${item['quantity']}',
                          if (item['total_amount'] != null)
                            _money(item['total_amount']),
                          if (linked.isNotEmpty)
                            '${linked.length} invoice link(s)',
                        ].join(' • '),
                      ),
                      onTap: editable ? () => _editItem(item) : null,
                      trailing: _canDelete
                          ? IconButton(
                              tooltip: 'Delete item',
                              onPressed:
                                  _busy ? null : () => _deleteItem(item),
                              icon: const Icon(Icons.delete_outline),
                            )
                          : editable
                              ? const Icon(Icons.chevron_right)
                              : null,
                    ),
                  );
                },
              ),
            const SizedBox(height: 18),
            Text(
              'Original receipt',
              style:
                  Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
            ),
            const SizedBox(height: 8),
            if (attachments.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No receipt photo attached.'),
                ),
              )
            else
              ...attachments.map(
                (attachment) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(
                      attachment['filename']?.toString() ??
                          'Receipt photo',
                    ),
                    trailing: const Icon(Icons.zoom_in),
                    onTap: () => _openAttachment(attachment),
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
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
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
