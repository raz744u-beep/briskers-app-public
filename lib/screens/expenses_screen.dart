import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../services/briskers_api.dart';
import 'expenses/expense_detail_screen.dart';
import 'expenses/expense_entry_screen.dart';
import 'settings/expense_settings_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
  });

  final String businessId;
  final String roleCode;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  static const _api = BriskersApi();
  static const _expenseIqChannel = MethodChannel('com.briskers/expenseiq');

  List<Map<String, dynamic>> _transactions = const [];
  List<Map<String, dynamic>> _quickTemplates = const [];
  bool _loading = true;
  bool _importing = false;
  int _importDone = 0;
  int _importTotal = 0;
  String _filter = 'all';
  String? _error;

  bool get _owner => widget.roleCode == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(value);
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.transactions(widget.businessId, limit: 1000),
        _api.transactionOptions(widget.businessId),
      ]);
      final rows = List<Map<String, dynamic>>.from(results[0] as List);
      final options = Map<String, dynamic>.from(results[1] as Map);
      final quick = List<dynamic>.from(options['quick_templates'] ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _transactions = rows;
        _quickTemplates = quick;
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

  Future<void> _addTransaction(
    String direction, {
    Map<String, dynamic>? quickTemplate,
  }) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          initialDirection: direction,
          quickTemplate: quickTemplate,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _chooseQuick() async {
    if (_quickTemplates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No quick transactions are defined yet. Add them in Settings.',
          ),
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
                      : Icons.bolt_outlined,
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

    if (selected != null && mounted) {
      await _addTransaction(
        selected['direction']?.toString() == 'income' ? 'income' : 'expense',
        quickTemplate: selected,
      );
    }
  }

  Future<void> _showAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.north_east),
              title: const Text('Add expense'),
              subtitle: const Text('General business expense'),
              onTap: () => Navigator.pop(sheetContext, 'expense'),
            ),
            ListTile(
              leading: const Icon(Icons.south_west),
              title: const Text('Add income'),
              subtitle: const Text('Refund, credit or other manual income'),
              onTap: () => Navigator.pop(sheetContext, 'income'),
            ),
            ListTile(
              leading: const Icon(Icons.bolt_outlined),
              title: const Text('Quick transaction'),
              subtitle: const Text('Use a saved payee/account/category preset'),
              onTap: () => Navigator.pop(sheetContext, 'quick'),
            ),
          ],
        ),
      ),
    );

    if (choice == 'expense') await _addTransaction('expense');
    if (choice == 'income') await _addTransaction('income');
    if (choice == 'quick') await _chooseQuick();
  }

  Future<void> _openTransaction(Map<String, dynamic> transaction) async {
    final id = transaction['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseDetailScreen(
          businessId: widget.businessId,
          transactionId: id,
        ),
      ),
    );
    await _load();
  }

  String _photoKey(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.jpeg')) {
      return filename.substring(0, filename.length - 5).toLowerCase();
    }
    if (lower.endsWith('.jpg')) {
      return filename.substring(0, filename.length - 4).toLowerCase();
    }
    return '';
  }

  Future<void> _importExpenseIqReceipts() async {
    if (_importing) return;

    List<Map<String, dynamic>> candidates;
    try {
      candidates =
          await _api.expenseReceiptImportCandidates(widget.businessId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No Expense IQ receipt photos are waiting to import.'),
        ),
      );
      return;
    }

    List<dynamic>? pickedFiles;
    try {
      pickedFiles = await _expenseIqChannel.invokeMethod<List<dynamic>>(
        'pickExpenseIqFolder',
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              'Android could not open the ExpenseIQ photos folder.\n$error';
        });
      }
      return;
    }
    if (pickedFiles == null || !mounted) return;

    final filesByPhotoId = <String, Map<String, dynamic>>{};
    for (final raw in pickedFiles) {
      if (raw is! Map) continue;
      final file = Map<String, dynamic>.from(raw);
      final filename = file['name']?.toString() ?? '';
      final key = _photoKey(filename);
      if (key.isNotEmpty) filesByPhotoId[key] = file;
    }

    final matches =
        <(Map<String, dynamic>, Map<String, dynamic>)>[];
    for (final candidate in candidates) {
      final photoId = candidate['photo_id']?.toString().trim().toLowerCase();
      if (photoId == null || photoId.isEmpty) continue;
      final file = filesByPhotoId[photoId];
      if (file != null) matches.add((candidate, file));
    }

    if (!mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import Expense IQ receipts?'),
        content: Text(
          'Briskers found ${matches.length} matching JPG/JPEG receipt photo(s) for ${candidates.length} expense record(s).\n\nThe photos will be copied into Briskers private storage so they will also be available on iPhone, iPad, and future phones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed:
                matches.isEmpty ? null : () => Navigator.pop(dialogContext, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() {
      _importing = true;
      _importDone = 0;
      _importTotal = matches.length;
      _error = null;
    });

    var failed = 0;
    for (final match in matches) {
      final candidate = match.$1;
      final file = match.$2;
      try {
        final filename = file['name']?.toString() ?? 'receipt.jpg';
        final uri = file['uri']?.toString() ?? '';
        if (uri.isEmpty) throw Exception('Receipt file URI is missing.');
        final bytes = await _expenseIqChannel.invokeMethod<Uint8List>(
          'readExpenseIqFile',
          {'uri': uri},
        );
        if (bytes == null) throw Exception('Could not read $filename.');
        await _api.uploadExpensePhoto(
          widget.businessId,
          candidate['transaction_id'].toString(),
          filename: filename,
          mimeType: 'image/jpeg',
          bytes: bytes,
        );
      } catch (_) {
        failed += 1;
      }
      if (mounted) setState(() => _importDone += 1);
    }

    if (!mounted) return;
    setState(() => _importing = false);
    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Imported ${matches.length} receipt photo(s).'
              : 'Imported ${matches.length - failed} receipt photo(s); $failed failed.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final income = _transactions
        .where((x) => x['direction']?.toString() == 'income')
        .fold<num>(
          0,
          (sum, item) =>
              sum + (num.tryParse(item['amount']?.toString() ?? '') ?? 0),
        );
    final expenses = _transactions
        .where((x) => x['direction']?.toString() != 'income')
        .fold<num>(
          0,
          (sum, item) =>
              sum + (num.tryParse(item['amount']?.toString() ?? '') ?? 0),
        );

    final visible = _transactions
        .where(
          (x) =>
              _filter == 'all' || x['direction']?.toString() == _filter,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.expenses.withValues(alpha: 0.10),
        title: const Text('Expenses & income'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _showAddMenu,
        backgroundColor: BriskersColors.expenses,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Transaction'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Income',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  _money(income),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF169B62),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'Expenses',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  _money(expenses),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: BriskersColors.expenses,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(
                        Icons.event_repeat_outlined,
                        color: BriskersColors.expenses,
                      ),
                      title: const Text(
                        'Recurring transactions',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'View and edit only transactions set to repeat',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RecurringTransactionsScreen(
                              businessId: widget.businessId,
                            ),
                          ),
                        );
                        await _load();
                      },
                    ),
                  ),
                  if (_owner && Platform.isAndroid) ...[
                    const SizedBox(height: 10),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(
                          Icons.photo_library_outlined,
                          color: BriskersColors.expenses,
                        ),
                        title: const Text(
                          'Import Expense IQ receipt photos',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          _importing
                              ? 'Importing $_importDone of $_importTotal...'
                              : '/storage/emulated/0/ExpenseIQ/photos',
                        ),
                        trailing: _importing
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: _importing ? null : _importExpenseIqReceipts,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('All')),
                      ButtonSegment(value: 'expense', label: Text('Expenses')),
                      ButtonSegment(value: 'income', label: Text('Income')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (value) =>
                        setState(() => _filter = value.first),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No transactions in this view.'),
                      ),
                    )
                  else
                    ...visible.map((transaction) {
                      final incomeRow =
                          transaction['direction']?.toString() == 'income';
                      final counterparty =
                          transaction['counterparty']?.toString() ??
                              (incomeRow ? 'Income' : 'Expense');
                      final category =
                          transaction['category']?.toString() ?? '';
                      final date =
                          transaction['transaction_date']?.toString() ?? '';
                      final jobNumber =
                          transaction['job_number']?.toString().trim() ?? '';
                      final documentNumber =
                          transaction['document_number']?.toString().trim() ?? '';
                      final receiptCount = int.tryParse(
                            transaction['receipt_count']?.toString() ?? '',
                          ) ??
                          0;
                      final color = incomeRow
                          ? const Color(0xFF169B62)
                          : BriskersColors.expenses;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Icon(
                              incomeRow ? Icons.south_west : Icons.north_east,
                              color: color,
                            ),
                          ),
                          title: Text(
                            counterparty,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            <String>[
                              if (category.isNotEmpty) category,
                              if (date.isNotEmpty) date,
                              if (jobNumber.isNotEmpty) 'Job $jobNumber',
                              if (documentNumber.isNotEmpty)
                                'Invoice #$documentNumber',
                            ].join(' • '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (receiptCount > 0) ...[
                                const Icon(
                                  Icons.photo_outlined,
                                  size: 18,
                                  color: BriskersColors.expenses,
                                ),
                                const SizedBox(width: 3),
                                Text('$receiptCount'),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                '${incomeRow ? '+' : '-'}${_money(transaction['amount'])}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () => _openTransaction(transaction),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
