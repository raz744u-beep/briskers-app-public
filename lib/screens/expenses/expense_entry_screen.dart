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
    this.initialDirection = 'expense',
    this.editTransactionId,
    this.copyTransactionId,
    this.quickTemplate,
  });

  final String businessId;
  final String? jobId;
  final String? documentId;
  final String? contextLabel;
  final String initialDirection;
  final String? editTransactionId;
  final String? copyTransactionId;
  final Map<String, dynamic>? quickTemplate;

  @override
  State<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _ExpenseEntryScreenState extends State<ExpenseEntryScreen> {
  static const _api = BriskersApi();
  final _picker = ImagePicker();
  final _amountController = TextEditingController();
  final _counterpartyController = TextEditingController();
  final _remarksController = TextEditingController();

  List<Map<String, dynamic>> _accounts = const [];
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _counterparties = const [];
  List<Map<String, dynamic>> _quickTemplates = const [];
  List<XFile> _receipts = const [];

  String _direction = 'expense';
  String? _accountId;
  String? _categoryId;
  String? _counterpartyId;
  String? _jobId;
  String? _documentId;
  String? _contextLabel;
  DateTime _date = DateTime.now();

  bool _repeat = false;
  String _repeatPreset = 'monthly';
  DateTime _nextDate = DateTime.now().add(const Duration(days: 30));
  DateTime? _endDate;
  String? _recurringRuleId;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.editTransactionId != null;
  bool get _copying => widget.copyTransactionId != null;
  bool get _linked => _jobId != null || _documentId != null;

  @override
  void initState() {
    super.initState();
    _direction = widget.initialDirection == 'income' ? 'income' : 'expense';
    _jobId = widget.jobId;
    _documentId = widget.documentId;
    _contextLabel = widget.contextLabel;
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _counterpartyController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  DateTime _parseDate(Object? raw, {DateTime? fallback}) {
    return DateTime.tryParse(raw?.toString() ?? '') ?? fallback ?? DateTime.now();
  }

  List<Map<String, dynamic>> get _orderedCategories {
    final rows = List<Map<String, dynamic>>.from(_categories);
    rows.sort((a, b) {
      final ad = a['normal_direction']?.toString() == _direction ? 0 : 1;
      final bd = b['normal_direction']?.toString() == _direction ? 0 : 1;
      if (ad != bd) return ad.compareTo(bd);
      return (a['name']?.toString() ?? '')
          .toLowerCase()
          .compareTo((b['name']?.toString() ?? '').toLowerCase());
    });
    return rows;
  }

  Future<void> _load() async {
    try {
      final data = await _api.transactionOptions(widget.businessId);
      final accounts = List<dynamic>.from(data['accounts'] ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final categories = List<dynamic>.from(data['categories'] ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final counterparties =
          List<dynamic>.from(data['counterparties'] ?? const [])
              .map((raw) => Map<String, dynamic>.from(raw as Map))
              .toList();
      final quickTemplates =
          List<dynamic>.from(data['quick_templates'] ?? const [])
              .map((raw) => Map<String, dynamic>.from(raw as Map))
              .toList();

      Map<String, dynamic>? detail;
      final sourceId = widget.editTransactionId ?? widget.copyTransactionId;
      if (sourceId != null) {
        detail = await _api.transactionDetail(widget.businessId, sourceId);
      }

      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _categories = categories;
        _counterparties = counterparties;
        _quickTemplates = quickTemplates;

        if (detail != null) {
          _direction = detail['direction']?.toString() == 'income'
              ? 'income'
              : 'expense';
          _amountController.text = detail['amount']?.toString() ?? '';
          _remarksController.text = detail['remarks']?.toString() ?? '';
          _counterpartyController.text =
              detail['counterparty']?.toString() ?? '';
          final detailAccount = detail['account_id']?.toString();
          final detailCategory = detail['category_id']?.toString();
          final detailCounterparty = detail['counterparty_id']?.toString();
          _accountId = accounts.any((x) => x['id']?.toString() == detailAccount)
              ? detailAccount
              : null;
          _categoryId =
              categories.any((x) => x['id']?.toString() == detailCategory)
                  ? detailCategory
                  : null;
          _counterpartyId = counterparties
                  .any((x) => x['id']?.toString() == detailCounterparty)
              ? detailCounterparty
              : null;
          _jobId = detail['job_id']?.toString();
          if ((_jobId ?? '').isEmpty) _jobId = null;
          _documentId = detail['document_id']?.toString();
          if ((_documentId ?? '').isEmpty) _documentId = null;
          final jobNumber = detail['job_number']?.toString() ?? '';
          final documentNumber = detail['document_number']?.toString() ?? '';
          _contextLabel = <String>[
            if (jobNumber.isNotEmpty) 'Job $jobNumber',
            if (documentNumber.isNotEmpty) 'Invoice #$documentNumber',
          ].join(' • ');
          if (_contextLabel!.isEmpty) _contextLabel = null;

          if (_copying) {
            _date = DateTime.now();
            _repeat = false;
            _recurringRuleId = null;
          } else {
            _date = _parseDate(detail['date']);
            final recurring = detail['recurring_rule'];
            if (recurring is Map) {
              final rule = Map<String, dynamic>.from(recurring);
              _recurringRuleId = rule['id']?.toString();
              _repeat = rule['is_repeating'] == true;
              _nextDate = _parseDate(
                rule['next_date'],
                fallback: DateTime.now().add(const Duration(days: 30)),
              );
              final rawEnd = rule['end_date']?.toString() ?? '';
              _endDate = rawEnd.isEmpty ? null : DateTime.tryParse(rawEnd);
              final frequency = rule['frequency']?.toString() ?? 'monthly';
              final interval =
                  int.tryParse(rule['interval_count']?.toString() ?? '') ?? 1;
              if (frequency == 'weekly' && interval == 2) {
                _repeatPreset = 'biweekly';
              } else {
                _repeatPreset = frequency;
              }
            }
          }
        } else {
          _accountId = accounts.isEmpty ? null : accounts.first['id']?.toString();
          final preferred = categories.where(
            (x) => x['normal_direction']?.toString() == _direction,
          );
          _categoryId = preferred.isNotEmpty
              ? preferred.first['id']?.toString()
              : (categories.isEmpty ? null : categories.first['id']?.toString());
          if (widget.quickTemplate != null) {
            _applyQuickTemplate(widget.quickTemplate!, updateState: false);
          }
        }

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

  void _applyQuickTemplate(
    Map<String, dynamic> item, {
    bool updateState = true,
  }) {
    void apply() {
      _direction = item['direction']?.toString() == 'income'
          ? 'income'
          : 'expense';
      final account = item['account_id']?.toString();
      final category = item['category_id']?.toString();
      final vendor = item['vendor_id']?.toString();
      if (_accounts.any((x) => x['id']?.toString() == account)) {
        _accountId = account;
      }
      if (_categories.any((x) => x['id']?.toString() == category)) {
        _categoryId = category;
      }
      if (vendor != null &&
          _counterparties.any((x) => x['id']?.toString() == vendor)) {
        _counterpartyId = vendor;
        _counterpartyController.text = item['vendor']?.toString() ?? '';
      } else {
        _counterpartyId = null;
        _counterpartyController.text = item['vendor']?.toString() ?? '';
      }
      final remarks = item['remarks']?.toString() ?? '';
      if (remarks.isNotEmpty) _remarksController.text = remarks;
    }

    if (updateState) {
      setState(apply);
    } else {
      apply();
    }
  }

  Future<void> _chooseQuickTemplate() async {
    if (_quickTemplates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No quick transactions are defined yet. Add them in Settings.'),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Quick transactions',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ..._quickTemplates.map(
              (item) => ListTile(
                leading: Icon(
                  item['direction']?.toString() == 'income'
                      ? Icons.south_west
                      : Icons.north_east,
                ),
                title: Text(item['name']?.toString() ?? ''),
                subtitle: Text(
                  <String>[
                    if ((item['vendor']?.toString() ?? '').isNotEmpty)
                      item['vendor'].toString(),
                    if ((item['category']?.toString() ?? '').isNotEmpty)
                      item['category'].toString(),
                    if ((item['account']?.toString() ?? '').isNotEmpty)
                      item['account'].toString(),
                  ].join(' • '),
                ),
                onTap: () => Navigator.pop(sheetContext, item),
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null && mounted) _applyQuickTemplate(selected);
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _pickNextDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _nextDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null && mounted) setState(() => _nextDate = value);
  }

  Future<void> _pickEndDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _nextDate.add(const Duration(days: 365)),
      firstDate: _nextDate,
      lastDate: DateTime.now().add(const Duration(days: 7300)),
    );
    if (value != null && mounted) setState(() => _endDate = value);
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

  (String, int) get _repeatParts {
    switch (_repeatPreset) {
      case 'daily':
        return ('daily', 1);
      case 'weekly':
        return ('weekly', 1);
      case 'biweekly':
        return ('weekly', 2);
      case 'yearly':
        return ('yearly', 1);
      default:
        return ('monthly', 1);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = num.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
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
      final rounded = num.parse(amount.toStringAsFixed(2));
      final counterpartyName = _counterpartyController.text.trim();
      String transactionId;

      if (_editing) {
        transactionId = widget.editTransactionId!;
        await _api.updateManualTransaction(
          widget.businessId,
          transactionId,
          direction: _direction,
          accountId: _accountId!,
          categoryId: _categoryId!,
          amount: rounded,
          date: _date,
          jobId: _jobId,
          documentId: _documentId,
          counterpartyId: _counterpartyId,
          counterpartyName:
              counterpartyName.isEmpty ? null : counterpartyName,
          remarks: _remarksController.text.trim().isEmpty
              ? null
              : _remarksController.text.trim(),
        );
      } else {
        transactionId = await _api.createManualTransaction(
          widget.businessId,
          direction: _direction,
          accountId: _accountId!,
          categoryId: _categoryId!,
          amount: rounded,
          date: _date,
          jobId: _jobId,
          documentId: _documentId,
          counterpartyId: _counterpartyId,
          counterpartyName:
              counterpartyName.isEmpty ? null : counterpartyName,
          remarks: _remarksController.text.trim().isEmpty
              ? null
              : _remarksController.text.trim(),
        );
      }

      for (final receipt in _receipts) {
        await _api.uploadExpensePhoto(
          widget.businessId,
          transactionId,
          filename: receipt.name,
          mimeType: _mimeType(receipt.name),
          bytes: await receipt.readAsBytes(),
        );
      }

      if (!_linked && !_copying) {
        if (_repeat) {
          var recurringVendorId = _counterpartyId;
          if (recurringVendorId == null && counterpartyName.isNotEmpty) {
            final refreshed = await _api.transactionDetail(
              widget.businessId,
              transactionId,
            );
            recurringVendorId = refreshed['counterparty_id']?.toString();
          }
          final repeatParts = _repeatParts;
          _recurringRuleId = await _api.saveRecurringTransaction(
            widget.businessId,
            ruleId: _recurringRuleId,
            sourceTransactionId: transactionId,
            direction: _direction,
            vendorId: recurringVendorId,
            accountId: _accountId!,
            categoryId: _categoryId!,
            amount: rounded,
            remarks: _remarksController.text.trim().isEmpty
                ? null
                : _remarksController.text.trim(),
            frequency: repeatParts.$1,
            intervalCount: repeatParts.$2,
            nextDate: _nextDate,
            endDate: _endDate,
          );
        } else if (_recurringRuleId != null) {
          await _api.stopRecurringTransaction(
            widget.businessId,
            _recurringRuleId!,
          );
        }
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
    final counterpartyNames = _counterparties
        .map((item) => item['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    final title = _editing
        ? 'Edit transaction'
        : _copying
            ? 'Copy transaction'
            : _direction == 'income'
                ? 'Add income'
                : 'Add expense';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.expenses.withValues(alpha: 0.10),
        title: Text(title),
        actions: [
          if (!_editing)
            IconButton(
              tooltip: 'Quick transaction',
              onPressed: _saving ? null : _chooseQuickTemplate,
              icon: const Icon(Icons.bolt_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if ((_contextLabel ?? '').isNotEmpty) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(
                        Icons.link_outlined,
                        color: BriskersColors.expenses,
                      ),
                      title: const Text(
                        'Linked automatically',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(_contextLabel!),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'expense',
                      label: Text('Expense'),
                      icon: Icon(Icons.north_east),
                    ),
                    ButtonSegment<String>(
                      value: 'income',
                      label: Text('Income'),
                      icon: Icon(Icons.south_west),
                    ),
                  ],
                  selected: {_direction},
                  onSelectionChanged: _saving
                      ? null
                      : (value) => setState(() {
                            _direction = value.first;
                            final preferred = _orderedCategories.where(
                              (x) =>
                                  x['normal_direction']?.toString() == _direction,
                            );
                            if (preferred.isNotEmpty) {
                              _categoryId = preferred.first['id']?.toString();
                            }
                          }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountController,
                  autofocus: !_editing,
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
                  items: _orderedCategories
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
                  onChanged:
                      _saving ? null : (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  decoration: InputDecoration(
                    labelText: _direction == 'income' ? 'Deposited to' : 'Paid from',
                    border: const OutlineInputBorder(),
                  ),
                  items: _accounts
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item['id']?.toString(),
                          child: Text(item['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged:
                      _saving ? null : (value) => setState(() => _accountId = value),
                ),
                const SizedBox(height: 12),
                Autocomplete<String>(
                  optionsBuilder: (value) {
                    final query = value.text.trim().toLowerCase();
                    if (query.isEmpty) return counterpartyNames;
                    return counterpartyNames.where(
                      (name) => name.toLowerCase().contains(query),
                    );
                  },
                  onSelected: (value) {
                    _counterpartyController.text = value;
                    for (final item in _counterparties) {
                      if (item['name']?.toString() == value) {
                        _counterpartyId = item['id']?.toString();
                        break;
                      }
                    }
                  },
                  fieldViewBuilder: (
                    context,
                    controller,
                    focusNode,
                    onFieldSubmitted,
                  ) {
                    if (controller.text != _counterpartyController.text) {
                      controller.text = _counterpartyController.text;
                      controller.selection = TextSelection.collapsed(
                        offset: controller.text.length,
                      );
                    }
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        _counterpartyController.text = value;
                        _counterpartyId = null;
                      },
                      decoration: InputDecoration(
                        labelText: _direction == 'income' ? 'Payer' : 'Payee',
                        hintText: 'Example: Worldpac, FedEx or Entergy',
                        border: const OutlineInputBorder(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Transaction date'),
                  subtitle: Text('${_date.month}/${_date.day}/${_date.year}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _saving ? null : _pickDate,
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
                        : '${_receipts.length} new receipt photo(s)',
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
                if (!_linked && !_copying) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Repeat transaction'),
                    subtitle: const Text(
                      'Repeating transactions also appear in the Recurring Transactions list.',
                    ),
                    value: _repeat,
                    onChanged:
                        _saving ? null : (value) => setState(() => _repeat = value),
                  ),
                  if (_repeat) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _repeatPreset,
                      decoration: const InputDecoration(
                        labelText: 'Repeat',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'daily', child: Text('Daily')),
                        DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                        DropdownMenuItem(
                          value: 'biweekly',
                          child: Text('Every 2 weeks'),
                        ),
                        DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                        DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _repeatPreset = value);
                              }
                            },
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: const Icon(Icons.event_repeat_outlined),
                      title: const Text('Next transaction'),
                      subtitle: Text(
                        '${_nextDate.month}/${_nextDate.day}/${_nextDate.year}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _saving ? null : _pickNextDate,
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: const Icon(Icons.event_busy_outlined),
                      title: const Text('End date'),
                      subtitle: Text(
                        _endDate == null
                            ? 'No end date'
                            : '${_endDate!.month}/${_endDate!.day}/${_endDate!.year}',
                      ),
                      trailing: _endDate == null
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              tooltip: 'No end date',
                              onPressed:
                                  _saving ? null : () => setState(() => _endDate = null),
                              icon: const Icon(Icons.close),
                            ),
                      onTap: _saving ? null : _pickEndDate,
                    ),
                  ],
                ],
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
                  label: Text(_saving ? 'Saving...' : 'Save transaction'),
                ),
              ],
            ),
    );
  }
}
