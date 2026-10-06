import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/connection_mode.dart';
import '../services/briskers_api.dart';
import '../services/local_attachment_cache.dart';
import '../services/local_financial_cache.dart';
import '../widgets/briskers_page_header.dart';
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
  final LocalFinancialCache _localFinancial = LocalFinancialCache();
  final LocalAttachmentCache _attachmentCache = LocalAttachmentCache();

  static const int _pageSize = 50;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _transactions = const [];
  List<Map<String, dynamic>> _quickTemplates = const [];
  List<Map<String, dynamic>> _accounts = const [];
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _counterparties = const [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _importing = false;
  int _importDone = 0;
  int _importTotal = 0;
  String _filter = 'all';
  String _dateRange = '30d';
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String? _accountFilterId;
  String? _categoryFilterId;
  String? _counterpartyFilterId;
  Timer? _searchDebounce;
  String? _error;
  bool _showingLocal = false;

  bool get _owner => widget.roleCode == 'owner';
  bool get _showFinancialSummary =>
      widget.roleCode == 'owner' || widget.roleCode == 'manager';
  bool get _allowRecurring =>
      widget.roleCode == 'owner' || widget.roleCode == 'manager';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 500) {
      _loadMore();
    }
  }

  String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(value);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime? get _rangeStartDate {
    if (_searchController.text.trim().isNotEmpty) return null;
    final today = _dateOnly(DateTime.now());
    switch (_dateRange) {
      case '30d':
        return today.subtract(const Duration(days: 29));
      case '60d':
        return today.subtract(const Duration(days: 59));
      case '90d':
        return today.subtract(const Duration(days: 89));
      case '6m':
        return DateTime(today.year, today.month - 6, today.day);
      case '1y':
        return DateTime(today.year - 1, today.month, today.day);
      case 'custom':
        return _customStartDate;
      case 'all':
      default:
        return null;
    }
  }

  DateTime? get _rangeEndDate {
    if (_searchController.text.trim().isNotEmpty) return null;
    if (_dateRange == 'all') return null;
    if (_dateRange == 'custom') return _customEndDate;
    return _dateOnly(DateTime.now());
  }

  String get _rangeLabel {
    switch (_dateRange) {
      case '30d':
        return '30 days';
      case '60d':
        return '60 days';
      case '90d':
        return '90 days';
      case '6m':
        return '6 months';
      case '1y':
        return '1 year';
      case 'custom':
        if (_customStartDate != null && _customEndDate != null) {
          final start = DateFormat('MMM d').format(_customStartDate!);
          final end = DateFormat('MMM d').format(_customEndDate!);
          return '$start–$end';
        }
        return 'Custom';
      case 'all':
      default:
        return 'All history';
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTransactions({
    required int offset,
  }) {
    return _api.transactionsPaged(
      widget.businessId,
      limit: _pageSize,
      offset: offset,
      startDate: _rangeStartDate,
      endDate: _rangeEndDate,
      search: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
      direction: _filter == 'all' ? null : _filter,
      accountId: _accountFilterId,
      categoryId: _categoryFilterId,
      counterpartyId: _counterpartyFilterId,
    );
  }

  Future<void> _prefetchReceiptDetails(
    List<Map<String, dynamic>> snapshot,
  ) async {
    final rows = snapshot.where((row) {
      final count =
          int.tryParse(row['receipt_count']?.toString() ?? '') ?? 0;
      return count > 0 && (row['id']?.toString() ?? '').isNotEmpty;
    }).toList();

    for (var index = 0; index < rows.length; index += 3) {
      final batch = rows.skip(index).take(3).map((row) async {
        final id = row['id'].toString();
        try {
          final detail = await _api.transactionDetail(
            widget.businessId,
            id,
          );
          await _localFinancial.saveTransactionDetail(
            widget.businessId,
            id,
            detail,
          );
          final attachments = List<dynamic>.from(
            detail['attachments'] ?? const [],
          ).whereType<Map>().map((raw) {
            return Map<String, dynamic>.from(raw);
          }).toList();

          for (final attachment in attachments) {
            final bucket = attachment['bucket']?.toString() ??
                'briskers-private';
            final key = attachment['key']?.toString() ?? '';
            if (key.isEmpty) continue;
            await _attachmentCache.getOrDownload(bucket, key);
          }
        } catch (_) {
          // Keep the transaction list usable if an individual receipt fails.
        }
      });
      await Future.wait(batch);
    }
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }

    final forceOnline =
        BriskersConnectionModeController.instance.forceOnline;

    if (!forceOnline) {
      try {
        final localRows = await _localFinancial.loadTransactions(
          widget.businessId,
          startDate: _rangeStartDate,
          endDate: _rangeEndDate,
          search: _searchController.text.trim().isEmpty
              ? null
              : _searchController.text.trim(),
          direction: _filter == 'all' ? null : _filter,
          accountId: _accountFilterId,
          categoryId: _categoryFilterId,
          counterpartyId: _counterpartyFilterId,
        );
        final localOptions =
            await _localFinancial.loadOptions(widget.businessId);

        if (mounted && (localRows.isNotEmpty || localOptions.isNotEmpty)) {
          setState(() {
            _transactions = localRows.take(_pageSize).toList();
            _hasMore = localRows.length > _pageSize;
            _quickTemplates = List<dynamic>.from(
              localOptions['quick_templates'] ?? const [],
            ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
            _accounts = List<dynamic>.from(
              localOptions['accounts'] ?? const [],
            ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
            _categories = List<dynamic>.from(
              localOptions['categories'] ?? const [],
            ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
            _counterparties = List<dynamic>.from(
              localOptions['counterparties'] ?? const [],
            ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
            _loading = false;
            _showingLocal = true;
            _error = null;
          });
        }
      } catch (_) {
        // Online load can still succeed if the local cache is unavailable.
      }
    }

    if (BriskersConnectionModeController.instance.forceOffline) {
      if (mounted && !_showingLocal) {
        setState(() {
          _transactions = const [];
          _hasMore = false;
          _loading = false;
          _error = null;
          _showingLocal = true;
        });
      }
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        _fetchTransactions(offset: 0),
        _api.transactionOptions(widget.businessId),
        _api.transactions(widget.businessId, limit: 1000),
      ]);
      final rows = List<Map<String, dynamic>>.from(results[0] as List);
      final options = Map<String, dynamic>.from(results[1] as Map);
      final snapshot =
          List<Map<String, dynamic>>.from(results[2] as List);

      await _localFinancial.saveTransactions(
        widget.businessId,
        snapshot,
      );
      await _localFinancial.saveOptions(widget.businessId, options);
      unawaited(_prefetchReceiptDetails(snapshot));

      if (!mounted) return;
      setState(() {
        _transactions = rows;
        _hasMore = rows.length == _pageSize;
        _quickTemplates = List<dynamic>.from(
          options['quick_templates'] ?? const [],
        ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
        _accounts = List<dynamic>.from(
          options['accounts'] ?? const [],
        ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
        _categories = List<dynamic>.from(
          options['categories'] ?? const [],
        ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
        _counterparties = List<dynamic>.from(
          options['counterparties'] ?? const [],
        ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
        _loading = false;
        _showingLocal = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      final forceOffline =
          BriskersConnectionModeController.instance.forceOffline;
      setState(() {
        _loading = false;
        if (_showingLocal || forceOffline) {
          _error = null;
        } else {
          _error = error.toString();
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_showingLocal ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final rows = await _fetchTransactions(offset: _transactions.length);
      if (!mounted) return;
      setState(() {
        _transactions = [..._transactions, ...rows];
        _hasMore = rows.length == _pageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  void _searchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () {
        if (mounted) _load(showLoading: false);
      },
    );
  }

  Future<void> _chooseDirection() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const [
              ('all', 'All'),
              ('expense', 'Expenses'),
              ('income', 'Income'),
            ])
              ListTile(
                title: Text(option.$2),
                trailing: _filter == option.$1
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(sheetContext, option.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || selected == _filter) return;
    setState(() => _filter = selected);
    await _load();
  }

  Future<void> _chooseDateRange() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Select date range',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            for (final option in const [
              ('30d', 'Last 30 days'),
              ('60d', 'Last 60 days'),
              ('90d', 'Last 90 days'),
              ('6m', 'Last 6 months'),
              ('1y', 'Last 1 year'),
              ('custom', 'Custom date range'),
              ('all', 'All history'),
            ])
              ListTile(
                title: Text(option.$2),
                trailing: _dateRange == option.$1
                    ? const Icon(
                        Icons.check,
                        color: BriskersColors.invoices,
                      )
                    : option.$1 == 'custom'
                        ? const Icon(Icons.chevron_right)
                        : null,
                onTap: () => Navigator.pop(sheetContext, option.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null) return;

    if (selected == 'custom') {
      if (!mounted) return;
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 10),
        lastDate: now,
        initialDateRange: _customStartDate != null && _customEndDate != null
            ? DateTimeRange(
                start: _customStartDate!,
                end: _customEndDate!,
              )
            : DateTimeRange(
                start: now.subtract(const Duration(days: 30)),
                end: now,
              ),
      );
      if (picked == null) return;
      _customStartDate = _dateOnly(picked.start);
      _customEndDate = _dateOnly(picked.end);
    }

    if (!mounted) return;
    setState(() => _dateRange = selected);
    await _load();
  }

  Future<void> _showAdvancedFilters() async {
    var accountId = _accountFilterId;
    var categoryId = _categoryFilterId;
    var counterpartyId = _counterpartyFilterId;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Transaction filters',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: accountId,
                  decoration: const InputDecoration(
                    labelText: 'Account',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All accounts'),
                    ),
                    ..._accounts.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item['id']?.toString(),
                        child: Text(item['name']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => accountId = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All categories'),
                    ),
                    ..._categories.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item['id']?.toString(),
                        child: Text(item['name']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => categoryId = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: counterpartyId,
                  decoration: const InputDecoration(
                    labelText: 'Payee',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All payees'),
                    ),
                    ..._counterparties.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item['id']?.toString(),
                        child: Text(item['name']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => counterpartyId = value),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setSheetState(() {
                            accountId = null;
                            categoryId = null;
                            counterpartyId = null;
                          });
                        },
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: BriskersColors.invoices,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () =>
                            Navigator.pop(sheetContext, true),
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (applied != true) return;
    setState(() {
      _accountFilterId = accountId;
      _categoryFilterId = categoryId;
      _counterpartyFilterId = counterpartyId;
    });
    await _load();
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
          allowRecurring: _allowRecurring,
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
          allowRecurring: _allowRecurring,
          canDeleteTransaction: widget.roleCode == 'owner',
          cachedDetail: _showingLocal
              ? Map<String, dynamic>.from(transaction)
              : null,
        ),
      ),
    );
    await _load();
  }

  Future<void> _editTransactionFromList(String transactionId) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          editTransactionId: transactionId,
          allowRecurring: _allowRecurring,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _copyTransactionFromList(String transactionId) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          copyTransactionId: transactionId,
          allowRecurring: _allowRecurring,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _deleteTransactionFromList(String transactionId) async {
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
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      await _api.voidManualTransaction(widget.businessId, transactionId);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _showTransactionActions(
    Map<String, dynamic> transaction,
  ) async {
    final id = transaction['id']?.toString() ?? '';
    if (id.isEmpty) return;

    Map<String, dynamic> detail;
    try {
      detail = await _api.transactionDetail(widget.businessId, id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (!mounted) return;

    final editable = detail['editable'] == true;
    final deletable = _owner && detail['deletable'] == true;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('View transaction'),
              onTap: () => Navigator.pop(sheetContext, 'view'),
            ),
            if (editable)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit transaction'),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
            if (editable)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy transaction'),
                onTap: () => Navigator.pop(sheetContext, 'copy'),
              ),
            if (deletable) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                ),
                title: const Text(
                  'Delete transaction',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'view') await _openTransaction(transaction);
    if (action == 'edit') await _editTransactionFromList(id);
    if (action == 'copy') await _copyTransactionFromList(id);
    if (action == 'delete') await _deleteTransactionFromList(id);
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

    final visible = _transactions;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: const Color(0xFFC62828).withValues(alpha: 0.08),
        title: BriskersPageTitle(
          title: tr('expensesIncome'),
          logoHeight: 40,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importing || _showingLocal ? null : _showAddMenu,
        backgroundColor: BriskersColors.expenses,
        foregroundColor: Colors.white,
        tooltip: 'Add transaction',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                children: [
                  if (_showingLocal)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: BriskersColors.expenses.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.cloud_off_outlined, size: 18),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'Showing saved transactions • reconnect to refresh, add or edit',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_showFinancialSummary)
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
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
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
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    _money(expenses),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFC62828),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_allowRecurring) ...[
                    const SizedBox(height: 10),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ExpansionTile(
                        leading: const Icon(
                          Icons.event_repeat_outlined,
                          color: BriskersColors.expenses,
                        ),
                        title: Text(
                          tr('recurringTransactions'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        children: [
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'View and edit only transactions set to repeat.',
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
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
                              icon: const Icon(Icons.open_in_new),
                              label: Text(tr('recurringTransactions')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_owner && Platform.isAndroid) ...[
                    const SizedBox(height: 10),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ExpansionTile(
                        leading: const Icon(
                          Icons.photo_library_outlined,
                          color: BriskersColors.expenses,
                        ),
                        title: const Text(
                          'Import Expense IQ receipt photos',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _importing
                                  ? 'Importing $_importDone of $_importTotal...'
                                  : '/storage/emulated/0/ExpenseIQ/photos',
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _importing ? null : _importExpenseIqReceipts,
                              icon: _importing
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.file_download_outlined),
                              label: Text(
                                _importing ? 'Importing...' : 'Import photos',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Transactions',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: _chooseDirection,
                        child: Text(
                          _filter == 'all'
                              ? tr('all')
                              : _filter == 'income'
                                  ? 'Income'
                                  : tr('expenses'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _chooseDateRange,
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 17,
                        ),
                        label: Text(_rangeLabel),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Transaction filters',
                        onPressed: _showAdvancedFilters,
                        icon: Icon(
                          Icons.filter_alt_outlined,
                          color: _accountFilterId != null ||
                                  _categoryFilterId != null ||
                                  _counterpartyFilterId != null
                              ? BriskersColors.invoices
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {});
                      _searchChanged(value);
                    },
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search transactions…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchDebounce?.cancel();
                                _searchController.clear();
                                setState(() {});
                                _load(showLoading: false);
                              },
                              icon: const Icon(Icons.close),
                            ),
                      filled: true,
                      fillColor: const Color(0xFFF1F2F7),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(32), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(32), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(32), borderSide: BorderSide.none),
                      isDense: true,
                    ),
                  ),
                  if (_searchController.text.trim().isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 5, left: 4),
                      child: Text(
                        'Search checks all transaction history.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF667085),
                        ),
                      ),
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
                      final jobTitle =
                          transaction['job_title']?.toString().trim() ?? '';
                      final customerName =
                          transaction['job_customer_name']?.toString().trim() ?? '';
                      final documentNumber =
                          transaction['document_number']?.toString().trim() ?? '';
                      final remarks =
                          transaction['remarks']?.toString().trim() ?? '';
                      final contextLine = <String>[
                        if (customerName.isNotEmpty) customerName,
                        if (jobNumber.isNotEmpty || jobTitle.isNotEmpty)
                          <String>[
                            if (jobNumber.isNotEmpty) jobNumber,
                            if (jobTitle.isNotEmpty) jobTitle,
                          ].join(' — '),
                        if (documentNumber.isNotEmpty)
                          'Invoice #$documentNumber',
                      ].join(' • ');
                      final receiptCount = int.tryParse(
                            transaction['receipt_count']?.toString() ?? '',
                          ) ??
                          0;
                      final directionColor = incomeRow
                          ? const Color(0xFF169B62)
                          : const Color(0xFFC62828);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _openTransaction(transaction),
                          onLongPress: _showingLocal
                              ? null
                              : () => _showTransactionActions(transaction),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor:
                                      directionColor.withValues(alpha: 0.10),
                                  child: Icon(
                                    incomeRow
                                        ? Icons.south_west
                                        : Icons.north_east,
                                    color: directionColor,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        counterparty,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      if (contextLine.isNotEmpty)
                                        Text(
                                          contextLine,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      Text(
                                        remarks.isEmpty
                                            ? <String>[
                                                if (category.isNotEmpty)
                                                  category,
                                                if (date.isNotEmpty) date,
                                              ].join(' • ')
                                            : remarks,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${incomeRow ? '+' : '-'}${_money(transaction['amount'])}',
                                      style: TextStyle(
                                        fontSize: 17.5,
                                        fontWeight: FontWeight.w900,
                                        color: directionColor,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (receiptCount > 0) ...[
                                          Icon(
                                            Icons.photo_outlined,
                                            size: 17,
                                            color: directionColor,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            '$receiptCount',
                                            style: TextStyle(
                                              color: directionColor,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        const Icon(
                                          Icons.chevron_right,
                                          size: 21,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  if (_loadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (!_hasMore && visible.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text(
                          'No more transactions',
                          style: TextStyle(
                            color: Color(0xFF667085),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
