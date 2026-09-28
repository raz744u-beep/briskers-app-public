import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class ExpenseEntryScreen extends StatefulWidget {
  const ExpenseEntryScreen({
    super.key,
    required this.businessId,
    this.jobId,
    this.documentId,
    this.contextLabel,
  });

  final String businessId;
  final String? jobId;
  final String? documentId;
  final String? contextLabel;

  @override
  State<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _ExpenseEntryScreenState extends State<ExpenseEntryScreen> {
  static const _api = BriskersApi();
  final _picker = ImagePicker();
  final _amountController = TextEditingController();
  final _vendorController = TextEditingController();
  final _remarksController = TextEditingController();

  List<Map<String, dynamic>> _accounts = const [];
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _vendors = const [];
  List<XFile> _receipts = const [];
  String? _accountId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _vendorController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _api.expenseOptions(widget.businessId);
      final accounts = List<dynamic>.from(data['accounts'] ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final categories = List<dynamic>.from(data['categories'] ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final vendors = List<dynamic>.from(data['vendors'] ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _categories = categories;
        _vendors = vendors;
        _accountId = accounts.isEmpty ? null : accounts.first['id']?.toString();
        _categoryId =
            categories.isEmpty ? null : categories.first['id']?.toString();
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

  String _categoryName(String id) {
    for (final item in _categories) {
      if (item['id']?.toString() == id) return item['name']?.toString() ?? '';
    }
    return '';
  }

  String _accountName(String id) {
    for (final item in _accounts) {
      if (item['id']?.toString() == id) return item['name']?.toString() ?? '';
    }
    return '';
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _addReceipts() async {
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

    if (source == ImageSource.gallery) {
      final files = await _picker.pickMultiImage(imageQuality: 92);
      if (files.isNotEmpty && mounted) {
        setState(() => _receipts = [..._receipts, ...files]);
      }
    } else {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (file != null && mounted) {
        setState(() => _receipts = [..._receipts, file]);
      }
    }
  }

  String _mimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = num.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid expense amount.');
      return;
    }
    if (_accountId == null || _categoryId == null) {
      setState(() => _error = 'Select an account and category.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final transactionId = await _api.createExpense(
        widget.businessId,
        accountId: _accountId!,
        categoryId: _categoryId!,
        amount: num.parse(amount.toStringAsFixed(2)),
        date: _date,
        jobId: widget.jobId,
        documentId: widget.documentId,
        vendorName: _vendorController.text.trim().isEmpty
            ? null
            : _vendorController.text.trim(),
        remarks: _remarksController.text.trim().isEmpty
            ? null
            : _remarksController.text.trim(),
      );

      for (final receipt in _receipts) {
        final bytes = await receipt.readAsBytes();
        await _api.uploadExpensePhoto(
          widget.businessId,
          transactionId,
          filename: receipt.name,
          mimeType: _mimeType(receipt.name),
          bytes: bytes,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendorNames = _vendors
        .map((item) => item['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.expenses.withValues(alpha: 0.10),
        title: const Text('Add expense'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if ((widget.contextLabel ?? '').isNotEmpty) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(
                        Icons.link_outlined,
                        color: BriskersColors.expenses,
                      ),
                      title: const Text(
                        'Linked to',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(widget.contextLabel!),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: _amountController,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '\$',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item['id']?.toString(),
                          child: Text(item['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                if (_categoryId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _categoryName(_categoryId!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  decoration: const InputDecoration(
                    labelText: 'Paid from',
                    border: OutlineInputBorder(),
                  ),
                  items: _accounts
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item['id']?.toString(),
                          child: Text(item['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _accountId = value),
                ),
                if (_accountId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _accountName(_accountId!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Autocomplete<String>(
                  optionsBuilder: (value) {
                    final query = value.text.trim().toLowerCase();
                    if (query.isEmpty) return vendorNames;
                    return vendorNames.where(
                      (name) => name.toLowerCase().contains(query),
                    );
                  },
                  onSelected: (value) => _vendorController.text = value,
                  fieldViewBuilder: (
                    context,
                    controller,
                    focusNode,
                    onFieldSubmitted,
                  ) {
                    if (controller.text != _vendorController.text) {
                      controller.text = _vendorController.text;
                    }
                    controller.addListener(() {
                      if (_vendorController.text != controller.text) {
                        _vendorController.text = controller.text;
                      }
                    });
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Payee',
                        hintText: 'Example: UPS, FedEx or Worldpac',
                        border: OutlineInputBorder(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Expense date'),
                  subtitle: Text(
                    '${_date.month}/${_date.day}/${_date.year}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _remarksController,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Description / notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _addReceipts,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                    _receipts.isEmpty
                        ? 'Add receipt photo'
                        : '${_receipts.length} receipt photo(s)',
                  ),
                ),
                if (_receipts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _receipts
                          .map(
                            (file) => Chip(
                              label: Text(
                                file.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onDeleted: _saving
                                  ? null
                                  : () => setState(
                                        () => _receipts = _receipts
                                            .where((item) => item.path != file.path)
                                            .toList(),
                                      ),
                            ),
                          )
                          .toList(),
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
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Save expense'),
                ),
              ],
            ),
    );
  }
}
