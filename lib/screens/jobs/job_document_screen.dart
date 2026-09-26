import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';
import '../../services/document_pdf_service.dart';

class JobDocumentScreen extends StatefulWidget {
  const JobDocumentScreen({
    super.key,
    required this.businessId,
    required this.documentId,
    required this.isOwner,
  });

  final String businessId;
  final String documentId;
  final bool isOwner;

  @override
  State<JobDocumentScreen> createState() => _JobDocumentScreenState();
}

class _JobDocumentScreenState extends State<JobDocumentScreen> {
  static const _api = BriskersApi();

  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _estimate => _detail?['kind']?.toString() == 'estimate';
  bool get _converted => _detail?['converted'] == true;
  bool get _readOnly => _estimate && _converted;

  Color get _accent =>
      _estimate ? BriskersColors.estimates : BriskersColors.invoices;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await _api.documentDetail(
        widget.businessId,
        widget.documentId,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
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

  int get _version =>
      int.tryParse(_detail?['row_version']?.toString() ?? '') ?? 1;

  num _number(Object? raw) => num.tryParse(raw?.toString() ?? '') ?? 0;

  String _money(Object? raw) =>
      NumberFormat.currency(symbol: '\$').format(_number(raw));

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addCatalogItem() async {
    if (_readOnly) return;

    List<Map<String, dynamic>> items;
    try {
      items = await _api.catalogItemsForSale(widget.businessId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (!mounted) return;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final controller = TextEditingController();
        var filtered = List<Map<String, dynamic>>.from(items);

        return StatefulBuilder(
          builder: (context, setSheetState) {
            void filter(String value) {
              final query = value.trim().toLowerCase();
              setSheetState(() {
                filtered = query.isEmpty
                    ? List<Map<String, dynamic>>.from(items)
                    : items
                        .where(
                          (item) =>
                              (item['name']?.toString().toLowerCase() ?? '')
                                  .contains(query) ||
                              (item['description']
                                          ?.toString()
                                          .toLowerCase() ??
                                      '')
                                  .contains(query),
                        )
                        .toList();
              });
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.78,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        onChanged: filter,
                        decoration: const InputDecoration(
                          labelText: 'Search items',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matching items.'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        _accent.withValues(alpha: 0.12),
                                    child: Icon(
                                      Icons.inventory_2_outlined,
                                      color: _accent,
                                    ),
                                  ),
                                  title: Text(
                                    item['name']?.toString() ?? '',
                                  ),
                                  subtitle: Text(
                                    <String>[
                                      if ((item['category']?.toString() ?? '')
                                          .isNotEmpty)
                                        item['category'].toString(),
                                      _money(item['selling_price']),
                                    ].join(' • '),
                                  ),
                                  onTap: () =>
                                      Navigator.pop(sheetContext, item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null) return;

    await _run(() async {
      await _api.addDocumentLine(
        widget.businessId,
        widget.documentId,
        expectedVersion: _version,
        name: selected['name']?.toString() ?? 'Item',
        description: selected['description']?.toString(),
        itemId: selected['id']?.toString(),
        quantity: 1,
        unitPrice: _number(selected['selling_price']),
        taxRate: 0,
        lineKind: 'item',
      );
    });
  }

  Future<void> _addCustomLine() async {
    if (_readOnly) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CustomLineDialog(),
    );
    if (result == null) return;

    await _run(() async {
      await _api.addDocumentLine(
        widget.businessId,
        widget.documentId,
        expectedVersion: _version,
        name: result['name'].toString(),
        description: result['description']?.toString(),
        quantity: result['quantity'] as num,
        unitPrice: result['unit_price'] as num,
        taxRate: result['tax_rate'] as num,
        lineKind: result['line_kind'].toString(),
      );
    });
  }

  Future<void> _editLine(Map<String, dynamic> line) async {
    if (_readOnly) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditLineDialog(line: line),
    );
    if (result == null) return;

    await _run(() async {
      await _api.updateDocumentLine(
        widget.businessId,
        line['id'].toString(),
        expectedVersion: _version,
        quantity: result['quantity'] as num,
        unitPrice: result['unit_price'] as num,
        taxRate: result['tax_rate'] as num,
        description: result['description']?.toString(),
      );
    });
  }

  Future<void> _deleteLine(Map<String, dynamic> line) async {
    if (_readOnly) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove line?'),
        content: Text(
          'Remove "${line['name'] ?? 'this item'}" from the document?',
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      await _api.deleteDocumentLine(
        widget.businessId,
        line['id'].toString(),
        expectedVersion: _version,
      );
    });
  }

  Future<Map<String, dynamic>?> _preparePdf() async {
    final lines = List<dynamic>.from(_detail?['lines'] ?? const []);
    if (lines.isEmpty) {
      setState(() => _error = 'Add at least one item before creating a PDF.');
      return null;
    }

    try {
      await _api.issueDocument(
        widget.businessId,
        widget.documentId,
        expectedVersion: _version,
      );
      final detail = await _api.documentDetail(
        widget.businessId,
        widget.documentId,
      );
      if (mounted) setState(() => _detail = detail);
      return detail;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return null;
    }
  }

  Future<void> _previewPdf() async {
    final detail = await _preparePdf();
    if (detail == null || !mounted) return;
    final bytes = await DocumentPdfService.build(detail);

    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            backgroundColor: _accent.withValues(alpha: 0.10),
            title: Text(_estimate ? 'Estimate PDF' : 'Invoice PDF'),
          ),
          body: PdfPreview(
            build: (format) async => bytes,
            pdfFileName: DocumentPdfService.fileName(detail),
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
          ),
        ),
      ),
    );
  }

  Future<void> _printPdf() async {
    final detail = await _preparePdf();
    if (detail == null) return;
    final bytes = await DocumentPdfService.build(detail);
    await Printing.layoutPdf(
      name: DocumentPdfService.fileName(detail),
      onLayout: (format) async => bytes,
    );
  }

  Future<void> _sharePdf() async {
    final detail = await _preparePdf();
    if (detail == null) return;
    final bytes = await DocumentPdfService.build(detail);
    await Printing.sharePdf(
      bytes: bytes,
      filename: DocumentPdfService.fileName(detail),
    );
  }

  Future<void> _convertEstimate() async {
    if (!_estimate || _converted) return;

    final lines = List<dynamic>.from(_detail?['lines'] ?? const []);
    if (lines.isEmpty) {
      setState(() => _error = 'Add at least one item before creating an invoice.');
      return;
    }

    String? invoiceId;
    await _run(() async {
      invoiceId = await _api.convertEstimate(
        widget.businessId,
        widget.documentId,
      );
    });

    if (!mounted || invoiceId == null) return;
    await Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: invoiceId!,
          isOwner: widget.isOwner,
        ),
      ),
    );
  }

  Future<void> _enterPayment() async {
    if (_estimate) return;

    Map<String, dynamic> options;
    try {
      options = await _api.paymentOptions(widget.businessId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (!mounted) return;

    final methods = List<dynamic>.from(options['methods'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    if (methods.isEmpty) {
      setState(() => _error = 'No payment methods are configured.');
      return;
    }

    final finalized = _number(_detail?['paid_amount']);
    final pending = _number(_detail?['pending_payment']);
    final total = _number(_detail?['total_amount']);
    final suggested = pending > 0 ? pending : (total - finalized);
    final existingMethod = _detail?['pending_payment_method_id']?.toString();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PaymentEntryDialog(
        methods: methods,
        initialAmount: suggested < 0 ? 0 : suggested,
        initialMethodId: existingMethod,
      ),
    );
    if (result == null) return;

    await _run(() async {
      await _api.setPendingInvoicePayment(
        widget.businessId,
        widget.documentId,
        amount: result['amount'] as num,
        methodId: result['method_id'].toString(),
      );
    });
  }

  Future<void> _finalizePayment() async {
    if (_estimate || _number(_detail?['pending_payment']) <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finalize payment?'),
        content: const Text(
          'This posts the payment to the permanent financial record. Review the invoice and PDF first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Finalize payment'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      await _api.finalizePendingInvoicePayment(
        widget.businessId,
        widget.documentId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _accent.withValues(alpha: 0.10),
          title: const Text('Document'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Document')),
        body: Center(child: Text(_error ?? 'Document not found.')),
      );
    }

    final lines = List<dynamic>.from(_detail!['lines'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final number = _detail!['document_number']?.toString().trim() ?? '';
    final finalizedPaid = _number(_detail!['paid_amount']);
    final pendingPaid = _number(_detail!['pending_payment']);
    final total = _number(_detail!['total_amount']);
    final shownPaid = finalizedPaid + pendingPaid;
    final balance = total - shownPaid;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _accent.withValues(alpha: 0.10),
        title: Text(
          number.isEmpty
              ? (_estimate ? 'Estimate' : 'Invoice')
              : (_estimate ? 'Estimate #$number' : 'Invoice #$number'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: _accent.withValues(alpha: 0.07),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _accent.withValues(alpha: 0.14),
                  child: Icon(
                    _estimate
                        ? Icons.request_quote_outlined
                        : Icons.receipt_long_outlined,
                    color: _accent,
                  ),
                ),
                title: Text(
                  _detail!['customer_name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  <String>[
                    if ((_detail!['vehicle']?.toString() ?? '').isNotEmpty)
                      _detail!['vehicle'].toString(),
                    if ((_detail!['job_number']?.toString() ?? '').isNotEmpty)
                      'Job ${_detail!['job_number']}',
                  ].join(' • '),
                ),
                trailing: _readOnly
                    ? const Chip(label: Text('Converted'))
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Items',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (!_readOnly)
                  PopupMenuButton<String>(
                    tooltip: 'Add item',
                    onSelected: (value) {
                      if (value == 'catalog') _addCatalogItem();
                      if (value == 'custom') _addCustomLine();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'catalog',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.inventory_2_outlined),
                          title: Text('Add from item list'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'custom',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.add_box_outlined),
                          title: Text('Add custom line'),
                        ),
                      ),
                    ],
                    child: Chip(
                      avatar: Icon(Icons.add, color: _accent),
                      label: const Text('Add item'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (lines.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No items added yet.'),
                ),
              )
            else
              ...lines.map(
                (line) => Card(
                  child: ListTile(
                    title: Text(
                      line['name']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      <String>[
                        '${line['quantity']} × ${_money(line['unit_price'])}',
                        if ((line['description']?.toString() ?? '').isNotEmpty)
                          line['description'].toString(),
                      ].join('\n'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _money(
                            line['gross_amount'] ??
                                (_number(line['net_amount']) +
                                    _number(line['tax_amount'])),
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (!_readOnly)
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') _editLine(line);
                              if (value == 'delete') _deleteLine(line);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Remove'),
                              ),
                            ],
                          ),
                      ],
                    ),
                    onTap: _readOnly ? null : () => _editLine(line),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _AmountRow(
                      label: 'Subtotal',
                      value: _money(_detail!['net_amount']),
                    ),
                    _AmountRow(
                      label: 'Tax',
                      value: _money(_detail!['tax_amount']),
                    ),
                    const Divider(),
                    _AmountRow(
                      label: 'Total',
                      value: _money(_detail!['total_amount']),
                      bold: true,
                    ),
                    if (!_estimate) ...[
                      _AmountRow(
                        label: 'Paid',
                        value: _money(shownPaid),
                      ),
                      if (pendingPaid > 0)
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Includes entered payment that is not finalized yet',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      const Divider(),
                      _AmountRow(
                        label: 'Balance Due',
                        value: _money(balance),
                        bold: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!_estimate) ...[
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.payments_outlined,
                        color: BriskersColors.invoices,
                      ),
                      title: Text(
                        pendingPaid > 0
                            ? 'Payment entered: ${_money(pendingPaid)}'
                            : 'Enter payment',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        pendingPaid > 0
                            ? 'Not finalized yet. The PDF can already show the payment.'
                            : 'Enter cash/card/check before previewing the final zero-balance PDF.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : _enterPayment,
                    ),
                    if (pendingPaid > 0) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _finalizePayment,
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Finalize payment'),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.preview_outlined, color: _accent),
                    title: const Text('Preview PDF'),
                    onTap: _busy ? null : _previewPdf,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.print_outlined, color: _accent),
                    title: const Text('Print PDF'),
                    onTap: _busy ? null : _printPdf,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.email_outlined, color: _accent),
                    title: const Text('Email / share PDF'),
                    subtitle: const Text(
                      'Choose Gmail or another email app from the share sheet.',
                    ),
                    onTap: _busy ? null : _sharePdf,
                  ),
                ],
              ),
            ),
            if (_estimate && !_converted) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: BriskersColors.invoices,
                ),
                onPressed: _busy ? null : _convertEstimate,
                icon: const Icon(Icons.arrow_forward_outlined),
                label: const Text('Create invoice from estimate'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _CustomLineDialog extends StatefulWidget {
  const _CustomLineDialog();

  @override
  State<_CustomLineDialog> createState() => _CustomLineDialogState();
}

class _CustomLineDialogState extends State<_CustomLineDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _price = TextEditingController(text: '0');
  final _taxPercent = TextEditingController(text: '0');
  String _lineKind = 'item';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _quantity.dispose();
    _price.dispose();
    _taxPercent.dispose();
    super.dispose();
  }

  void _save() {
    final quantity = num.tryParse(_quantity.text.trim());
    final price = num.tryParse(_price.text.trim());
    final taxPercent = num.tryParse(_taxPercent.text.trim());
    if (_name.text.trim().isEmpty ||
        quantity == null ||
        price == null ||
        taxPercent == null ||
        quantity <= 0 ||
        price < 0 ||
        taxPercent < 0 ||
        taxPercent > 100) {
      setState(() => _error = 'Enter a valid name, quantity, price and tax.');
      return;
    }
    Navigator.pop(
      context,
      <String, dynamic>{
        'name': _name.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'quantity': _lineKind == 'discount' ? -quantity.abs() : quantity,
        'unit_price': price,
        'tax_rate': taxPercent / 100,
        'line_kind': _lineKind,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add custom line'),
      content: SingleChildScrollView(
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
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _lineKind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'item', child: Text('Part / Item')),
                DropdownMenuItem(value: 'labor', child: Text('Labor')),
                DropdownMenuItem(value: 'supply', child: Text('Shop supply')),
                DropdownMenuItem(value: 'discount', child: Text('Discount')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _lineKind = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quantity,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Unit price',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _taxPercent,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tax',
                suffixText: '%',
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _EditLineDialog extends StatefulWidget {
  const _EditLineDialog({required this.line});

  final Map<String, dynamic> line;

  @override
  State<_EditLineDialog> createState() => _EditLineDialogState();
}

class _EditLineDialogState extends State<_EditLineDialog> {
  late final TextEditingController _description;
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  late final TextEditingController _taxPercent;
  String? _error;

  @override
  void initState() {
    super.initState();
    _description = TextEditingController(
      text: widget.line['description']?.toString() ?? '',
    );
    final initialQuantity =
        num.tryParse(widget.line['quantity']?.toString() ?? '') ?? 1;
    _quantity = TextEditingController(
      text: initialQuantity.abs().toString(),
    );
    _price = TextEditingController(
      text: widget.line['unit_price']?.toString() ?? '0',
    );
    final rate = num.tryParse(widget.line['tax_rate']?.toString() ?? '') ?? 0;
    _taxPercent = TextEditingController(text: (rate * 100).toString());
  }

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _price.dispose();
    _taxPercent.dispose();
    super.dispose();
  }

  void _save() {
    final quantity = num.tryParse(_quantity.text.trim());
    final price = num.tryParse(_price.text.trim());
    final taxPercent = num.tryParse(_taxPercent.text.trim());
    if (quantity == null ||
        price == null ||
        taxPercent == null ||
        quantity <= 0 ||
        price < 0 ||
        taxPercent < 0 ||
        taxPercent > 100) {
      setState(() => _error = 'Enter a valid quantity, price and tax.');
      return;
    }

    Navigator.pop(
      context,
      <String, dynamic>{
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'quantity': widget.line['line_kind']?.toString() == 'discount'
            ? -quantity.abs()
            : quantity,
        'unit_price': price,
        'tax_rate': taxPercent / 100,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.line['name']?.toString() ?? 'Edit line'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quantity,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Unit price',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _taxPercent,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tax',
                suffixText: '%',
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

class _PaymentEntryDialog extends StatefulWidget {
  const _PaymentEntryDialog({
    required this.methods,
    required this.initialAmount,
    this.initialMethodId,
  });

  final List<Map<String, dynamic>> methods;
  final num initialAmount;
  final String? initialMethodId;

  @override
  State<_PaymentEntryDialog> createState() => _PaymentEntryDialogState();
}

class _PaymentEntryDialogState extends State<_PaymentEntryDialog> {
  late final TextEditingController _amount;
  late String _methodId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.initialAmount.toStringAsFixed(2),
    );
    final existing = widget.initialMethodId;
    _methodId = existing != null &&
            widget.methods.any((item) => item['id']?.toString() == existing)
        ? existing
        : widget.methods.first['id'].toString();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final amount = num.tryParse(_amount.text.trim());
    if (amount == null || amount < 0) {
      setState(() => _error = 'Enter a valid payment amount.');
      return;
    }
    Navigator.pop(
      context,
      <String, dynamic>{
        'amount': amount,
        'method_id': _methodId,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '\$ ',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _methodId,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: widget.methods
                .map(
                  (method) => DropdownMenuItem<String>(
                    value: method['id'].toString(),
                    child: Text(method['name']?.toString() ?? ''),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _methodId = value);
            },
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save payment'),
        ),
      ],
    );
  }
}
