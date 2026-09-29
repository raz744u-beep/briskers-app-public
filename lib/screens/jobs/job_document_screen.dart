import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../../core/briskers_colors.dart';
import '../../core/formatters.dart';
import '../../core/invoice_status_style.dart';
import '../../services/briskers_api.dart';
import '../../services/document_pdf_service.dart';
import '../expenses/expense_detail_screen.dart';
import '../expenses/expense_entry_screen.dart';
import 'job_detail_screen.dart';

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
  final ImagePicker _picker = ImagePicker();

  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _invoiceStyles = const [];
  num _defaultTaxRate = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _estimate => _detail?['kind']?.toString() == 'estimate';
  bool get _converted => _detail?['converted'] == true;
  bool get _readOnly => _estimate && _converted;

  Color get _accent =>
      _estimate ? BriskersColors.estimates : BriskersColors.jobs;

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
      final taxSettings = await _api.taxSettings(widget.businessId);
      List<Map<String, dynamic>> invoiceStyles = const [];
      if (detail['kind']?.toString() == 'invoice') {
        invoiceStyles = await _api.invoiceStatusStyles(widget.businessId);
      }
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _invoiceStyles = invoiceStyles;
        _defaultTaxRate =
            num.tryParse(taxSettings['sales_tax_rate']?.toString() ?? '') ?? 0;
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

  Future<void> _addInvoiceExpense() async {
    if (_estimate || !widget.isOwner || _detail == null) return;
    final number = _detail!['document_number']?.toString().trim() ?? '';
    final jobId = _detail!['job_id']?.toString();
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          jobId: jobId == null || jobId.isEmpty ? null : jobId,
          documentId: widget.documentId,
          contextLabel: number.isEmpty ? 'This invoice' : 'Invoice #$number',
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _showInvoiceExpenses() async {
    if (_estimate || !widget.isOwner) return;
    try {
      final expenses = await _api.documentExpenses(
        widget.businessId,
        widget.documentId,
      );
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Invoice expenses & credits',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          await _addInvoiceExpense();
                        },
                        icon: const Icon(Icons.add_card_outlined),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: expenses.isEmpty
                      ? const Center(
                          child: Text('No expenses or credits linked to this invoice yet.'),
                        )
                      : ListView.separated(
                          itemCount: expenses.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final expense = expenses[index];
                            final id = expense['id']?.toString() ?? '';
                            final vendor =
                                expense['vendor']?.toString() ?? 'Expense';
                            final category =
                                expense['category']?.toString() ?? '';
                            final date =
                                expense['transaction_date']?.toString() ?? '';
                            final receiptCount = int.tryParse(
                                  expense['receipt_count']?.toString() ?? '',
                                ) ??
                                0;
                            final income =
                                expense['direction']?.toString() == 'income';
                            return ListTile(
                              leading: CircleAvatar(
                                child: Icon(
                                  income ? Icons.south_west : Icons.north_east,
                                ),
                              ),
                              title: Text(vendor),
                              subtitle: Text(
                                <String>[
                                  if (category.isNotEmpty) category,
                                  if (date.isNotEmpty) date,
                                  if (receiptCount > 0)
                                    '$receiptCount receipt photo(s)',
                                ].join(' • '),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${income ? '+' : '-'}${_money(expense['amount'])}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: id.isEmpty
                                  ? null
                                  : () async {
                                      Navigator.pop(sheetContext);
                                      await Navigator.push<void>(
                                        this.context,
                                        MaterialPageRoute(
                                          builder: (_) => ExpenseDetailScreen(
                                            businessId: widget.businessId,
                                            transactionId: id,
                                          ),
                                        ),
                                      );
                                      await _load();
                                    },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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

    if (selected == null || !mounted) return;

    final line = <String, dynamic>{
      'name': selected['name']?.toString() ?? 'Item',
      'description': selected['description']?.toString(),
      'quantity': 1,
      'unit_price': _number(selected['selling_price']),
      'tax_rate': selected['taxable'] == true ? _defaultTaxRate : 0,
      'line_kind': 'item',
    };

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EditLineDialog(
        line: line,
        title: 'Add item to invoice',
        saveLabel: 'Add to Invoice',
        lockCatalogFields: true,
      ),
    );
    if (result == null) return;

    await _run(() async {
      await _api.addDocumentLine(
        widget.businessId,
        widget.documentId,
        expectedVersion: _version,
        name: result['name'].toString(),
        description: result['description']?.toString(),
        itemId: selected['id']?.toString(),
        quantity: result['quantity'] as num,
        unitPrice: result['unit_price'] as num,
        taxRate: result['tax_rate'] as num,
        lineKind: result['line_kind'].toString(),
      );
    });
  }

  Future<void> _addCustomLine() async {
    if (_readOnly) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CustomLineDialog(
        defaultTaxRate: _defaultTaxRate,
      ),
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

    if (line['line_kind']?.toString() == 'discount') {
      await _editDiscount(line);
      return;
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EditLineDialog(
        line: line,
        title: 'Edit invoice item',
        saveLabel: 'Save Changes',
        lockCatalogFields: line['item_id'] != null,
      ),
    );
    if (result == null) return;

    await _run(() async {
      await _api.updateDocumentLineV2(
        widget.businessId,
        line['id'].toString(),
        expectedVersion: _version,
        name: result['name'].toString(),
        quantity: result['quantity'] as num,
        unitPrice: result['unit_price'] as num,
        taxRate: result['tax_rate'] as num,
        description: result['description']?.toString(),
        lineKind: result['line_kind'].toString(),
      );
    });
  }

  Future<void> _addDiscount() async {
    if (_readOnly) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _DiscountDialog(),
    );
    if (result == null) return;

    await _run(() async {
      await _api.addDocumentDiscount(
        widget.businessId,
        widget.documentId,
        expectedVersion: _version,
        name: result['name'].toString(),
        method: result['method'].toString(),
        value: result['value'] as num,
        timing: result['timing'].toString(),
        description: result['description']?.toString(),
      );
    });
  }

  Future<void> _editDiscount(Map<String, dynamic> line) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DiscountDialog(line: line),
    );
    if (result == null) return;

    await _run(() async {
      await _api.updateDocumentDiscount(
        widget.businessId,
        line['id'].toString(),
        expectedVersion: _version,
        name: result['name'].toString(),
        method: result['method'].toString(),
        value: result['value'] as num,
        timing: result['timing'].toString(),
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

  Future<void> _copyLine(Map<String, dynamic> line) async {
    if (_readOnly || _busy) return;
    await _run(() => _api.copyDocumentLine(
          widget.businessId,
          line['id'].toString(),
          expectedVersion: _version,
        ));
  }

  Future<void> _moveLine(
    Map<String, dynamic> line,
    String direction,
  ) async {
    if (_readOnly || _busy) return;
    await _run(() => _api.moveDocumentLine(
          widget.businessId,
          line['id'].toString(),
          expectedVersion: _version,
          direction: direction,
        ));
  }

  Future<void> _showLineActions(
    Map<String, dynamic> line, {
    required bool canMoveUp,
    required bool canMoveDown,
  }) async {
    if (_readOnly || _busy) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit item'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy item'),
              onTap: () => Navigator.pop(sheetContext, 'copy'),
            ),
            ListTile(
              enabled: canMoveUp,
              leading: const Icon(Icons.arrow_upward),
              title: const Text('Move up'),
              onTap: canMoveUp
                  ? () => Navigator.pop(sheetContext, 'up')
                  : null,
            ),
            ListTile(
              enabled: canMoveDown,
              leading: const Icon(Icons.arrow_downward),
              title: const Text('Move down'),
              onTap: canMoveDown
                  ? () => Navigator.pop(sheetContext, 'down')
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete item'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'edit') await _editLine(line);
    if (action == 'copy') await _copyLine(line);
    if (action == 'up') await _moveLine(line, 'up');
    if (action == 'down') await _moveLine(line, 'down');
    if (action == 'delete') await _deleteLine(line);
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

  Future<List<Map<String, dynamic>>> _paymentMethods() async {
    final options = await _api.paymentOptions(widget.businessId);
    return List<dynamic>.from(options['methods'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
  }

  Future<void> _enterPayment() async {
    if (_estimate) return;

    List<Map<String, dynamic>> methods;
    try {
      methods = await _paymentMethods();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (!mounted) return;
    if (methods.isEmpty) {
      setState(() => _error = 'No payment methods are configured.');
      return;
    }

    final finalized = _number(_detail?['paid_amount']);
    final pending = _number(_detail?['pending_payment']);
    final total = _number(_detail?['total_amount']);
    final remaining = total - finalized - pending;
    if (remaining <= 0.005) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PaymentEntryDialog(
        methods: methods,
        initialAmount: remaining,
        title: 'Add payment',
        saveLabel: 'Add payment',
      ),
    );
    if (result == null) return;

    await _run(() async {
      await _api.addPendingInvoicePayment(
        widget.businessId,
        widget.documentId,
        amount: result['amount'] as num,
        methodId: result['method_id'].toString(),
      );
    });
  }

  Future<void> _editPayment(Map<String, dynamic> payment) async {
    if (_estimate || payment['state']?.toString() != 'pending') return;

    List<Map<String, dynamic>> methods;
    try {
      methods = await _paymentMethods();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (!mounted || methods.isEmpty) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PaymentEntryDialog(
        methods: methods,
        initialAmount: _number(payment['amount']),
        initialMethodId: payment['payment_method_id']?.toString(),
        title: 'Edit payment',
        saveLabel: 'Save changes',
      ),
    );
    if (result == null) return;

    await _run(() async {
      await _api.updatePendingInvoicePayment(
        widget.businessId,
        payment['id'].toString(),
        amount: result['amount'] as num,
        methodId: result['method_id'].toString(),
      );
    });
  }

  Future<void> _deletePayment(Map<String, dynamic> payment) async {
    if (_estimate || payment['state']?.toString() != 'pending') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove payment?'),
        content: Text(
          'Remove the ${_money(payment['amount'])} '
          '${payment['payment_method_name'] ?? 'payment'} entry?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() => _api.deletePendingInvoicePayment(
          widget.businessId,
          payment['id'].toString(),
        ));
  }

  Future<Map<String, dynamic>?> _pickInvoiceCustomer() async {
    final customers = await _api.customers(widget.businessId, limit: 200);
    if (!mounted) return null;
    var query = '';

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final visible = customers.where((customer) {
            final name = customer['display_name']?.toString() ?? '';
            return query.isEmpty ||
                name.toLowerCase().contains(query.toLowerCase());
          }).toList();

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.72,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Select customer',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search customers',
                      ),
                      onChanged: (value) =>
                          setSheetState(() => query = value.trim()),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final customer = visible[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(
                            customer['display_name']?.toString() ?? '',
                          ),
                          subtitle: Text(
                            '${customer['vehicle_count'] ?? 0} vehicle(s)',
                          ),
                          onTap: () =>
                              Navigator.pop(sheetContext, customer),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _pickInvoiceVehicle(
    String customerId,
  ) async {
    final detail = await _api.customerDetail(widget.businessId, customerId);
    final vehicles = List<dynamic>.from(detail['vehicles'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    if (!mounted) return null;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                'Select vehicle',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('No vehicle'),
              onTap: () => Navigator.pop(
                sheetContext,
                <String, dynamic>{'id': null},
              ),
            ),
            if (vehicles.isNotEmpty) const Divider(),
            ...vehicles.map((vehicle) {
              final label = <String>[
                if (vehicle['year'] != null) vehicle['year'].toString(),
                if ((vehicle['make']?.toString() ?? '').isNotEmpty)
                  vehicle['make'].toString(),
                if ((vehicle['model']?.toString() ?? '').isNotEmpty)
                  vehicle['model'].toString(),
              ].join(' ');

              return ListTile(
                leading: const Icon(Icons.directions_car_outlined),
                title: Text(label.isEmpty ? 'Vehicle' : label),
                subtitle: (vehicle['vin']?.toString() ?? '').isEmpty
                    ? null
                    : Text('VIN: ${vehicle['vin']}'),
                onTap: () => Navigator.pop(sheetContext, vehicle),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _vehicleLabel(Map<String, dynamic>? vehicle) {
    if (vehicle == null || vehicle['id'] == null) return '';
    return <String>[
      if (vehicle['year'] != null) vehicle['year'].toString(),
      if ((vehicle['make']?.toString() ?? '').isNotEmpty)
        vehicle['make'].toString(),
      if ((vehicle['model']?.toString() ?? '').isNotEmpty)
        vehicle['model'].toString(),
    ].join(' ');
  }

  Future<void> _editDocumentHeader() async {
    if (_readOnly || _detail == null || _busy) return;

    var customerId = _detail!['customer_id']?.toString() ?? '';
    var customerName = _detail!['customer_name']?.toString() ?? '';
    String? vehicleId = _detail!['vehicle_id']?.toString();
    var vehicleName = _detail!['vehicle']?.toString() ?? '';
    var mileageText = _detail!['odometer_in']?.toString().trim() ?? '';
    var date = DateTime.tryParse(
          _detail!['document_date']?.toString() ?? '',
        ) ??
        DateTime.now();

    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      _estimate
                          ? 'Edit estimate details'
                          : 'Edit invoice details',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Customer'),
                  subtitle: Text(customerName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final customer = await _pickInvoiceCustomer();
                    if (customer == null) return;
                    final newId = customer['id']?.toString() ?? '';
                    if (newId.isEmpty) return;

                    final vehicle = await _pickInvoiceVehicle(newId);
                    setSheetState(() {
                      customerId = newId;
                      customerName =
                          customer['display_name']?.toString() ?? '';
                      vehicleId = vehicle?['id']?.toString();
                      vehicleName = _vehicleLabel(vehicle);
                      mileageText = vehicle?['mileage']?.toString().trim() ?? '';
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.directions_car_outlined),
                  title: const Text('Vehicle'),
                  subtitle: Text(
                    vehicleName.isEmpty ? 'No vehicle' : vehicleName,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: customerId.isEmpty
                      ? null
                      : () async {
                          final vehicle =
                              await _pickInvoiceVehicle(customerId);
                          if (vehicle == null) return;
                          setSheetState(() {
                            vehicleId = vehicle['id']?.toString();
                            vehicleName = _vehicleLabel(vehicle);
                            mileageText = vehicle['mileage']?.toString().trim() ?? '';
                          });
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.speed_outlined),
                  title: const Text('Mileage'),
                  subtitle: Text(
                    mileageText.isEmpty
                        ? 'Not entered'
                        : '${_quantity(mileageText)} mi',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: vehicleId == null || vehicleId!.isEmpty
                      ? null
                      : () async {
                          final controller = TextEditingController(
                            text: mileageText,
                          );
                          final saveMileage = await showDialog<bool>(
                            context: sheetContext,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Mileage'),
                              content: TextField(
                                controller: controller,
                                autofocus: true,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Current mileage',
                                  suffixText: 'mi',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('Save'),
                                ),
                              ],
                            ),
                          );
                          if (saveMileage == true) {
                            final raw = controller.text
                                .replaceAll(',', '')
                                .trim();
                            if (raw.isEmpty || num.tryParse(raw) != null) {
                              setSheetState(() => mileageText = raw);
                            } else if (sheetContext.mounted) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Enter valid mileage.'),
                                ),
                              );
                            }
                          }
                          controller.dispose();
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Date'),
                  subtitle: Text(
                    DateFormat('MMM d, yyyy').format(date),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: sheetContext,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (selected != null) {
                      setSheetState(() => date = selected);
                    }
                  },
                ),
                if ((_detail!['job_number']?.toString() ?? '').isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Changing the customer or vehicle will detach this document from its current Job.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: customerId.isEmpty
                        ? null
                        : () => Navigator.pop(sheetContext, true),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (save != true) return;

    final originalCustomerId = _detail!['customer_id']?.toString() ?? '';
    final originalVehicleId = _detail!['vehicle_id']?.toString();
    final originalDate = DateTime.tryParse(
      _detail!['document_date']?.toString() ?? '',
    );
    final originalMileage =
        _detail!['odometer_in']?.toString().replaceAll(',', '').trim() ?? '';
    final newMileage = mileageText.replaceAll(',', '').trim();

    final headerChanged =
        customerId != originalCustomerId ||
        vehicleId != originalVehicleId ||
        originalDate == null ||
        DateUtils.dateOnly(originalDate) != DateUtils.dateOnly(date);

    if (headerChanged) {
      await _run(() async {
        await _api.updateDocumentHeader(
          widget.businessId,
          widget.documentId,
          expectedVersion: _version,
          customerId: customerId,
          vehicleId: vehicleId,
          documentDate: date,
        );
      });

      if (_detail == null ||
          _detail!['customer_id']?.toString() != customerId ||
          _detail!['vehicle_id']?.toString() != vehicleId) {
        if (mounted) {
          setState(() {
            _error =
                'The invoice customer/vehicle change did not persist. Please try again.';
          });
        }
        return;
      }
    }

    if (newMileage != originalMileage) {
      await _run(() async {
        await _api.updateDocumentMileage(
          widget.businessId,
          widget.documentId,
          odometer: newMileage.isEmpty ? null : num.tryParse(newMileage),
        );
      });
    }

    if (mounted && _error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice details updated.')),
      );
    }
  }

  Future<void> _copyInvoice() async {
    if (_estimate || _detail == null || _busy) return;

    var copyNotes = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Copy invoice?'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Copy invoice notes'),
            value: copyNotes,
            onChanged: (value) =>
                setDialogState(() => copyNotes = value == true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Copy invoice'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    String? newId;
    await _run(() async {
      newId = await _api.copyInvoice(
        widget.businessId,
        widget.documentId,
        copyNotes: copyNotes,
      );
    });

    if (!mounted || newId == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: newId!,
          isOwner: widget.isOwner,
        ),
      ),
    );
  }

  Future<void> _deleteOrVoidInvoice() async {
    if (_estimate || _detail == null || _busy) return;

    final finalizedPaid = _number(_detail!['paid_amount']);
    final pendingPaid = _number(_detail!['pending_payment']);

    if (finalizedPaid > 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Paid invoice'),
          content: const Text(
            'This invoice has finalized payment activity, so it cannot be deleted or reused. Use the correction/reversal workflow if it needs to be changed.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (pendingPaid > 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Payments entered'),
          content: const Text(
            'Remove the entered payments first. Once there are no payments on this invoice, it can be reassigned or deleted.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete invoice?'),
        content: const Text(
          'This invoice has no finalized payment. It will be deleted and its invoice number can be reused, even if it was previously previewed, printed, emailed, or shown to the customer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete invoice'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      setState(() {
        _busy = true;
        _error = null;
      });

      await _api.deleteDraftInvoice(
        widget.businessId,
        widget.documentId,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _findingMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _addInvoiceFinding() async {
    if (_estimate || _detail == null || _busy) return;

    final vehicleId = _detail!['vehicle_id']?.toString() ?? '';
    if (vehicleId.isEmpty) {
      setState(() => _error = 'Select a vehicle before adding a finding.');
      return;
    }

    final controller = TextEditingController();
    var includeOnInvoice = true;
    final photos = <XFile>[];

    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Add vehicle finding',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Finding',
                      hintText: 'Describe the issue found during service',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include on invoice notes'),
                    value: includeOnInvoice,
                    onChanged: (value) => setSheetState(
                      () => includeOnInvoice = value == true,
                    ),
                  ),
                  if (photos.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        photos.length == 1
                            ? '1 photo selected'
                            : '${photos.length} photos selected',
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await _picker.pickMultiImage(
                              imageQuality: 88,
                              maxWidth: 1920,
                              maxHeight: 1920,
                            );
                            if (picked.isNotEmpty) {
                              setSheetState(() => photos.addAll(picked));
                            }
                          },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gallery'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final photo = await _picker.pickImage(
                              source: ImageSource.camera,
                              imageQuality: 88,
                              maxWidth: 1920,
                              maxHeight: 1920,
                            );
                            if (photo != null) {
                              setSheetState(() => photos.add(photo));
                            }
                          },
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Camera'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        if (controller.text.trim().isNotEmpty) {
                          Navigator.pop(sheetContext, true);
                        }
                      },
                      child: const Text('Add finding'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final body = controller.text.trim();
    controller.dispose();
    if (save != true || body.isEmpty) return;

    await _run(() async {
      final findingId = await _api.createInvoiceFinding(
        widget.businessId,
        widget.documentId,
        body: body,
        includeOnInvoice: includeOnInvoice,
      );

      for (final photo in photos) {
        await _api.uploadVehicleFindingPhoto(
          widget.businessId,
          findingId,
          filename: photo.name,
          mimeType: _findingMime(photo.name),
          bytes: await photo.readAsBytes(),
        );
      }
    });
  }

  Future<void> _showInvoiceFindings() async {
    if (_estimate || _detail == null || _busy) return;

    final vehicleId = _detail!['vehicle_id']?.toString() ?? '';
    if (vehicleId.isEmpty) {
      setState(() => _error = 'Select a vehicle before viewing findings.');
      return;
    }

    List<Map<String, dynamic>> findings;
    try {
      findings = await _api.vehicleFindings(
        widget.businessId,
        vehicleId,
        includeResolved: false,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.68,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Vehicle findings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add finding',
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _addInvoiceFinding();
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: findings.isEmpty
                    ? const Center(child: Text('No open findings.'))
                    : ListView.separated(
                        itemCount: findings.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final finding = findings[index];
                          final sourceJob =
                              finding['found_job_number']?.toString() ?? '';
                          final sourceInvoice =
                              finding['found_document_number']?.toString() ??
                                  '';

                          return ListTile(
                            leading: const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.deepOrange,
                            ),
                            title: Text(
                              finding['body']?.toString() ?? '',
                            ),
                            subtitle: Text(
                              sourceInvoice.isNotEmpty
                                  ? 'Found on Invoice #$sourceInvoice'
                                  : sourceJob.isNotEmpty
                                      ? 'Found on Job $sourceJob'
                                      : 'Open finding',
                            ),
                            trailing: TextButton(
                              onPressed: () async {
                                Navigator.pop(sheetContext);
                                await _run(() =>
                                    _api.resolveVehicleFindingByInvoice(
                                      widget.businessId,
                                      finding['id'].toString(),
                                      widget.documentId,
                                    ));
                              },
                              child: const Text('Resolve'),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editNotes() async {
    if (_readOnly || _detail == null || _busy) return;

    final controller = TextEditingController(
      text: _detail!['memo']?.toString() ?? '',
    );

    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _estimate ? 'Estimate notes' : 'Invoice notes',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: 'Enter notes that should appear on the document.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.pop(sheetContext, controller.text.trim()),
                  child: const Text('Save notes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();

    if (value == null) return;
    await _run(() => _api.updateDocumentNotes(
          widget.businessId,
          widget.documentId,
          expectedVersion: _version,
          memo: value.isEmpty ? null : value,
        ));
  }

  Future<void> _emailPdf() async {
    await _sharePdf();
  }

  Future<void> _showSendMenu() async {
    if (_busy) return;
    final number = _detail?['document_number']?.toString().trim() ?? '';
    final label = _estimate ? 'Estimate' : 'Invoice';

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Text(
                    number.isEmpty ? 'Send $label' : 'Send $label #$number',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Email'),
                subtitle: const Text('Send the PDF through an email app'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(sheetContext, 'email'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Print PDF'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(sheetContext, 'print'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share PDF'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(sheetContext, 'share'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'email') await _emailPdf();
    if (action == 'print') await _printPdf();
    if (action == 'share') await _sharePdf();
  }

  String _dateLabel(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return '';
    return DateFormat('MMM d, yyyy').format(parsed.toLocal());
  }

  String _quantity(Object? raw) {
    final value = _number(raw);
    if (value == value.roundToDouble()) return value.toInt().toString();
    var text = value.toStringAsFixed(2);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }

  String _taxLabel(List<Map<String, dynamic>> lines) {
    final rates = lines
        .map((line) => _number(line['tax_rate']))
        .where((rate) => rate > 0)
        .toSet();
    if (rates.length != 1) return 'Tax';
    final percent = rates.single * 100;
    var value = percent.toStringAsFixed(2);
    while (value.endsWith('0')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('.')) value = value.substring(0, value.length - 1);
    return 'Tax ($value%)';
  }

  Map<String, dynamic>? _invoiceStyle(String code) {
    for (final item in _invoiceStyles) {
      if (item['code']?.toString() == code) return item;
    }
    return null;
  }

  String _invoiceStatusCode({
    required num total,
    required num finalizedPaid,
    required num pendingPaid,
  }) {
    final rawStatus = _detail?['status']?.toString() ?? 'draft';
    if (rawStatus == 'void') return 'void';
    final shownPaid = finalizedPaid + pendingPaid;
    if (pendingPaid > 0 &&
        total > 0 &&
        shownPaid >= total - 0.005) {
      return 'pending_close';
    }
    if (total > 0 && finalizedPaid >= total - 0.005) return 'paid';
    if (shownPaid > 0) return 'partial';
    return 'open';
  }

  String _statusLabel({
    required num total,
    required num finalizedPaid,
    required num pendingPaid,
  }) {
    final rawStatus = _detail?['status']?.toString() ?? 'draft';
    if (_readOnly) return 'Converted';
    if (_estimate) {
      if (rawStatus == 'void') return 'Void';
      if (rawStatus == 'accepted') return 'Accepted';
      if (rawStatus == 'declined') return 'Declined';
      if (rawStatus == 'expired') return 'Expired';
      if (rawStatus == 'issued') return 'Issued';
      return 'Draft';
    }

    final code = _invoiceStatusCode(
      total: total,
      finalizedPaid: finalizedPaid,
      pendingPaid: pendingPaid,
    );
    final style = _invoiceStyle(code);
    if (style != null) return style['name']?.toString() ?? 'Open';
    switch (code) {
      case 'partial':
        return 'Partial';
      case 'pending_close':
        return 'Pending Close';
      case 'paid':
        return 'Paid';
      case 'void':
        return 'Void';
      default:
        return 'Open';
    }
  }

  Color _statusColor(String label, {String? code}) {
    if (!_estimate && code != null) {
      final style = _invoiceStyle(code);
      if (style != null) {
        return invoiceStatusColorFromHex(
          style['color_hex']?.toString(),
          fallback: BriskersColors.invoices,
        );
      }
    }

    switch (label) {
      case 'Accepted':
        return const Color(0xFF169B62);
      case 'Issued':
        return const Color(0xFF1976D2);
      case 'Void':
      case 'Declined':
      case 'Expired':
        return const Color(0xFFC62828);
      case 'Converted':
        return BriskersColors.estimates;
      default:
        return _accent;
    }
  }

  IconData _statusIcon(String label, {String? code}) {
    if (!_estimate && code != null) {
      final style = _invoiceStyle(code);
      if (style != null) {
        return invoiceStatusIcon(style['icon_key']?.toString());
      }
    }

    switch (label) {
      case 'Accepted':
        return Icons.check_circle;
      case 'Void':
      case 'Declined':
      case 'Expired':
        return Icons.cancel;
      case 'Converted':
        return Icons.transform;
      default:
        return Icons.circle_outlined;
    }
  }

  Widget _statusPill(String label, {String? code}) {
    final color = _statusColor(label, code: code);
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(label, code: code), size: 16, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLinkedJob() async {
    final jobId = _detail?['job_id']?.toString() ?? '';
    if (jobId.isEmpty || !mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          businessId: widget.businessId,
          jobId: jobId,
          roleCode: widget.isOwner ? 'owner' : 'office',
        ),
      ),
    );
    await _load();
  }

  Future<void> _openConvertedInvoice() async {
    final invoiceId = _detail?['converted_invoice_id']?.toString() ?? '';
    if (invoiceId.isEmpty || !mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: invoiceId,
          isOwner: widget.isOwner,
        ),
      ),
    );
    await _load();
  }

  Widget _convertedInvoiceBanner() {
    final invoiceNumber =
        _detail?['converted_invoice_number']?.toString().trim() ?? '';
    final convertedDate = _dateLabel(_detail?['converted_invoice_date']);
    final title = invoiceNumber.isEmpty
        ? 'Converted to Invoice'
        : 'Converted to Invoice #$invoiceNumber';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF8EE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBEBD3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF159447),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: Colors.white,
              size: 23,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: Color(0xFF08752F),
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                ),
                if (convertedDate.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Converted $convertedDate',
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Color(0xFF405064),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _openConvertedInvoice,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF08752F),
              side: const BorderSide(color: Color(0xFF59B875)),
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 9,
              ),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.open_in_new, size: 17),
            label: const Text(
              'View',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerHeader() {
    final customer = _detail?['customer_name']?.toString().trim() ?? '';
    final phone = _detail?['customer_phone']?.toString().trim() ?? '';
    final vehicle = _detail?['vehicle']?.toString().trim() ?? '';
    final vin = _detail?['vehicle_vin']?.toString().trim() ?? '';
    final mileage = _detail?['odometer_in']?.toString().trim() ?? '';
    final date = _dateLabel(_detail?['document_date']);
    final job = _detail?['job_number']?.toString().trim() ?? '';

    Widget infoLine(
      IconData icon,
      String value, {
      bool bold = false,
      int maxLines = 2,
      VoidCallback? onTap,
      Color? valueColor,
      bool underline = false,
    }) {
      final line = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF26354D)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.visible,
              softWrap: true,
              style: TextStyle(
                fontSize: bold ? 18 : 15,
                height: 1.2,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: valueColor ?? const Color(0xFF101827),
                decoration:
                    underline ? TextDecoration.underline : TextDecoration.none,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 22,
              color: valueColor ?? _accent,
            ),
          ],
        ],
      );

      return onTap == null
          ? line
          : InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: line,
              ),
            );
    }

    final vehicleMileage = <String>[
      if (vehicle.isNotEmpty) vehicle,
      if (mileage.isNotEmpty) '${_quantity(mileage)} mi',
    ].join(' · ');

    final customerInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        infoLine(
          Icons.person_outline,
          customer.isEmpty ? 'Customer' : customer,
          bold: true,
          maxLines: 2,
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 8),
          infoLine(
            Icons.phone_outlined,
            formatUsPhone(phone),
            maxLines: 1,
          ),
        ],
        const SizedBox(height: 8),
        infoLine(
          Icons.directions_car_outlined,
          vehicleMileage.isEmpty ? 'No vehicle' : vehicleMileage,
          maxLines: 2,
        ),
        if (vin.isNotEmpty) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              'VIN: $vin',
              softWrap: true,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF405064),
                height: 1.2,
              ),
            ),
          ),
        ],
      ],
    );

    final documentInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        infoLine(
          Icons.calendar_month_outlined,
          date.isEmpty ? 'Date: —' : 'Date: $date',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        infoLine(
          Icons.receipt_long_outlined,
          job.isEmpty ? 'No job' : 'Job $job',
          maxLines: 1,
          onTap: job.isEmpty ? null : _openLinkedJob,
          valueColor: job.isEmpty ? null : _accent,
          underline: job.isNotEmpty,
        ),
      ],
    );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 430) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                customerInfo,
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFD7E0E4)),
                const SizedBox(height: 12),
                documentInfo,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: customerInfo),
              Container(
                width: 1,
                constraints: const BoxConstraints(minHeight: 92),
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: const Color(0xFFD7E0E4),
              ),
              Expanded(flex: 4, child: documentInfo),
            ],
          );
        },
      ),
    );
  }

  Widget _itemsTab(
    List<Map<String, dynamic>> lines, {
    required num shownPaid,
    required num balance,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            color: const Color(0xFFF2F6F7),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    'Item',
                    style: TextStyle(
                      color: Color(0xFF405064),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    'Qty',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF405064),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Text(
                    'Amount',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Color(0xFF405064),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: Text('No items added yet.')),
            )
          else
            ...lines.map((line) {
              final description =
                  line['description']?.toString().trim() ?? '';
              final amount = _number(line['net_amount']);
              return InkWell(
                onTap: _readOnly || _busy ? null : () => _editLine(line),
                onLongPress: _readOnly || _busy
                    ? null
                    : () => _showLineActions(
                          line,
                          canMoveUp:
                              line['position'] != lines.first['position'],
                          canMoveDown:
                              line['position'] != lines.last['position'],
                        ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE1E6E9)),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line['name']?.toString() ?? '',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0D1528),
                              ),
                            ),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                description,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.25,
                                  color: Color(0xFF405064),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 58,
                        child: Text(
                          _quantity(line['quantity']),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15.5,
                            color: Color(0xFF182239),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 92,
                        child: Text(
                          _money(amount),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 15.5,
                            color: Color(0xFF182239),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            child: Column(
              children: [
                _AmountRow(
                  label: 'Subtotal',
                  value: _money(
                    lines
                        .where((line) => line['line_kind'] != 'discount')
                        .fold<num>(
                          0,
                          (sum, line) => sum + _number(line['net_amount']),
                        ),
                  ),
                ),
                if (lines.any((line) => line['line_kind'] == 'discount'))
                  _AmountRow(
                    label: 'Discount',
                    value: _money(
                      lines
                          .where((line) => line['line_kind'] == 'discount')
                          .fold<num>(
                            0,
                            (sum, line) =>
                                sum + _number(line['net_amount']),
                          ),
                    ),
                  ),
                _AmountRow(
                  label: _taxLabel(lines),
                  value: _money(_detail!['tax_amount']),
                ),
                const Divider(height: 18),
                _AmountRow(
                  label: 'TOTAL',
                  value: _money(_detail!['total_amount']),
                  bold: true,
                ),
                if (!_estimate) ...[
                  _AmountRow(
                    label: 'Amount Paid',
                    value: _money(shownPaid),
                    valueColor: shownPaid > 0
                        ? const Color(0xFF0C9A43)
                        : null,
                  ),
                  _AmountRow(
                    label: 'Balance Due',
                    value: _money(balance < 0 ? 0 : balance),
                    bold: balance > 0,
                  ),
                ],
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _paymentTab({
    required num total,
    required num finalizedPaid,
    required num pendingPaid,
    required num balance,
  }) {
    final payments = List<dynamic>.from(_detail?['payments'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final shownPaid = finalizedPaid + pendingPaid;
    final safeBalance = balance < 0 ? 0 : balance;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Text(
            'Payment',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _AmountRow(label: 'Invoice total', value: _money(total)),
                  _AmountRow(
                    label: 'Paid',
                    value: _money(shownPaid),
                    valueColor:
                        shownPaid > 0 ? const Color(0xFF0C9A43) : null,
                  ),
                  const Divider(height: 18),
                  _AmountRow(
                    label: 'Balance',
                    value: _money(safeBalance),
                    bold: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Payments',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (payments.isNotEmpty)
                Text(
                  '${payments.length}',
                  style: const TextStyle(
                    color: Color(0xFF405064),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (payments.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('No payments entered yet.'),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var index = 0; index < payments.length; index++) ...[
                    Builder(
                      builder: (context) {
                        final payment = payments[index];
                        final editable =
                            payment['state']?.toString() == 'pending';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                const Color(0xFF0C9A43).withValues(alpha: 0.10),
                            child: const Icon(
                              Icons.payments_outlined,
                              color: Color(0xFF0C9A43),
                            ),
                          ),
                          title: Text(
                            payment['payment_method_name']?.toString() ??
                                'Payment',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _money(payment['amount']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (editable && !_busy) ...[
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  tooltip: 'Payment options',
                                  onSelected: (value) {
                                    if (value == 'edit') _editPayment(payment);
                                    if (value == 'remove') {
                                      _deletePayment(payment);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(Icons.edit_outlined),
                                        title: Text('Edit payment'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'remove',
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(Icons.delete_outline),
                                        title: Text('Remove payment'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    if (index != payments.length - 1)
                      const Divider(height: 1, indent: 72),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (safeBalance > 0.005)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _enterPayment,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('Add Payment'),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: pendingPaid > 0
                    ? const Color(0xFFFFF4DE)
                    : const Color(0xFFEAF8EE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: pendingPaid > 0
                      ? const Color(0xFFF1CC7A)
                      : const Color(0xFFCBEBD3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    pendingPaid > 0 ? Icons.schedule : Icons.check_circle,
                    color: pendingPaid > 0
                        ? const Color(0xFFE58A00)
                        : const Color(0xFF0C9A43),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    pendingPaid > 0
                        ? 'Paid in full — Pending Close'
                        : 'Paid in full',
                    style: TextStyle(
                      color: pendingPaid > 0
                          ? const Color(0xFFA45F00)
                          : const Color(0xFF08752F),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _notesTab() {
    final memo = _detail?['memo']?.toString().trim() ?? '';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _estimate ? 'Estimate Notes' : 'Invoice Notes',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (!_readOnly)
                TextButton.icon(
                  onPressed: _busy ? null : _editNotes,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 130),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8F7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE0E7E5)),
            ),
            child: Text(
              memo.isEmpty
                  ? (_estimate
                      ? 'No estimate notes yet.'
                      : 'No invoice notes yet.')
                  : memo,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: memo.isEmpty
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : const Color(0xFF182239),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'These notes appear on the PDF preview.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: onTap == null
                    ? Theme.of(context).disabledColor
                    : _accent,
                size: 29,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: onTap == null
                      ? Theme.of(context).disabledColor
                      : _accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          title: const Text('Document'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_detail == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          title: const Text('Document'),
        ),
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
    final statusCode = _estimate
        ? null
        : _invoiceStatusCode(
            total: total,
            finalizedPaid: finalizedPaid,
            pendingPaid: pendingPaid,
          );
    final statusLabel = _statusLabel(
      total: total,
      finalizedPaid: finalizedPaid,
      pendingPaid: pendingPaid,
    );
    final tabCount = _estimate ? 2 : 3;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 1,
          titleSpacing: 0,
          title: Row(
            children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      number.isEmpty
                          ? (_estimate ? 'Estimate' : 'Invoice')
                          : (_estimate
                              ? 'Estimate #$number'
                              : 'Invoice #$number'),
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusPill(statusLabel, code: statusCode),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'More actions',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'refresh') _load();
                if (value == 'convert') _convertEstimate();
                if (value == 'edit') _editDocumentHeader();
                if (value == 'copy') _copyInvoice();
                if (value == 'findings') _showInvoiceFindings();
                if (value == 'expenses') _showInvoiceExpenses();
                if (value == 'add_expense') _addInvoiceExpense();
                if (value == 'delete') _deleteOrVoidInvoice();
              },
              itemBuilder: (context) => [
                if (!_readOnly)
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit document'),
                    ),
                  ),
                if (!_estimate)
                  const PopupMenuItem(
                    value: 'copy',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.copy_outlined),
                      title: Text('Copy invoice'),
                    ),
                  ),
                if (!_estimate)
                  const PopupMenuItem(
                    value: 'findings',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.car_repair_outlined),
                      title: Text('Vehicle findings'),
                    ),
                  ),
                if (!_estimate && widget.isOwner)
                  const PopupMenuItem(
                    value: 'expenses',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.payments_outlined),
                      title: Text('View expenses'),
                    ),
                  ),
                if (!_estimate && widget.isOwner)
                  const PopupMenuItem(
                    value: 'add_expense',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.add_card_outlined),
                      title: Text('Add expense'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.refresh),
                    title: Text('Refresh'),
                  ),
                ),
                if (_estimate && !_converted)
                  const PopupMenuItem(
                    value: 'convert',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.receipt_long_outlined),
                      title: Text('Create invoice'),
                    ),
                  ),
                if (!_estimate)
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete invoice'),
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            _customerHeader(),
            if (_estimate && _converted) _convertedInvoiceBanner(),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFE4E9EB)),
                  bottom: BorderSide(color: Color(0xFFE4E9EB)),
                ),
              ),
              child: TabBar(
                indicatorColor: _accent,
                indicatorWeight: 3,
                labelColor: _accent,
                unselectedLabelColor: const Color(0xFF26354D),
                labelStyle: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
                tabs: [
                  const Tab(text: 'Items'),
                  if (!_estimate) const Tab(text: 'Payment'),
                  const Tab(text: 'Notes'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _itemsTab(
                    lines,
                    shownPaid: shownPaid,
                    balance: balance,
                  ),
                  if (!_estimate)
                    _paymentTab(
                      total: total,
                      finalizedPaid: finalizedPaid,
                      pendingPaid: pendingPaid,
                      balance: balance,
                    ),
                  _notesTab(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Color(0xFFDDE4E6)),
              ),
            ),
            child: Row(
              children: [
                _bottomAction(
                  icon: Icons.add_circle,
                  label: 'Add Item',
                  onTap: _readOnly || _busy
                      ? null
                      : () async {
                          final action =
                              await showModalBottomSheet<String>(
                            context: context,
                            showDragHandle: true,
                            builder: (sheetContext) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(
                                      Icons.inventory_2_outlined,
                                    ),
                                    title: const Text('Add from item list'),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, 'catalog'),
                                  ),
                                  ListTile(
                                    leading:
                                        const Icon(Icons.add_box_outlined),
                                    title: const Text('Add custom line'),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, 'custom'),
                                  ),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.percent_outlined,
                                    ),
                                    title: const Text('Add discount'),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, 'discount'),
                                  ),
                                ],
                              ),
                            ),
                          );
                          if (action == 'catalog') await _addCatalogItem();
                          if (action == 'custom') await _addCustomLine();
                          if (action == 'discount') await _addDiscount();
                        },
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: const Color(0xFFDDE4E6),
                ),
                _bottomAction(
                  icon: Icons.visibility_outlined,
                  label: 'Preview',
                  onTap: _busy ? null : _previewPdf,
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: const Color(0xFFDDE4E6),
                ),
                _bottomAction(
                  icon: Icons.outbox_outlined,
                  label: 'Send',
                  onTap: _busy ? null : _showSendMenu,
                ),
              ],
            ),
          ),
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
    this.valueColor,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
      fontSize: bold ? 18 : 15,
      color: const Color(0xFF182239),
    );
    final valueStyle = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
      fontSize: bold ? 19 : 15,
      color: valueColor ?? const Color(0xFF182239),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

class _CustomLineDialog extends StatefulWidget {
  const _CustomLineDialog({
    required this.defaultTaxRate,
  });

  final num defaultTaxRate;

  @override
  State<_CustomLineDialog> createState() => _CustomLineDialogState();
}

class _CustomLineDialogState extends State<_CustomLineDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _price = TextEditingController(text: '0');
  late final TextEditingController _taxPercent;
  String _lineKind = 'item';
  String? _error;

  @override
  void initState() {
    super.initState();
    var percent = (widget.defaultTaxRate * 100).toStringAsFixed(3);
    while (percent.contains('.') && percent.endsWith('0')) {
      percent = percent.substring(0, percent.length - 1);
    }
    if (percent.endsWith('.')) {
      percent = percent.substring(0, percent.length - 1);
    }
    _taxPercent = TextEditingController(text: percent);
  }

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
  const _EditLineDialog({
    required this.line,
    this.title = 'Edit item',
    this.saveLabel = 'Save',
    this.lockCatalogFields = false,
  });

  final Map<String, dynamic> line;
  final String title;
  final String saveLabel;
  final bool lockCatalogFields;

  @override
  State<_EditLineDialog> createState() => _EditLineDialogState();
}

class _EditLineDialogState extends State<_EditLineDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  late final TextEditingController _taxPercent;
  late String _lineKind;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.line['name']?.toString() ?? '',
    );
    _lineKind = widget.line['line_kind']?.toString() ?? 'item';
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
      setState(() => _error = 'Enter a valid quantity, price and tax.');
      return;
    }

    Navigator.pop(
      context,
      <String, dynamic>{
        'name': _name.text.trim(),
        'line_kind': _lineKind,
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'quantity': _lineKind == 'discount'
            ? -quantity.abs()
            : quantity,
        'unit_price': price,
        'tax_rate': taxPercent / 100,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final keyboardOpen = viewInsets.bottom > 0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.80,
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
                        widget.title,
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
                  padding: EdgeInsets.fromLTRB(
                    18,
                    16,
                    18,
                    keyboardOpen ? 110 : 22,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        readOnly: widget.lockCatalogFields,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Item',
                          border: const OutlineInputBorder(),
                          filled: widget.lockCatalogFields,
                          fillColor: widget.lockCatalogFields
                              ? Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.45)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _description,
                        minLines: 2,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Optional line description',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _quantity,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Qty',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _price,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Price',
                                prefixText: '\$ ',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!widget.lockCatalogFields) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _taxPercent,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Tax',
                            suffixText: '%',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _lineKind,
                          decoration: const InputDecoration(
                            labelText: 'Type',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'item',
                              child: Text('Part / Item'),
                            ),
                            DropdownMenuItem(
                              value: 'labor',
                              child: Text('Labor'),
                            ),
                            DropdownMenuItem(
                              value: 'supply',
                              child: Text('Shop supply'),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text('Other'),
                            ),
                            DropdownMenuItem(
                              value: 'shipping',
                              child: Text('Shipping'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _lineKind = value);
                            }
                          },
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 10),
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
                        label: Text(widget.saveLabel),
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

class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({this.line});

  final Map<String, dynamic>? line;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _value;
  late String _method;
  late String _timing;
  String? _error;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    _name = TextEditingController(
      text: line?['name']?.toString() ?? 'Discount',
    );
    _description = TextEditingController(
      text: line?['description']?.toString() ?? '',
    );
    _method = line?['discount_method']?.toString() ?? 'amount';
    _timing = line?['discount_timing']?.toString() ?? 'before_tax';

    final rawValue = line?['discount_value'];
    final fallback = (num.tryParse(line?['net_amount']?.toString() ?? '') ?? 0)
        .abs();
    _value = TextEditingController(
      text: rawValue?.toString() ?? fallback.toString(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _value.dispose();
    super.dispose();
  }

  void _save() {
    final value = num.tryParse(_value.text.trim());
    if (value == null ||
        value < 0 ||
        (_method == 'percent' && value > 100)) {
      setState(() => _error = _method == 'percent'
          ? 'Enter a percentage from 0 to 100.'
          : 'Enter a valid discount amount.');
      return;
    }

    Navigator.pop(
      context,
      <String, dynamic>{
        'name': _name.text.trim().isEmpty ? 'Discount' : _name.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'method': _method,
        'value': value,
        'timing': _timing,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final keyboardOpen = viewInsets.bottom > 0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: keyboardOpen ? 0.96 : 0.68,
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
                        widget.line == null ? 'Add Discount' : 'Edit Discount',
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
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'amount',
                            label: Text('Amount'),
                            icon: Icon(Icons.attach_money),
                          ),
                          ButtonSegment(
                            value: 'percent',
                            label: Text('Percentage'),
                            icon: Icon(Icons.percent),
                          ),
                        ],
                        selected: {_method},
                        onSelectionChanged: (value) {
                          setState(() => _method = value.first);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _value,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        scrollPadding: const EdgeInsets.only(bottom: 180),
                        decoration: InputDecoration(
                          labelText: _method == 'percent'
                              ? 'Discount percentage'
                              : 'Discount amount',
                          prefixText: _method == 'amount' ? '\$ ' : null,
                          suffixText: _method == 'percent' ? '%' : null,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'before_tax',
                            label: Text('Before Tax'),
                          ),
                          ButtonSegment(
                            value: 'after_tax',
                            label: Text('After Tax'),
                          ),
                        ],
                        selected: {_timing},
                        onSelectionChanged: (value) {
                          setState(() => _timing = value.first);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _timing == 'before_tax'
                            ? 'Tax is recalculated after this discount is applied.'
                            : 'Tax is calculated first, then this discount is subtracted.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _description,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Optional note',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
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
                        label: Text(
                          widget.line == null
                              ? 'Add Discount'
                              : 'Save Discount',
                        ),
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

class _PaymentEntryDialog extends StatefulWidget {
  const _PaymentEntryDialog({
    required this.methods,
    required this.initialAmount,
    this.initialMethodId,
    this.title = 'Add payment',
    this.saveLabel = 'Save payment',
  });

  final List<Map<String, dynamic>> methods;
  final num initialAmount;
  final String? initialMethodId;
  final String title;
  final String saveLabel;

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
    if (amount == null || amount <= 0) {
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
      title: Text(widget.title),
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
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}
