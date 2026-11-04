// ignore_for_file: prefer_interpolation_to_compose_strings, use_null_aware_elements, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Explicit operator confirmation before receipt fields alter expense entry.
/// Keeps the existing expense editor; it does not create any transaction.
class ReceiptReviewSheet extends StatefulWidget {
  const ReceiptReviewSheet({super.key, required this.extraction});

  final Map<String, dynamic> extraction;

  @override
  State<ReceiptReviewSheet> createState() => _ReceiptReviewSheetState();
}

class _ItemDraft {
  _ItemDraft(Map<String, dynamic> row)
    : description = TextEditingController(
        text: row['description']?.toString() ?? '',
      ),
      sku = TextEditingController(text: row['sku']?.toString() ?? ''),
      quantity = TextEditingController(text: row['quantity']?.toString() ?? ''),
      unitPrice = TextEditingController(
        text: row['unit_price']?.toString() ?? '',
      ),
      total = TextEditingController(
        text: row['total_amount']?.toString() ?? '',
      );

  final TextEditingController description;
  final TextEditingController sku;
  final TextEditingController quantity;
  final TextEditingController unitPrice;
  final TextEditingController total;

  void dispose() {
    description.dispose();
    sku.dispose();
    quantity.dispose();
    unitPrice.dispose();
    total.dispose();
  }
}

class _ReceiptReviewSheetState extends State<ReceiptReviewSheet> {
  late final TextEditingController _vendor;
  late final TextEditingController _invoice;
  late final TextEditingController _date;
  late final TextEditingController _total;
  final List<_ItemDraft> _items = [];
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final extraction = widget.extraction;
    _vendor = TextEditingController(
      text: extraction['vendor_name']?.toString() ?? '',
    );
    _invoice = TextEditingController(
      text: extraction['vendor_invoice_number']?.toString() ?? '',
    );
    _date = TextEditingController(
      text: extraction['receipt_date']?.toString() ?? '',
    );
    _total = TextEditingController(
      text: extraction['receipt_total']?.toString() ?? '',
    );
    final raw = extraction['items'];
    if (raw is List) {
      for (final row in raw) {
        if (row is Map) _items.add(_ItemDraft(Map<String, dynamic>.from(row)));
      }
    }
  }

  @override
  void dispose() {
    _vendor.dispose();
    _invoice.dispose();
    _date.dispose();
    _total.dispose();
    for (final row in _items) {
      row.dispose();
    }
    super.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType keyboard = TextInputType.text,
  }) => TextField(
    controller: controller,
    keyboardType: keyboard,
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    ),
  );

  void _accept() {
    final date = _date.text.trim();
    final parsedDate = DateTime.tryParse(date);
    if (date.isNotEmpty &&
        (parsedDate == null ||
            date.length != 10 ||
            parsedDate.toIso8601String().substring(0, 10) != date)) {
      setState(() => _validationError = 'Use YYYY-MM-DD for the receipt date.');
      return;
    }
    final amountText = _total.text.trim().replaceAll(',', '');
    final amount = num.tryParse(amountText);
    if (amountText.isNotEmpty &&
        (amount == null || !amount.isFinite || amount <= 0)) {
      setState(
        () => _validationError =
            'Check the receipt total, or leave it empty for manual entry.',
      );
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (final row in _items) {
      final description = row.description.text.trim();
      if (description.isEmpty) continue;
      final qtyText = row.quantity.text.trim();
      final unitText = row.unitPrice.text.trim();
      final lineText = row.total.text.trim();
      final qty = int.tryParse(qtyText);
      final unit = num.tryParse(unitText.replaceAll(',', ''));
      final lineTotal = num.tryParse(lineText.replaceAll(',', ''));
      if ((qtyText.isNotEmpty && (qty == null || qty <= 0)) ||
          (unitText.isNotEmpty &&
              (unit == null || !unit.isFinite || unit < 0)) ||
          (lineText.isNotEmpty &&
              (lineTotal == null || !lineTotal.isFinite || lineTotal < 0))) {
        setState(
          () => _validationError =
              'Check quantity and item prices in each part line.',
        );
        return;
      }
      items.add(<String, dynamic>{
        'position': items.length + 1,
        'description': description,
        if (row.sku.text.trim().isNotEmpty) 'sku': row.sku.text.trim(),
        if (qty != null) 'quantity': qty,
        if (unit != null) 'unit_price': unit,
        if (lineTotal != null) 'total_amount': lineTotal,
      });
    }

    final extraction = Map<String, dynamic>.from(widget.extraction);
    extraction.remove('vendor_name');
    extraction.remove('vendor_invoice_number');
    extraction.remove('receipt_date');
    extraction.remove('receipt_total');
    if (_vendor.text.trim().isNotEmpty)
      extraction['vendor_name'] = _vendor.text.trim();
    if (_invoice.text.trim().isNotEmpty)
      extraction['vendor_invoice_number'] = _invoice.text.trim();
    if (date.isNotEmpty) extraction['receipt_date'] = date;
    if (amount != null) extraction['receipt_total'] = amount;
    extraction['items'] = items;
    extraction['review_confirmed'] = true;
    Navigator.pop(context, extraction);
  }

  @override
  Widget build(BuildContext context) {
    final flags = (widget.extraction['review_flags'] is List)
        ? (widget.extraction['review_flags'] as List)
              .map((item) => item.toString())
              .toList()
        : <String>[];
    final metadata = widget.extraction['raw_data'];
    final rawText = metadata is Map
        ? metadata['ocr_text']?.toString() ?? ''
        : '';
    final rowCount = metadata is Map ? metadata['ocr_line_count'] : null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Review receipt (read on device)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Keep photo only',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    const Text(
                      'Please correct uncertain information before applying it to the expense. No expense is saved until you tap Save Transaction.',
                    ),
                    if (flags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Needs review: ' + flags.join('; '),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (rawText.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ExpansionTile(
                        key: const ValueKey('local-receipt-ocr-details'),
                        tilePadding: EdgeInsets.zero,
                        title: const Text('View text recognized on phone'),
                        subtitle: Text(
                          rowCount == null
                              ? 'Local OCR text — never uploaded automatically'
                              : 'Local OCR text ($rowCount recognized lines)',
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const ValueKey('copy-local-receipt-ocr'),
                              icon: const Icon(Icons.copy_outlined),
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: rawText),
                              ),
                              label: const Text('Copy recognized text'),
                            ),
                          ),
                          Container(
                            alignment: Alignment.topLeft,
                            width: double.infinity,
                            constraints: const BoxConstraints(maxHeight: 220),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                rawText,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    _field(_vendor, 'Vendor'),
                    const SizedBox(height: 10),
                    _field(_invoice, 'Vendor invoice number (preserves zeros)'),
                    const SizedBox(height: 10),
                    _field(_date, 'Receipt date YYYY-MM-DD'),
                    const SizedBox(height: 10),
                    _field(
                      _total,
                      'Receipt total',
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Part lines',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Add part'),
                          onPressed: () =>
                              setState(() => _items.add(_ItemDraft({}))),
                        ),
                      ],
                    ),
                    if (_items.isEmpty)
                      const Text(
                        'No trustworthy item rows recognized. Add parts manually if needed.',
                      ),
                    for (var i = 0; i < _items.length; i++) ...[
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Part ' + (i + 1).toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Remove part',
                                    onPressed: () => setState(
                                      () => _items.removeAt(i).dispose(),
                                    ),
                                  ),
                                ],
                              ),
                              _field(_items[i].description, 'Part description'),
                              const SizedBox(height: 8),
                              _field(_items[i].sku, 'Part number / SKU'),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _field(
                                      _items[i].quantity,
                                      'Qty',
                                      keyboard: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _field(
                                      _items[i].unitPrice,
                                      'Unit \$',
                                      keyboard:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _field(
                                      _items[i].total,
                                      'Line \$',
                                      keyboard:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_validationError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _validationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _accept,
                    icon: const Icon(Icons.check),
                    label: const Text('Use reviewed fields'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
