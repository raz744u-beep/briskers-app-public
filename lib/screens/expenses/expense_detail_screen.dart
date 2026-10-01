import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';
import 'expense_entry_screen.dart';

class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.businessId,
    required this.transactionId,
  });

  final String businessId;
  final String transactionId;

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  static const _api = BriskersApi();
  final _picker = ImagePicker();

  Map<String, dynamic>? _detail;
  Map<String, dynamic>? _receiptStructure;
  bool _loading = true;
  bool _canDeleteRecords = false;
  bool _canEditReceipt = false;
  bool _uploading = false;
  String? _deletingAttachmentId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.transactionDetail(
          widget.businessId,
          widget.transactionId,
        ),
        _api.myPermissions(widget.businessId),
      ]);
      final detail = Map<String, dynamic>.from(results[0] as Map);
      final permissions = List<String>.from(results[1] as List);

      Map<String, dynamic>? receiptStructure;
      if (detail['direction']?.toString() != 'income') {
        try {
          receiptStructure = await _api.expenseReceiptStructure(
            widget.businessId,
            widget.transactionId,
          );
        } catch (_) {
          receiptStructure = null;
        }
      }

      if (!mounted) return;
      setState(() {
        _detail = detail;
        _receiptStructure = receiptStructure;
        _canDeleteRecords = permissions.contains('records.delete');
        _canEditReceipt = permissions.contains('expenses.create');
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

  String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(value);
  }

  String _mimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _addReceipt() async {
    if (_uploading) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    List<XFile> files = const [];
    if (source == ImageSource.gallery) {
      files = await _picker.pickMultiImage(imageQuality: 92);
    } else {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (file != null) files = [file];
    }
    if (files.isEmpty) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      for (final file in files) {
        await _api.uploadExpensePhoto(
          widget.businessId,
          widget.transactionId,
          filename: file.name,
          mimeType: _mimeType(file.name),
          bytes: await file.readAsBytes(),
        );
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _replaceReceipt(
    Map<String, dynamic> attachment,
  ) async {
    if (!_canDeleteRecords ||
        _uploading ||
        _deletingAttachmentId != null) {
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose replacement from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take replacement photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    XFile? file;
    if (source == ImageSource.gallery) {
      file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
    } else {
      file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
    }
    if (file == null || !mounted) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      await _api.uploadExpensePhoto(
        widget.businessId,
        widget.transactionId,
        filename: file.name,
        mimeType: _mimeType(file.name),
        bytes: await file.readAsBytes(),
      );

      final attachmentId = attachment['attachment_id']?.toString() ?? '';
      if (attachmentId.isNotEmpty) {
        await _api.deleteExpensePhoto(
          widget.businessId,
          widget.transactionId,
          attachmentId,
          bucket: attachment['bucket']?.toString() ?? 'briskers-private',
          key: attachment['key']?.toString() ?? '',
        );
      }

      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    try {
      final url = await _api.signedAttachmentUrl(
        attachment['bucket']?.toString() ?? 'briskers-private',
        attachment['key']?.toString() ?? '',
      );
      if (!mounted) return;
      final editable = _detail?['editable'] == true;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 300,
                    child: Center(child: Text('Could not load receipt.')),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
              if (editable && _canDeleteRecords)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      await _deleteAttachment(attachment);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete photo'),
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

  Future<void> _deleteAttachment(
    Map<String, dynamic> attachment,
  ) async {
    final attachmentId = attachment['attachment_id']?.toString() ?? '';
    if (attachmentId.isEmpty || _deletingAttachmentId != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete receipt photo?'),
        content: const Text(
          'The photo will be removed from this transaction.',
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
    if (confirmed != true || !mounted) return;

    setState(() {
      _deletingAttachmentId = attachmentId;
      _error = null;
    });

    try {
      await _api.deleteExpensePhoto(
        widget.businessId,
        widget.transactionId,
        attachmentId,
        bucket: attachment['bucket']?.toString() ?? 'briskers-private',
        key: attachment['key']?.toString() ?? '',
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _deletingAttachmentId = null);
    }
  }

  Future<void> _edit() async {
    final detail = _detail;
    if (detail == null || _busy) return;

    final options = await _api.transactionOptions(widget.businessId);
    if (!mounted) return;

    final accounts = List<dynamic>.from(options['accounts'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final categories = List<dynamic>.from(options['categories'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final counterparties =
        List<dynamic>.from(options['counterparties'] ?? const [])
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList();

    final amount = TextEditingController(
      text: detail['amount']?.toString() ?? '',
    );
    final remarks = TextEditingController(
      text: detail['remarks']?.toString() ?? '',
    );

    var direction =
        detail['direction']?.toString() == 'income' ? 'income' : 'expense';
    String? accountId = detail['account_id']?.toString();
    String? categoryId = detail['category_id']?.toString();
    String? counterpartyId = detail['counterparty_id']?.toString();
    var date = DateTime.tryParse(detail['date']?.toString() ?? '') ??
        DateTime.now();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, keyboard + 16),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.82,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Edit expense',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        children: [
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'expense',
                                label: Text('Expense'),
                                icon: Icon(Icons.north_east),
                              ),
                              ButtonSegment(
                                value: 'income',
                                label: Text('Income'),
                                icon: Icon(Icons.south_west),
                              ),
                            ],
                            selected: {direction},
                            onSelectionChanged: (value) => setSheetState(
                              () => direction = value.first,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: amount,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            scrollPadding:
                                const EdgeInsets.only(bottom: 160),
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                              prefixText: r'$',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String?>(
                            initialValue: counterpartyId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText:
                                  direction == 'income' ? 'Payer' : 'Payee',
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('None'),
                              ),
                              ...counterparties.map(
                                (item) => DropdownMenuItem<String?>(
                                  value: item['id']?.toString(),
                                  child: Text(
                                    item['name']?.toString() ?? '',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                setSheetState(() => counterpartyId = value),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: categoryId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                            ),
                            items: categories
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item['id']?.toString(),
                                    child: Text(
                                      item['name']?.toString() ?? '',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setSheetState(() => categoryId = value),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: accountId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: direction == 'income'
                                  ? 'Deposited to'
                                  : 'Paid from',
                              border: const OutlineInputBorder(),
                            ),
                            items: accounts
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item['id']?.toString(),
                                    child: Text(
                                      item['name']?.toString() ?? '',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setSheetState(() => accountId = value),
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading:
                                const Icon(Icons.calendar_today_outlined),
                            title: const Text('Transaction date'),
                            subtitle: Text(
                              '${date.month}/${date.day}/${date.year}',
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
                          const SizedBox(height: 8),
                          TextField(
                            controller: remarks,
                            minLines: 2,
                            maxLines: 5,
                            scrollPadding:
                                const EdgeInsets.only(bottom: 160),
                            decoration: const InputDecoration(
                              labelText: 'Description / notes',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final parsed =
                            num.tryParse(amount.text.trim().replaceAll(',', ''));
                        if (parsed == null ||
                            parsed <= 0 ||
                            accountId == null ||
                            categoryId == null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Amount, category and account are required.',
                              ),
                            ),
                          );
                          return;
                        }

                        Map<String, dynamic>? selectedCounterparty;
                        for (final item in counterparties) {
                          if (item['id']?.toString() == counterpartyId) {
                            selectedCounterparty = item;
                            break;
                          }
                        }

                        await _api.updateManualTransaction(
                          widget.businessId,
                          widget.transactionId,
                          direction: direction,
                          accountId: accountId!,
                          categoryId: categoryId!,
                          amount: parsed,
                          date: date,
                          jobId: detail['job_id']?.toString(),
                          documentId: detail['document_id']?.toString(),
                          counterpartyId: counterpartyId,
                          counterpartyName:
                              selectedCounterparty?['name']?.toString(),
                          remarks: remarks.text.trim(),
                        );

                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext, true);
                        }
                      },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save changes'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    amount.dispose();
    remarks.dispose();
    if (saved == true) await _load();
  }

  Future<void> _copy() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          copyTransactionId: widget.transactionId,
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final detail = _detail;
    if (detail == null || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text(
          'The transaction will disappear from normal views but remain in the audit history.',
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

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.voidManualTransaction(
        widget.businessId,
        widget.transactionId,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _handleMenu(String value) async {
    if (value == 'edit') await _edit();
    if (value == 'copy') await _copy();
    if (value == 'delete') await _delete();
  }

  Future<void> _editReceiptHeader() async {
    if (!_canEditReceipt || _busy) return;

    final receipt = _receiptStructure ?? const <String, dynamic>{};
    final invoiceNumber = TextEditingController(
      text: receipt['vendor_invoice_number']?.toString() ?? '',
    );
    final total = TextEditingController(
      text: receipt['receipt_total']?.toString() ??
          receipt['transaction_total']?.toString() ??
          '',
    );
    var receiptDate = DateTime.tryParse(
      receipt['receipt_date']?.toString() ??
          receipt['transaction_date']?.toString() ??
          '',
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
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
                controller: invoiceNumber,
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
                  receiptDate == null
                      ? 'Not set'
                      : DateFormat('MMM d, yyyy').format(receiptDate!),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: sheetContext,
                    initialDate: receiptDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(
                      const Duration(days: 366),
                    ),
                  );
                  if (picked != null) {
                    setSheetState(() => receiptDate = picked);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: total,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Receipt total',
                  prefixText: '\Map<String, dynamic> attachment) {
    const size = 52.0;
    final bucket = attachment['bucket']?.toString() ?? '';
    final key = attachment['key']?.toString() ?? '';

    if (bucket.isEmpty || key.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BriskersColors.expenses.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.broken_image_outlined),
      );
    }

    return FutureBuilder<String>(
      future: _api.signedAttachmentUrl(bucket, key),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: snapshot.hasError
                ? const Icon(Icons.broken_image_outlined)
                : const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snapshot.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: Center(child: Text(_error ?? 'Transaction not found.')),
      );
    }

    final income = detail['direction']?.toString() == 'income';
    final editable = detail['editable'] == true;
    final deletable = detail['deletable'] == true;
    final attachments = List<dynamic>.from(detail['attachments'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final counterparty = detail['counterparty']?.toString() ??
        (income ? 'Income' : 'Expense');
    final category = detail['category']?.toString() ?? '';
    final account = detail['account']?.toString() ?? '';
    final date = detail['date']?.toString() ?? '';
    final remarks = detail['remarks']?.toString() ?? '';
    final jobNumber = detail['job_number']?.toString().trim() ?? '';
    final jobTitle = detail['job_title']?.toString().trim() ?? '';
    final customerName =
        detail['job_customer_name']?.toString().trim() ?? '';
    final documentNumber = detail['document_number']?.toString().trim() ?? '';
    final contextLine = <String>[
      if (customerName.isNotEmpty) customerName,
      if (jobNumber.isNotEmpty || jobTitle.isNotEmpty)
        <String>[
          if (jobNumber.isNotEmpty) jobNumber,
          if (jobTitle.isNotEmpty) jobTitle,
        ].join(' — '),
      if (documentNumber.isNotEmpty) 'Invoice #$documentNumber',
    ].join(' • ');
    final recurring = detail['recurring_rule'];
    final color =
        income ? const Color(0xFF169B62) : BriskersColors.expenses;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color.withValues(alpha: 0.10),
        title: Text(income ? 'Income' : 'Expense'),
        actions: [
          if (editable)
            PopupMenuButton<String>(
              onSelected: _handleMenu,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit transaction'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.copy_outlined),
                    title: Text('Copy transaction'),
                  ),
                ),
                if (deletable)
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete transaction'),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(
                      income ? Icons.south_west : Icons.north_east,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      counterparty,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${income ? '+' : '-'}${_money(detail['amount'])}',
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (contextLine.isNotEmpty) ...[
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text(
                  'Linked to',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(contextLine),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (remarks.isNotEmpty) ...[
            Text(
              'Description / notes',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(remarks),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _DetailRow(label: 'Category', value: category),
          _DetailRow(label: 'Account', value: account),
          _DetailRow(label: 'Date', value: date),
          if (jobNumber.isNotEmpty)
            _DetailRow(label: 'Job', value: jobNumber),
          if (documentNumber.isNotEmpty)
            _DetailRow(label: 'Invoice', value: documentNumber),
          if (recurring is Map)
            _DetailRow(
              label: 'Repeating',
              value: <String>[
                recurring['frequency']?.toString() ?? '',
                if ((recurring['next_date']?.toString() ?? '').isNotEmpty)
                  'next ${recurring['next_date']}',
              ].where((x) => x.isNotEmpty).join(' • '),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Receipts',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (editable)
                TextButton.icon(
                  onPressed: _uploading ? null : _addReceipt,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(_uploading ? 'Uploading...' : 'Add'),
                ),
            ],
          ),
          if (attachments.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No receipt photos attached.'),
              ),
            )
          else
            ...attachments.map(
              (attachment) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _openAttachment(attachment),
                        child: _receiptThumbnail(attachment),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'View receipt',
                        onPressed: () => _openAttachment(attachment),
                        icon: const Icon(Icons.zoom_in),
                      ),
                      if (editable)
                        IconButton(
                          tooltip: 'Replace receipt photo',
                          onPressed: _uploading
                              ? null
                              : () => _replaceReceipt(attachment),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      if (editable)
                        IconButton(
                          tooltip: 'Delete receipt photo',
                          onPressed:
                              _deletingAttachmentId ==
                                      attachment['attachment_id']?.toString()
                                  ? null
                                  : () => _deleteAttachment(attachment),
                          icon: _deletingAttachmentId ==
                                  attachment['attachment_id']?.toString()
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Receipt Details',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_canEditReceipt)
                TextButton.icon(
                  onPressed: _busy ? null : _editReceiptHeader,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Edit'),
                ),
            ],
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Builder(
                builder: (context) {
                  final receipt =
                      _receiptStructure ?? const <String, dynamic>{};
                  final invoice =
                      receipt['vendor_invoice_number']?.toString() ?? '';
                  final receiptDate =
                      receipt['receipt_date']?.toString() ?? '';
                  final receiptTotal =
                      receipt['receipt_total'];
                  final summary =
                      receipt['item_summary']?.toString() ?? '';

                  if (invoice.isEmpty &&
                      receiptDate.isEmpty &&
                      receiptTotal == null &&
                      summary.isEmpty) {
                    return const Text(
                      'No structured receipt details yet. The receipt photo remains the original source document.',
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (invoice.isNotEmpty)
                        _DetailRow(
                          label: 'Vendor invoice',
                          value: invoice,
                        ),
                      if (receiptDate.isNotEmpty)
                        _DetailRow(
                          label: 'Receipt date',
                          value: receiptDate,
                        ),
                      if (receiptTotal != null)
                        _DetailRow(
                          label: 'Receipt total',
                          value: _money(receiptTotal),
                        ),
                      if (summary.isNotEmpty)
                        _DetailRow(
                          label: 'Items',
                          value: summary,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Receipt Items',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_canEditReceipt)
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _editReceiptItem(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                ),
            ],
          ),
          Builder(
            builder: (context) {
              final items = List<dynamic>.from(
                _receiptStructure?['items'] ?? const <dynamic>[],
              )
                  .whereType<Map>()
                  .map((raw) => Map<String, dynamic>.from(raw))
                  .toList();

              if (items.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No structured receipt items yet.',
                    ),
                  ),
                );
              }

              return Column(
                children: items.map((item) {
                  final linked = List<dynamic>.from(
                    item['linked_invoice_lines'] ??
                        const <dynamic>[],
                  );
                  final priceParts = <String>[
                    if (item['quantity'] != null)
                      'Qty ${item['quantity']}',
                    if (item['total_amount'] != null)
                      _money(item['total_amount']),
                  ];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(
                        Icons.inventory_2_outlined,
                      ),
                      title: Text(
                        item['description']?.toString() ??
                            'Receipt item',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        <String>[
                          if ((item['sku']?.toString() ?? '')
                              .isNotEmpty)
                            'SKU ${item['sku']}',
                          ...priceParts,
                          if (linked.isNotEmpty)
                            linked.length == 1
                                ? 'Linked to customer invoice'
                                : 'Linked to ${linked.length} invoice items',
                        ].join(' • '),
                      ),
                      onTap: _canEditReceipt
                          ? () => _editReceiptItem(item)
                          : null,
                      trailing: _canDeleteRecords
                          ? IconButton(
                              tooltip: 'Delete receipt item',
                              onPressed: _busy
                                  ? null
                                  : () => _deleteReceiptItem(item),
                              icon: const Icon(
                                Icons.delete_outline,
                              ),
                            )
                          : _canEditReceipt
                              ? const Icon(Icons.edit_outlined)
                              : null,
                    ),
                  );
                }).toList(),
              );
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final invoiceValue = invoiceNumber.text.trim();
    final totalValue = num.tryParse(total.text.trim());
    invoiceNumber.dispose();
    total.dispose();

    if (saved != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await _api.saveExpenseReceiptHeader(
        widget.businessId,
        widget.transactionId,
        vendorInvoiceNumber:
            invoiceValue.isEmpty ? null : invoiceValue,
        receiptDate: receiptDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(receiptDate!),
        receiptTotal: totalValue,
        itemSummary:
            _receiptStructure?['item_summary']?.toString(),
      );
      if (mounted) {
        setState(() => _receiptStructure = updated);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editReceiptItem([
    Map<String, dynamic>? item,
  ]) async {
    if (!_canEditReceipt || _busy) return;

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
    final totalAmount = TextEditingController(
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
                  item == null
                      ? 'Add receipt item'
                      : 'Edit receipt item',
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
                textCapitalization: TextCapitalization.sentences,
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
                  labelText: 'Part / SKU (optional)',
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
                        labelText: 'Qty',
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
                        labelText: 'Unit price',
                        prefixText: '\Map<String, dynamic> attachment) {
    const size = 52.0;
    final bucket = attachment['bucket']?.toString() ?? '';
    final key = attachment['key']?.toString() ?? '';

    if (bucket.isEmpty || key.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BriskersColors.expenses.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.broken_image_outlined),
      );
    }

    return FutureBuilder<String>(
      future: _api.signedAttachmentUrl(bucket, key),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: snapshot.hasError
                ? const Icon(Icons.broken_image_outlined)
                : const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snapshot.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: Center(child: Text(_error ?? 'Transaction not found.')),
      );
    }

    final income = detail['direction']?.toString() == 'income';
    final editable = detail['editable'] == true;
    final deletable = detail['deletable'] == true;
    final attachments = List<dynamic>.from(detail['attachments'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final counterparty = detail['counterparty']?.toString() ??
        (income ? 'Income' : 'Expense');
    final category = detail['category']?.toString() ?? '';
    final account = detail['account']?.toString() ?? '';
    final date = detail['date']?.toString() ?? '';
    final remarks = detail['remarks']?.toString() ?? '';
    final jobNumber = detail['job_number']?.toString().trim() ?? '';
    final jobTitle = detail['job_title']?.toString().trim() ?? '';
    final customerName =
        detail['job_customer_name']?.toString().trim() ?? '';
    final documentNumber = detail['document_number']?.toString().trim() ?? '';
    final contextLine = <String>[
      if (customerName.isNotEmpty) customerName,
      if (jobNumber.isNotEmpty || jobTitle.isNotEmpty)
        <String>[
          if (jobNumber.isNotEmpty) jobNumber,
          if (jobTitle.isNotEmpty) jobTitle,
        ].join(' — '),
      if (documentNumber.isNotEmpty) 'Invoice #$documentNumber',
    ].join(' • ');
    final recurring = detail['recurring_rule'];
    final color =
        income ? const Color(0xFF169B62) : BriskersColors.expenses;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color.withValues(alpha: 0.10),
        title: Text(income ? 'Income' : 'Expense'),
        actions: [
          if (editable)
            PopupMenuButton<String>(
              onSelected: _handleMenu,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit transaction'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.copy_outlined),
                    title: Text('Copy transaction'),
                  ),
                ),
                if (deletable)
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete transaction'),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(
                      income ? Icons.south_west : Icons.north_east,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      counterparty,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${income ? '+' : '-'}${_money(detail['amount'])}',
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (contextLine.isNotEmpty) ...[
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text(
                  'Linked to',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(contextLine),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (remarks.isNotEmpty) ...[
            Text(
              'Description / notes',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(remarks),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _DetailRow(label: 'Category', value: category),
          _DetailRow(label: 'Account', value: account),
          _DetailRow(label: 'Date', value: date),
          if (jobNumber.isNotEmpty)
            _DetailRow(label: 'Job', value: jobNumber),
          if (documentNumber.isNotEmpty)
            _DetailRow(label: 'Invoice', value: documentNumber),
          if (recurring is Map)
            _DetailRow(
              label: 'Repeating',
              value: <String>[
                recurring['frequency']?.toString() ?? '',
                if ((recurring['next_date']?.toString() ?? '').isNotEmpty)
                  'next ${recurring['next_date']}',
              ].where((x) => x.isNotEmpty).join(' • '),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Receipts',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (editable)
                TextButton.icon(
                  onPressed: _uploading ? null : _addReceipt,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(_uploading ? 'Uploading...' : 'Add'),
                ),
            ],
          ),
          if (attachments.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No receipt photos attached.'),
              ),
            )
          else
            ...attachments.map(
              (attachment) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _openAttachment(attachment),
                        child: _receiptThumbnail(attachment),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'View receipt',
                        onPressed: () => _openAttachment(attachment),
                        icon: const Icon(Icons.zoom_in),
                      ),
                      if (editable)
                        IconButton(
                          tooltip: 'Replace receipt photo',
                          onPressed: _uploading
                              ? null
                              : () => _replaceReceipt(attachment),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      if (editable)
                        IconButton(
                          tooltip: 'Delete receipt photo',
                          onPressed:
                              _deletingAttachmentId ==
                                      attachment['attachment_id']?.toString()
                                  ? null
                                  : () => _deleteAttachment(attachment),
                          icon: _deletingAttachmentId ==
                                  attachment['attachment_id']?.toString()
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: totalAmount,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Item total',
                        prefixText: '\Map<String, dynamic> attachment) {
    const size = 52.0;
    final bucket = attachment['bucket']?.toString() ?? '';
    final key = attachment['key']?.toString() ?? '';

    if (bucket.isEmpty || key.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BriskersColors.expenses.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.broken_image_outlined),
      );
    }

    return FutureBuilder<String>(
      future: _api.signedAttachmentUrl(bucket, key),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: snapshot.hasError
                ? const Icon(Icons.broken_image_outlined)
                : const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snapshot.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: Center(child: Text(_error ?? 'Transaction not found.')),
      );
    }

    final income = detail['direction']?.toString() == 'income';
    final editable = detail['editable'] == true;
    final deletable = detail['deletable'] == true;
    final attachments = List<dynamic>.from(detail['attachments'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final counterparty = detail['counterparty']?.toString() ??
        (income ? 'Income' : 'Expense');
    final category = detail['category']?.toString() ?? '';
    final account = detail['account']?.toString() ?? '';
    final date = detail['date']?.toString() ?? '';
    final remarks = detail['remarks']?.toString() ?? '';
    final jobNumber = detail['job_number']?.toString().trim() ?? '';
    final jobTitle = detail['job_title']?.toString().trim() ?? '';
    final customerName =
        detail['job_customer_name']?.toString().trim() ?? '';
    final documentNumber = detail['document_number']?.toString().trim() ?? '';
    final contextLine = <String>[
      if (customerName.isNotEmpty) customerName,
      if (jobNumber.isNotEmpty || jobTitle.isNotEmpty)
        <String>[
          if (jobNumber.isNotEmpty) jobNumber,
          if (jobTitle.isNotEmpty) jobTitle,
        ].join(' — '),
      if (documentNumber.isNotEmpty) 'Invoice #$documentNumber',
    ].join(' • ');
    final recurring = detail['recurring_rule'];
    final color =
        income ? const Color(0xFF169B62) : BriskersColors.expenses;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color.withValues(alpha: 0.10),
        title: Text(income ? 'Income' : 'Expense'),
        actions: [
          if (editable)
            PopupMenuButton<String>(
              onSelected: _handleMenu,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit transaction'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.copy_outlined),
                    title: Text('Copy transaction'),
                  ),
                ),
                if (deletable)
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete transaction'),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(
                      income ? Icons.south_west : Icons.north_east,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      counterparty,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${income ? '+' : '-'}${_money(detail['amount'])}',
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (contextLine.isNotEmpty) ...[
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text(
                  'Linked to',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(contextLine),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (remarks.isNotEmpty) ...[
            Text(
              'Description / notes',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(remarks),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _DetailRow(label: 'Category', value: category),
          _DetailRow(label: 'Account', value: account),
          _DetailRow(label: 'Date', value: date),
          if (jobNumber.isNotEmpty)
            _DetailRow(label: 'Job', value: jobNumber),
          if (documentNumber.isNotEmpty)
            _DetailRow(label: 'Invoice', value: documentNumber),
          if (recurring is Map)
            _DetailRow(
              label: 'Repeating',
              value: <String>[
                recurring['frequency']?.toString() ?? '',
                if ((recurring['next_date']?.toString() ?? '').isNotEmpty)
                  'next ${recurring['next_date']}',
              ].where((x) => x.isNotEmpty).join(' • '),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Receipts',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (editable)
                TextButton.icon(
                  onPressed: _uploading ? null : _addReceipt,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(_uploading ? 'Uploading...' : 'Add'),
                ),
            ],
          ),
          if (attachments.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No receipt photos attached.'),
              ),
            )
          else
            ...attachments.map(
              (attachment) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _openAttachment(attachment),
                        child: _receiptThumbnail(attachment),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'View receipt',
                        onPressed: () => _openAttachment(attachment),
                        icon: const Icon(Icons.zoom_in),
                      ),
                      if (editable)
                        IconButton(
                          tooltip: 'Replace receipt photo',
                          onPressed: _uploading
                              ? null
                              : () => _replaceReceipt(attachment),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      if (editable)
                        IconButton(
                          tooltip: 'Delete receipt photo',
                          onPressed:
                              _deletingAttachmentId ==
                                      attachment['attachment_id']?.toString()
                                  ? null
                                  : () => _deleteAttachment(attachment),
                          icon: _deletingAttachmentId ==
                                  attachment['attachment_id']?.toString()
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
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

    final descriptionValue = description.text.trim();
    final skuValue = sku.text.trim();
    final quantityValue = num.tryParse(quantity.text.trim());
    final unitPriceValue = num.tryParse(unitPrice.text.trim());
    final totalAmountValue =
        num.tryParse(totalAmount.text.trim());

    description.dispose();
    sku.dispose();
    quantity.dispose();
    unitPrice.dispose();
    totalAmount.dispose();

    if (saved != true || descriptionValue.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await _api.saveExpenseReceiptItem(
        widget.businessId,
        widget.transactionId,
        itemId: item?['id']?.toString(),
        expectedRowVersion: int.tryParse(
          item?['row_version']?.toString() ?? '',
        ),
        description: descriptionValue,
        sku: skuValue.isEmpty ? null : skuValue,
        quantity: quantityValue,
        unitPrice: unitPriceValue,
        totalAmount: totalAmountValue,
      );
      final rawReceipt = response['receipt'];
      if (mounted && rawReceipt is Map) {
        setState(() {
          _receiptStructure =
              Map<String, dynamic>.from(rawReceipt);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteReceiptItem(
    Map<String, dynamic> item,
  ) async {
    if (!_canDeleteRecords || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete receipt item?'),
        content: Text(
          'Delete "${item['description'] ?? 'this item'}" from the structured receipt details?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.deleteExpenseReceiptItem(
        widget.businessId,
        widget.transactionId,
        item['id'].toString(),
      );
      final updated = await _api.expenseReceiptStructure(
        widget.businessId,
        widget.transactionId,
      );
      if (mounted) {
        setState(() => _receiptStructure = updated);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _receiptThumbnail(Map<String, dynamic> attachment) {
    const size = 52.0;
    final bucket = attachment['bucket']?.toString() ?? '';
    final key = attachment['key']?.toString() ?? '';

    if (bucket.isEmpty || key.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BriskersColors.expenses.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.broken_image_outlined),
      );
    }

    return FutureBuilder<String>(
      future: _api.signedAttachmentUrl(bucket, key),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: snapshot.hasError
                ? const Icon(Icons.broken_image_outlined)
                : const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snapshot.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: Center(child: Text(_error ?? 'Transaction not found.')),
      );
    }

    final income = detail['direction']?.toString() == 'income';
    final editable = detail['editable'] == true;
    final deletable = detail['deletable'] == true;
    final attachments = List<dynamic>.from(detail['attachments'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final counterparty = detail['counterparty']?.toString() ??
        (income ? 'Income' : 'Expense');
    final category = detail['category']?.toString() ?? '';
    final account = detail['account']?.toString() ?? '';
    final date = detail['date']?.toString() ?? '';
    final remarks = detail['remarks']?.toString() ?? '';
    final jobNumber = detail['job_number']?.toString().trim() ?? '';
    final jobTitle = detail['job_title']?.toString().trim() ?? '';
    final customerName =
        detail['job_customer_name']?.toString().trim() ?? '';
    final documentNumber = detail['document_number']?.toString().trim() ?? '';
    final contextLine = <String>[
      if (customerName.isNotEmpty) customerName,
      if (jobNumber.isNotEmpty || jobTitle.isNotEmpty)
        <String>[
          if (jobNumber.isNotEmpty) jobNumber,
          if (jobTitle.isNotEmpty) jobTitle,
        ].join(' — '),
      if (documentNumber.isNotEmpty) 'Invoice #$documentNumber',
    ].join(' • ');
    final recurring = detail['recurring_rule'];
    final color =
        income ? const Color(0xFF169B62) : BriskersColors.expenses;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color.withValues(alpha: 0.10),
        title: Text(income ? 'Income' : 'Expense'),
        actions: [
          if (editable)
            PopupMenuButton<String>(
              onSelected: _handleMenu,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit transaction'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.copy_outlined),
                    title: Text('Copy transaction'),
                  ),
                ),
                if (deletable)
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete transaction'),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(
                      income ? Icons.south_west : Icons.north_east,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      counterparty,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${income ? '+' : '-'}${_money(detail['amount'])}',
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (contextLine.isNotEmpty) ...[
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text(
                  'Linked to',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(contextLine),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (remarks.isNotEmpty) ...[
            Text(
              'Description / notes',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(remarks),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _DetailRow(label: 'Category', value: category),
          _DetailRow(label: 'Account', value: account),
          _DetailRow(label: 'Date', value: date),
          if (jobNumber.isNotEmpty)
            _DetailRow(label: 'Job', value: jobNumber),
          if (documentNumber.isNotEmpty)
            _DetailRow(label: 'Invoice', value: documentNumber),
          if (recurring is Map)
            _DetailRow(
              label: 'Repeating',
              value: <String>[
                recurring['frequency']?.toString() ?? '',
                if ((recurring['next_date']?.toString() ?? '').isNotEmpty)
                  'next ${recurring['next_date']}',
              ].where((x) => x.isNotEmpty).join(' • '),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Receipts',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (editable)
                TextButton.icon(
                  onPressed: _uploading ? null : _addReceipt,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(_uploading ? 'Uploading...' : 'Add'),
                ),
            ],
          ),
          if (attachments.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No receipt photos attached.'),
              ),
            )
          else
            ...attachments.map(
              (attachment) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _openAttachment(attachment),
                        child: _receiptThumbnail(attachment),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'View receipt',
                        onPressed: () => _openAttachment(attachment),
                        icon: const Icon(Icons.zoom_in),
                      ),
                      if (editable)
                        IconButton(
                          tooltip: 'Replace receipt photo',
                          onPressed: _uploading
                              ? null
                              : () => _replaceReceipt(attachment),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      if (editable)
                        IconButton(
                          tooltip: 'Delete receipt photo',
                          onPressed:
                              _deletingAttachmentId ==
                                      attachment['attachment_id']?.toString()
                                  ? null
                                  : () => _deleteAttachment(attachment),
                          icon: _deletingAttachmentId ==
                                  attachment['attachment_id']?.toString()
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
