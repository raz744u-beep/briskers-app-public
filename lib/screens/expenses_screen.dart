import '../widgets/briskers_dialog.dart';
import '../local/local_database_provider.dart';
import 'payroll/payroll_expense_review.dart';
import 'dart:async';
import '../core/navigation_content_timing.dart';
import 'dart:io';

import 'package:flutter/material.dart' hide showDialog, showModalBottomSheet;

import '../core/module_modal_theme.dart';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/connection_mode.dart';
import '../core/supabase_config.dart';
import '../services/device_owner_authorization.dart';
import '../services/briskers_api.dart';
import '../services/warranty_receipt_reporting.dart';
import '../services/local_financial_cache.dart';
import '../services/local_employee_reports.dart';
import '../services/offline_financial_write_service.dart';
import '../services/financial_history_recovery.dart';
import '../services/invoice_payment_feed.dart';
import '../services/expenses_period_totals.dart';
import '../services/expense_filter_preferences.dart';
import '../services/local_expense_subtotal.dart';
import '../services/local_transaction_search.dart';
import '../services/verified_expense_totals_cache.dart';
import '../services/local_financial_totals_journal.dart';
import '../services/expenseiq_local_photo_sync.dart';
import '../services/expenseiq_background_scheduler.dart';
import '../widgets/briskers_page_header.dart';
import 'expenses/expense_detail_screen.dart';
import 'jobs/job_document_screen.dart';
import 'expenses/expense_entry_screen.dart';
import 'settings/expense_settings_screen.dart';
import 'settings/offline_recurring_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
    this.showAppBar = true,
    this.dockResetToken = 0,
  });

  final String businessId;
  final String roleCode;
  final bool showAppBar;
  final int dockResetToken;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen>
    with ModuleModalState<ExpensesScreen>, WidgetsBindingObserver {
  @override
  Color get modalAccent => BriskersColors.expenses;
  static const _api = BriskersApi();
  static const _expenseIqChannel = MethodChannel('com.briskers/expenseiq');
  final LocalFinancialCache _localFinancial = LocalFinancialCache();
  final InvoicePaymentFeed _invoiceFeed = InvoicePaymentFeed();
  List<Map<String, dynamic>> _invoiceReceipts = const [];
  bool _recoveringCachedReceipts = false;

  static const int _pageSize = 50;
  int _visibleCount = _pageSize;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _transactions = const [];
  List<Map<String, dynamic>> _quickTemplates = const [];
  List<Map<String, dynamic>> _accounts = const [];
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _counterparties = const [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _downloadingHistory = false;
  int _downloadedHistoryCount = 0;
  String? _historyRecoveryMessage;

  bool _hasMore = true;
  bool _importing = false;
  bool _requestingPhotoSync = false;
  final ExpenseIqLocalPhotoSync _photoSync = ExpenseIqLocalPhotoSync();
  ExpenseIqSyncCounts? _photoCounts;
  Timer? _photoCountTimer;
  bool _photoCountsReading = false;
  String? _photoQueueError;
  int _indexProcessed = 0;
  int _indexExpected = 0;
  bool _restoringFilters = true;
  int _filterRestoreEpoch = 0;
  String _filter = 'all';
  String _dateRange = 'all';
  ({DateTime? start, DateTime end})? _postedHistoryCoverage;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String? _accountFilterId;
  String? _categoryFilterId;
  String? _counterpartyFilterId;
  Timer? _searchDebounce;
  String _appliedSearch = '';
  List<Map<String, dynamic>>? _offlineScopeRows;
  List<Map<String, dynamic>>? _offlineMatches;
  final _searchIndex = Expando<String>();
  Object? _combinedScope;
  List<Map<String, dynamic>> _combinedRows = const [];
  String? _error;
  bool _showingLocal = false;
  // Cache-first is normal in Auto mode; only an actual transaction-page
  // refresh failure should produce the saved-data notice.
  bool _transactionRefreshFailed = false;
  // Only a server-returned transaction ID is an affirmative cloud receipt.
  // The API currently omits sync_state: unknown must remain unknown.
  final Set<String> _serverConfirmedTransactionIds = {};
  // Recently seen server receipts survive app restarts, but only for the
  // same business, unchanged transaction fingerprint, and a bounded TTL.
  Map<String, String> _previousServerTransactionProofs = {};
  String? _serverConfirmedBusinessId;
  // A newer search, filter or module entry invalidates older network results.
  int _loadEpoch = 0;
  int _receiptEpoch = 0;
  int _periodEpoch = 0;
  ExpensesPeriodTotals? _periodTotals;
  ExpensesPeriodTotals? _serverPeriodBase;
  bool _periodCalculating = false;
  String? _periodError;
  String? _lastPeriodScope;
  DateTime? _lastPeriodAt;
  String? _pendingPeriodScope;

  bool _isCurrentReceipt(int epoch, String businessId) =>
      mounted && epoch == _receiptEpoch && widget.businessId == businessId;

  bool _isCurrentLoad(int epoch, String businessId) =>
      mounted && epoch == _loadEpoch && widget.businessId == businessId;

  bool get _owner => widget.roleCode == 'owner';
  // Financial rollups belong to Owner only. Secretary/office and
  // mechanic/foreman roles do not fetch or render confidential totals.
  bool get _showFinancialSummary => _owner;
  bool get _allowRecurring =>
      widget.roleCode == 'owner' || widget.roleCode == 'manager';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addObserver(this);
    // Allow the first Expenses frame to paint before starting database work.
    // Running multiple startup queries during initState can make navigation
    // appear unresponsive, particularly after returning from another module.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_restoreFiltersAndLoad());
      unawaited(_refreshPhotoCounts());
    });
    if (_owner && Platform.isAndroid) {
      // Photo totals are informational; avoid rebuilding the entire list
      // every four seconds while the owner is reading transactions.
      _photoCountTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) {
          // Expenses remains mounted between dock visits. Skip cosmetic
          // photo-count polling while it is hidden; sync runs elsewhere.
          if (mounted && TickerMode.valuesOf(context).enabled) {
            unawaited(_refreshPhotoCounts());
          }
        },
      );
    }
  }

  @override
  void didUpdateWidget(covariant ExpensesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.roleCode != widget.roleCode) {
      // Never reuse an Owner's financial totals or server ID proofs for a
      // different business/role. Even a transient role swap must fail closed.
      ++_loadEpoch;
      ++_receiptEpoch;
      _restoringFilters = true;
      ++_periodEpoch;
      _pendingPeriodScope = null;
      _periodTotals = null;
      _serverPeriodBase = null;
      _lastPeriodScope = null;
      _lastPeriodAt = null;
      _periodCalculating = false;
      _periodError = null;
      _payrollDisplayNames = const PayrollDisplayNames();
      _serverConfirmedTransactionIds.clear();
      _previousServerTransactionProofs = {};
      _transactionRefreshFailed = false;
      _serverConfirmedBusinessId = null;
      _postedHistoryCoverage = null;
      _searchDebounce?.cancel();
      _filter = 'all';
      _dateRange = 'all';
      _customStartDate = null;
      _customEndDate = null;
      _accountFilterId = null;
      _categoryFilterId = null;
      _counterpartyFilterId = null;
      _searchController.clear();
      _appliedSearch = '';
      _offlineScopeRows = null;
      _offlineMatches = null;
      _transactions = const [];
      _invoiceReceipts = const [];
      _visibleCount = _pageSize;
      unawaited(_restoreFiltersAndLoad());
      return;
    }
    if (oldWidget.dockResetToken != widget.dockResetToken) {
      unawaited(_load());
      if (_owner && Platform.isAndroid) {
        unawaited(_refreshPhotoCounts());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || !mounted) return;
    // Returning from background may follow a successful app-wide sync.
    // Refresh the scope automatically without clearing the visible list.
    // Force Offline is handled by _load and never invokes remote requests.
    unawaited(_load(showLoading: false));
  }

  Future<void> _restoreFiltersAndLoad() async {
    final epoch = ++_filterRestoreEpoch;
    final business = widget.businessId;
    final role = widget.roleCode;
    ExpenseFilterPreferences saved;
    try {
      saved = await ExpenseFilterPreferences.load(business, role);
    } catch (_) {
      saved = const ExpenseFilterPreferences();
    }
    if (!mounted || epoch != _filterRestoreEpoch ||
        business != widget.businessId || role != widget.roleCode) {
      return;
    }
    setState(() {
      _filter = saved.direction;
      _dateRange = saved.dateRange;
      _customStartDate = saved.customStart;
      _customEndDate = saved.customEnd;
      _accountFilterId = saved.accountId;
      _categoryFilterId = saved.categoryId;
      _counterpartyFilterId = saved.counterpartyId;
      _restoringFilters = false;
    });
    await _load();
  }

  Future<void> _saveFilters() async {
    final selection = ExpenseFilterPreferences(
      direction: _filter,
      dateRange: _dateRange,
      customStart: _customStartDate,
      customEnd: _customEndDate,
      accountId: _accountFilterId,
      categoryId: _categoryFilterId,
      counterpartyId: _counterpartyFilterId,
    );
    try {
      await selection.save(widget.businessId, widget.roleCode);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Filters could not be saved. Please select them again.'),
      ));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _photoCountTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter >= 500) {
      return;
    }
    final count = _combinedTransactions.length;
    if (_visibleCount < count) {
      setState(() => _visibleCount += _pageSize);
    } else {
      _loadMore();
    }
  }

  String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(value);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  // Avoid overflowing dates when a month has fewer days than today.
  DateTime _monthsAgoClamped(DateTime today, int months) {
    final first = DateTime(today.year, today.month - months, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month,
        today.day <= lastDay ? today.day : lastDay);
  }

  bool get _searching => _appliedSearch.isNotEmpty;
  DateTime? get _selectedRangeStart => _rangeStartDate;
  DateTime? get _selectedRangeEnd => _rangeEndDate;

  bool get _postedRangeVerified => _coversPeriod(
    _postedHistoryCoverage, _selectedRangeStart, _selectedRangeEnd,
  );

  bool _coversPeriod(
    ({DateTime? start, DateTime end})? coverage, DateTime? from, DateTime? to,
  ) {
    if (coverage == null) return false;
    final coveredStart = coverage.start;
    return (coveredStart == null ||
        (from != null && !from.isBefore(coveredStart))) &&
        !(to ?? _dateOnly(DateTime.now())).isAfter(coverage.end);
  }

  int? get _calendarYear => int.tryParse(_dateRange);

  DateTime? get _rangeStartDate {
    final today = _dateOnly(DateTime.now());
    if (_calendarYear case final year?) return DateTime(year, 1, 1);
    switch (_dateRange) {
      case '30d':
        return DateTime(today.year, today.month, today.day - 29);
      case '60d':
        return DateTime(today.year, today.month, today.day - 59);
      case '90d':
        return DateTime(today.year, today.month, today.day - 89);
      case 'thisMonth':
        return DateTime(today.year, today.month, 1);
      case 'lastMonth':
        return DateTime(today.year, today.month - 1, 1);
      case '3m':
        return _monthsAgoClamped(today, 3);
      case 'ytd':
        return DateTime(today.year, 1, 1);
      case '6m':
        return _monthsAgoClamped(today, 6);
      case '1y':
        return _monthsAgoClamped(today, 12);
      case 'custom':
        return _customStartDate;
      case 'all':
      default:
        return null;
    }
  }

  DateTime? get _rangeEndDate {
    if (_calendarYear case final year?) return DateTime(year, 12, 31);
    if (_dateRange == 'all') return null;
    if (_dateRange == 'custom') return _customEndDate;
    if (_dateRange == 'lastMonth') {
      final today = _dateOnly(DateTime.now());
      return DateTime(today.year, today.month, 0);
    }
    return _dateOnly(DateTime.now());
  }

  String get _rangeLabel {
    if (_calendarYear != null) return _dateRange;
    switch (_dateRange) {
      case '30d':
        return '30 days';
      case '60d':
        return '60 days';
      case '90d':
        return '90 days';
      case 'thisMonth':
        return 'this month';
      case 'lastMonth':
        return 'last month';
      case '3m':
        return 'last 3 months';
      case 'ytd':
        return 'year to date';
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
        return 'All Time';
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTransactions({
    required int offset,
    bool fastFirstPaint = false,
  }) async {
    final rows = await _api.transactionsPaged(
      widget.businessId,
      limit: _pageSize,
      offset: offset,
      startDate: _selectedRangeStart,
      endDate: _selectedRangeEnd,
      search: _searching ? _appliedSearch : null,
      direction: _filter == 'all' ? null : _filter,
      accountId: _accountFilterId,
      categoryId: _categoryFilterId,
      counterpartyId: _counterpartyFilterId,
    );
    if (fastFirstPaint) {
      // Price/fee verification is supplemental. The transaction list cannot
      // wait for sequential invoice-detail reads to show existing payments.
      return rows.map(WarrantyReceiptReporting.unverified).toList();
    }
    try {
      return await const WarrantyReceiptReporting().enrich(
        widget.businessId,
        rows,
      );
    } catch (_) {
      return rows.map(WarrantyReceiptReporting.unverified).toList();
    }
  }

  Future<void> _enrichVisiblePage(
    int epoch, String businessId, List<Map<String, dynamic>> rows,
  ) async {
    try {
      final checked = await const WarrantyReceiptReporting()
          .enrich(businessId, rows);
      if (!_isCurrentLoad(epoch, businessId)) return;
      final updates = {
        for (final row in checked)
          if ((row['id']?.toString() ?? '').isNotEmpty)
            row['id'].toString(): row,
      };
      setState(() {
        _transactions = [
          for (final existing in _transactions)
            if (updates.containsKey(existing['id']?.toString()))
              updates[existing['id']?.toString()]!
            else
              existing,
        ];
      });
    } catch (_) {
      // Unverified gross amounts remain explicitly labeled, not inferred.
    }
  }


  PayrollDisplayNames _payrollDisplayNames = const PayrollDisplayNames();

  Future<void> _load({
    bool showLoading = true,
    bool refreshReceipts = false,
    bool forceTotals = false,
  }) async {
    if (_restoringFilters) return;
    _appliedSearch = _searchController.text.trim();
    _offlineScopeRows = null;
    _offlineMatches = null;
    final epoch = ++_loadEpoch;
    _loadingMore = false;
    final businessId = widget.businessId;
    if (_serverConfirmedBusinessId != businessId) {
      _serverConfirmedTransactionIds.clear();
      _previousServerTransactionProofs = {};
      _serverConfirmedBusinessId = businessId;
    }
    // Totals are independent of the visible page; never display stale 50-row
    // sums as though they represented the selected accounting period.
    if (_showFinancialSummary) {
      unawaited(_refreshPeriodTotals(force: forceTotals || refreshReceipts));
    }
    if (showLoading) {
      setState(() {
        // Never blank a previously displayed financial list while refreshing.
        _loading = _transactions.isEmpty && _invoiceReceipts.isEmpty;
        _visibleCount = _pageSize;
        _transactionRefreshFailed = false;
        _error = null;
      });
    } else {
      setState(() {
        _error = null;
        _transactionRefreshFailed = false;
      });
    }

    if (_owner) {
      try {
        final names = await LocalEmployeeReports().displayNames(businessId);
        if (!_isCurrentLoad(epoch, businessId)) return;
        setState(() => _payrollDisplayNames = names);
      } catch (error) {
        if (_isCurrentLoad(epoch, businessId)) {
          setState(() => _payrollDisplayNames = const PayrollDisplayNames());
        }
        debugPrint('Payroll names could not be read: ${error.runtimeType}');
      }
      if (!_isCurrentLoad(epoch, businessId)) return;
      try {
        await OfflineFinancialWriteService().materializePendingPayrollExpenses(businessId);
      } catch (error) {
        debugPrint('Saved payroll expense projection remains queued: ${error.runtimeType}');
      }
      if (!_isCurrentLoad(epoch, businessId)) return;
    }

    // Cached financial rows paint quickly. Restore separately persisted,
    // previously authenticated server evidence before those rows render.
    // Absence of a proof remains an unknown gray cloud, never a green guess.
    try {
      final proofs = await _localFinancial.loadServerConfirmedTransactions(
        businessId,
      );
      final coverage = await _localFinancial.postedHistoryCoverage(businessId);
      if (_isCurrentLoad(epoch, businessId)) {
        setState(() {
          _previousServerTransactionProofs = proofs;
          _postedHistoryCoverage = coverage;
        });
      }
    } catch (_) {
      // A missing/corrupt verification cache must not block the list.
    }

    // Reload the durable offline payment queue on every entry/refresh.
    try {
      final receipts = await _invoiceFeed.load(widget.businessId);
      if (_isCurrentLoad(epoch, businessId)) {
        setState(() {
          // A search must not replace a newly fetched server receipt with
          // an older on-disk snapshot while background reconciliation runs.
          // Force Offline: the durable local feed is authoritative.
          // Merging prior UI rows resurrected deleted test payments until
          // process restart after Owner Delete.
          _invoiceReceipts =
              BriskersConnectionModeController.instance.forceOffline
                  ? receipts
                  : (_invoiceReceipts.isEmpty
                      ? receipts
                      : InvoicePaymentFeed.mergeReceipts(_invoiceReceipts, receipts));
          if (_invoiceReceipts.isNotEmpty) _loading = false;
        });
      }
    } catch (_) {
      // Preserve the existing financial list if cache access fails.
    }

    if (!_isCurrentLoad(epoch, businessId)) return;
    // Receipt visibility must never wait on full transaction-history downloads
    // or expensive cache persistence. The first receipt page paints immediately.
    if (showLoading || refreshReceipts) {
      if (!BriskersConnectionModeController.instance.forceOffline) {
        unawaited(_refreshInvoiceReceipts(businessId));
      }
    }
    final mode = BriskersConnectionModeController.instance;
    final forceOffline = mode.forceOffline;
    final forceOnline = mode.forceOnline;

    if (!forceOnline) {
      try {
        var localRows = await _localFinancial.loadTransactions(
          widget.businessId,
          startDate: _selectedRangeStart,
          endDate: _selectedRangeEnd,
          search: !forceOffline && _searching ? _appliedSearch : null,
          direction: _filter == 'all' ? null : _filter,
          accountId: _accountFilterId,
          categoryId: _categoryFilterId,
          counterpartyId: _counterpartyFilterId,
          includeCachedDetails: true,
        );
        if (!_isCurrentLoad(epoch, businessId)) return;
        if (forceOffline) {
          _offlineScopeRows = localRows;
          localRows = _matchOfflineSearch(localRows);
          _offlineMatches = localRows;
        }
        // The first offline frame displays at most 50 transactions.
        // Enrich only those rows. Enriching the entire ~1,000-row snapshot
        // first can delay the page and unnecessarily process many receipts.
        final hasMoreLocal = localRows.length > _pageSize;
        // Display cached transactions immediately; full processor-fee
        // verification is asynchronous and scoped to this navigation epoch.
        localRows = localRows.take(_pageSize).map(
          WarrantyReceiptReporting.unverified).toList();
        // Paint locally committed transactions before loading account/category
        // dropdown options. An options query failure must not blank Expenses.
        if (_isCurrentLoad(epoch, businessId) &&
            (localRows.isNotEmpty || BriskersConnectionModeController.instance.forceOffline)) {
          setState(() {
            _transactions = localRows;
            _hasMore = hasMoreLocal;
            _loading = false;
            _showingLocal = true;
            _error = null;
          });
        }
        final localOptions = await _localFinancial.loadOptions(
          widget.businessId,
        );

        if (_isCurrentLoad(epoch, businessId) &&
            (localRows.isNotEmpty || localOptions.isNotEmpty)) {
          setState(() {
            _quickTemplates = List<dynamic>.from(
              localOptions['quick_templates'] ?? const [],
            ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
            _accounts = List<dynamic>.from(localOptions['accounts'] ?? const [])
                .map((raw) => Map<String, dynamic>.from(raw as Map))
                .toList();
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
      if (_isCurrentLoad(epoch, businessId)) {
        setState(() {
          if (!_showingLocal && _transactions.isEmpty) {
            _transactions = const [];
          }
          // Keep _hasMore from the complete filtered local cache query.
          // Force Offline must not hide remaining historical pages.
          _loading = false;
          _error = null;
          _transactionRefreshFailed = false;
          _showingLocal = true;
        });
        // Existing installations have cached server invoice payments before
        // the new receipt inventory has ever been pulled. Restore them AFTER
        // painting, without changing saved payments or requiring a connection.
        if (_owner || widget.roleCode == 'manager') {
          unawaited(_recoverCachedInvoiceReceipts());
        }
      }
      return;
    }

    try {
      // Fetch just the visible page first. Waiting for historical 1,000-row
      // snapshots made newly posted invoice payments appear very late.
      final rows = await _fetchTransactions(
        offset: 0, fastFirstPaint: true);
      final reversed = {
        ...await _localFinancial.reversedPayrollExpenseIds(businessId),
        ...await _localFinancial.locallyVoidedExpenseIds(businessId),
      };
      if (!_isCurrentLoad(epoch, businessId)) return;
      setState(() {
        _serverConfirmedTransactionIds.addAll(
          rows.map((row) => row['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty),
        );
        // Retain locally committed, not-yet-synced financial entries if
        // the authenticated server's first page has not received them.
        // Identity-scoped replacement avoids duplicate list cards.
        _transactions = LocalFinancialCache.overlayPending(
          rows.where((row) => !reversed.contains(row['id'])).toList(),
          _transactions.where((row) => !reversed.contains(row['id'])).toList(),
        );
        _hasMore = rows.length == _pageSize;
        _loading = false;
        _showingLocal = false;
        _transactionRefreshFailed = false;
        _error = null;
      });
      unawaited(_enrichVisiblePage(epoch, businessId, rows));
      // Only the successful authenticated server response can add durable
      // proof. A viewing request does not import the remote history.
      unawaited(_localFinancial.saveServerConfirmedTransactions(
        businessId, rows,
      ).catchError((Object _) {}));
      // Options and the complete offline cache are not prerequisites for
      // showing a transaction or an invoice payment in Expenses & Income.
      unawaited(_loadFinancialOptions(epoch, businessId));
    } catch (error) {
      if (!_isCurrentLoad(epoch, businessId)) return;
      final forceOffline =
          BriskersConnectionModeController.instance.forceOffline;
      setState(() {
        _loading = false;
        _transactionRefreshFailed = !forceOffline;
        if (_showingLocal || forceOffline ||
            _transactions.isNotEmpty || _invoiceReceipts.isNotEmpty) {
          _error = null;
        } else {
          _error = error.toString();
        }
      });
    }
  }

  Future<void> _refreshPeriodTotals({bool force = false}) async {
    // Do not even query/report financial totals for secretary or other roles.
    if (!_showFinancialSummary || !mounted) return;
    final businessId = widget.businessId;
    final offline =
        BriskersConnectionModeController.instance.forceOffline;
    final startDate = _rangeStartDate;
    final endDate = _rangeEndDate;
    final checkedThrough = endDate ?? _dateOnly(DateTime.now());
    final direction = _filter == 'all' ? null : _filter;
    final accountId = _accountFilterId;
    final categoryId = _categoryFilterId;
    final counterpartyId = _counterpartyFilterId;
    final scope = [
      businessId,
      widget.roleCode,
      startDate?.toIso8601String() ?? '',
      endDate?.toIso8601String() ?? '',
      '',
      direction ?? '',
      accountId ?? '',
      categoryId ?? '',
      counterpartyId ?? '',
    ].join('|');
    // Restore complete stored totals and add all locally committed deltas.
    // The server is NOT a prerequisite for entering the Expenses screen.
    if (_pendingPeriodScope == scope && !force) return;
    final epoch = ++_periodEpoch;
    final journal = LocalFinancialTotalsJournal();
    _pendingPeriodScope = scope;
    if (_lastPeriodScope != scope) {
      setState(() {
        _periodTotals = null;
        _periodError = null;
        _periodCalculating = true;
      });
    }
    final sameScope = _lastPeriodScope == scope && _serverPeriodBase != null;
    final sqliteSaved = await journal.loadBaseline(businessId, scope);
    // Migrate an older complete verified snapshot from preferences once.
    final legacy = sqliteSaved == null
        ? await const VerifiedExpenseTotalsCache().load(scope) : null;
    if (sqliteSaved == null && legacy != null) {
      await journal.saveBaseline(
          businessId, scope, legacy.totals, legacy.at);
    }
    // A rolling 30/60/90-day filter shifts at midnight. Its previous exact
    // baseline is still valuable: reuse verified daily buckets for the
    // overlapping days and include local committed changes for today.
    // The unsynced new day is labeled explicitly, never called verified.
    final rolling = sqliteSaved == null && legacy == null &&
            startDate != null && endDate != null
        ? await journal.loadRollingBaseline(
            businessId, scope, startDate: startDate, endDate: endDate,
          ) : null;
    if (!mounted || epoch != _periodEpoch || !_showFinancialSummary ||
        widget.businessId != businessId) {
      return;
    }
    final baseline = sqliteSaved?.totals ?? legacy?.totals ??
        rolling?.totals ?? (sameScope ? _serverPeriodBase : null);
    final lastVerified = sqliteSaved?.at ?? legacy?.at ??
        rolling?.at ?? (sameScope ? _lastPeriodAt : null);
    final rolloverPending = rolling != null && endDate != null &&
        rolling.verifiedThrough.isBefore(endDate);
    ExpensesPeriodTotals? local;
    bool usingSavedRows = false;
    var hasCompleteLocalHistory = false;
    int localChanges = 0;
    try {
      final coverage = await _localFinancial.postedHistoryCoverage(businessId);
      hasCompleteLocalHistory = _coversPeriod(coverage, startDate, endDate);
      if (baseline != null && !hasCompleteLocalHistory) {
        local = await journal.apply(
          businessId, baseline,
          startDate: startDate, endDate: endDate,
          direction: direction,
          accountId: accountId, categoryId: categoryId,
          counterpartyId: counterpartyId,
        );
      } else {
        // Never present a cached first page as a verified COMPLETE history.
        // It is still useful as a clearly marked on-device subtotal.
        final cached = await _localFinancial.loadTransactions(
          businessId, includeCachedDetails: true,
        );
        final effective = await journal.overlayCachedRows(businessId, cached);
        final annual = (direction == null || direction == 'expense') &&
                accountId == null && categoryId == null && counterpartyId == null
            ? await _localFinancial.reuseClosedYearExpenses(
                businessId, effective, from: startDate, through: endDate,
                coverage: coverage, currentYear: DateTime.now().year,
              )
            : (liveRows: effective, cents: 0, count: 0);
        local = await LocalExpenseSubtotal.calculate(annual.liveRows,
          enrichPage: (rows) => const WarrantyReceiptReporting().enrich(
            businessId, rows, refresh: false,
          ),
          startDate: startDate, endDate: endDate,
          direction: direction,
          accountId: accountId, categoryId: categoryId,
          counterpartyId: counterpartyId);
        if (annual.count != 0) {
          local = ExpensesPeriodTotals(
            income: local?.income ?? 0,
            expenses: (((local?.expenses ?? 0) * 100).round() + annual.cents) / 100,
            transactions: (local?.transactions ?? 0) + annual.count,
            feesUnverified: local?.feesUnverified ?? false,
            unverifiedIncomeReceipts: local?.unverifiedIncomeReceipts ?? 0,
          );
        }
        if (hasCompleteLocalHistory) {
          local ??= const ExpensesPeriodTotals(
            income: 0, expenses: 0, transactions: 0,
            feesUnverified: false, unverifiedIncomeReceipts: 0,
          );
        }
        usingSavedRows = true;
      }
      localChanges = await journal.pendingCount(businessId);
    } catch (_) {
      if (mounted && epoch == _periodEpoch) {
        setState(() {
          _periodCalculating = false;
          _pendingPeriodScope = null;
          _periodError = 'Local totals need verification. Refresh to retry.';
        });
      }
      return;
    }
    if (!mounted || epoch != _periodEpoch || !_showFinancialSummary ||
        widget.businessId != businessId) {
      return;
    }
    // An upgraded b2468 device may have a perfectly valid exact baseline
    // saved before daily buckets existed. Keep displaying its totals now, but
    // seed daily buckets with ONE background reconciliation so tomorrow's
    // rolling range will not hit the same cold-cache problem.
    final needsDailySeed = baseline != null && rolling == null &&
        startDate != null && endDate != null &&
        await journal.loadRollingBaseline(
          businessId, scope, startDate: startDate, endDate: endDate,
        ) == null;
    if (!mounted || epoch != _periodEpoch || !_showFinancialSummary ||
        widget.businessId != businessId) {
      return;
    }
    final savedClosedPeriod = hasCompleteLocalHistory && endDate != null &&
        endDate.isBefore(DateTime(DateTime.now().year));
    final fresh = savedClosedPeriod ||
        (!rolloverPending && !needsDailySeed && lastVerified != null &&
            DateTime.now().difference(lastVerified) < const Duration(minutes: 30));
    setState(() {
      _serverPeriodBase = baseline;
      _periodTotals = local;
      _lastPeriodScope = scope;
      _lastPeriodAt = lastVerified;
      _periodCalculating = false;
      _periodError = local == null
          ? (offline ? 'No saved transactions for this period. History may be missing.'
              : 'Preparing first complete local baseline…')
          : usingSavedRows
              ? 'Saved totals for $_rangeLabel · ${local.transactions} posted '
                'transactions · ${hasCompleteLocalHistory ? 'history checked for this period' : 'history incomplete or unverified'}'
          : rolloverPending
              ? 'Saved local totals through ${DateFormat('MMM d').format(rolling.verifiedThrough)} · today not yet verified'
              : offline
                  ? 'Totals checked ${DateFormat('MMM d, h:mm a').format(lastVerified!)} '
                    '· some transaction details may be missing on this device'
                    '${localChanges > 0 ? ' · includes local changes' : ''}'
                  : localChanges > 0
                      ? 'Includes $localChanges locally saved change(s) · sync pending'
                      : 'Saved local totals · verified ${DateFormat('MMM d, h:mm a').format(lastVerified!)}';
    });
    if (offline || (fresh && !force)) {
      _pendingPeriodScope = null;
      return;
    }
    // Only a missing/old snapshot or an explicit refresh runs a full scan.
    // The previously projected figures remain visible during verification.
    if (_periodTotals == null) {
      setState(() => _periodCalculating = true);
    }

    bool current() =>
        mounted && epoch == _periodEpoch &&
        _pendingPeriodScope == scope &&
        widget.businessId == businessId &&
        !BriskersConnectionModeController.instance.forceOffline;
    try {
      final fetchedPages = <int, List<Map<String, dynamic>>>{};
      var pageSize = 0;
      final totals = await ExpensesPeriodTotals.calculate(
        isCurrent: current,
        readPage: (offset, limit) async {
          final rows = await _api.transactionsPaged(
            businessId,
            offset: offset, limit: limit,
            startDate: startDate, endDate: endDate,
            direction: direction,
            accountId: accountId,
            categoryId: categoryId,
            counterpartyId: counterpartyId,
          );
          pageSize = limit;
          fetchedPages[offset] = rows;
          return rows;
        },
        enrichPage: (rows) => const WarrantyReceiptReporting().enrich(
          businessId, rows, refresh: false,
        ),
      );
      if (!current()) return;
      final completeRows = <Map<String, dynamic>>[];
      for (var offset = 0; fetchedPages.containsKey(offset); offset += pageSize) {
        final page = fetchedPages[offset]!;
        completeRows.addAll(page);
        if (page.length < pageSize) break;
      }
      if (completeRows.length != totals.transactions) {
        throw StateError('Transaction pages changed while totals were checked.');
      }
      var refreshedCoverage = _postedHistoryCoverage;
      if (direction == null && accountId == null && categoryId == null &&
          counterpartyId == null) {
        // Save the same rows that supported the complete online totals.
        // A later Force Offline session can use the underlying history.
        await _localFinancial.mergeServerTransactions(businessId, completeRows);
        await _localFinancial.savePostedHistoryCoverage(
          businessId, startDate, checkedThrough,
        );
        refreshedCoverage = await _localFinancial.postedHistoryCoverage(businessId);
      }
      if (!current()) return;
      // Retire only receipts proven identical by the complete authenticated
      // history and exact operation/transaction identities.
      final verifiedAt = DateTime.now();
      await journal.reconcileAndSaveBaseline(
        businessId, scope, totals, verifiedAt,
        completeRows, receipts: _invoiceReceipts,
      );
      final projected = await journal.apply(
        businessId, totals,
        startDate: startDate, endDate: endDate,
        direction: direction,
        accountId: accountId, categoryId: categoryId,
        counterpartyId: counterpartyId,
      );
      final remaining = await journal.pendingCount(businessId);
      if (!current()) return;
      // Preferences are a legacy fallback; SQLite above is authoritative.
      try {
        await const VerifiedExpenseTotalsCache().save(scope, totals, verifiedAt);
      } catch (_) { /* Keep the in-memory verified baseline. */ }
      if (!current()) return;
      setState(() {
        _postedHistoryCoverage = refreshedCoverage;
        _serverPeriodBase = totals;
        _periodTotals = projected;
        _lastPeriodScope = scope;
        _lastPeriodAt = verifiedAt;
        _pendingPeriodScope = null;
        _periodCalculating = false;
        _periodError = remaining > 0
            ? 'Includes $remaining locally saved change(s) · sync pending'
            : null;
      });
    } catch (_) {
      if (!current()) return;
      setState(() {
        _pendingPeriodScope = null;
        // A previously verified same-scope total is retained only if we
        // explicitly label it as historical, never silently as current.
        if (_lastPeriodScope != scope) _periodTotals = null;
        _periodCalculating = false;
        _periodError = _periodTotals != null && _lastPeriodScope == scope
            ? 'Showing last verified totals; refresh failed.'
            : 'Complete totals are unavailable. Refresh to retry.';
      });
    }
  }

  Future<void> _loadFinancialOptions(
    int epoch, String businessId,
  ) async {
    try {
      final options = await _api.transactionOptions(businessId);
      if (!_isCurrentLoad(epoch, businessId) ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }
      setState(() {
        _quickTemplates = (options['quick_templates'] as List? ?? const [])
            .whereType<Map>().map(Map<String, dynamic>.from).toList();
        _accounts = (options['accounts'] as List? ?? const [])
            .whereType<Map>().map(Map<String, dynamic>.from).toList();
        _categories = (options['categories'] as List? ?? const [])
            .whereType<Map>().map(Map<String, dynamic>.from).toList();
        _counterparties = (options['counterparties'] as List? ?? const [])
            .whereType<Map>().map(Map<String, dynamic>.from).toList();
      });
      await _localFinancial.saveOptions(businessId, options);
    } catch (_) {
      // Keep the locally available options and already visible records.
    }
  }

  Future<void> _recoverCachedInvoiceReceipts() async {
    if (_recoveringCachedReceipts) return;
    _recoveringCachedReceipts = true;
    try {
      final businessId = widget.businessId;
      final rows = await _invoiceFeed.pendingFromCachedInvoices(businessId);
      if (!mounted || widget.businessId != businessId || rows.isEmpty) return;
      setState(() => _invoiceReceipts = InvoicePaymentFeed.mergeReceipts(
        _invoiceReceipts, rows,
      ));
    } catch (_) {
      // Preserve the local outbox and posted financial snapshot unchanged.
    } finally {
      _recoveringCachedReceipts = false;
    }
  }

  Future<void> _refreshInvoiceReceipts(String businessId) async {
    // A user searching invoices must not cancel a payment that is still
    // arriving from the server. Receipt refresh has its own lifecycle.
    final epoch = ++_receiptEpoch;
    try {
      if (BriskersConnectionModeController.instance.forceOffline) return;
      final page = await _api.invoiceReceipts(businessId, limit: _pageSize, offset: 0);
      if (!_isCurrentReceipt(epoch, businessId) ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }
      setState(() {
        _invoiceReceipts = InvoicePaymentFeed.reconcileOnlineFirstPage(page, _invoiceReceipts);
        if (_invoiceReceipts.isNotEmpty) _loading = false;
      });
    } catch (_) {
      // Keep locally recorded payments visible on old/unavailable backends.
    }
  }

  Future<void> _openInvoiceReceipt(Map<String, dynamic> row) async {
    final invoiceId = row['document_id']?.toString() ?? '';
    if (invoiceId.isEmpty) {
      await _viewInvoiceReceipt(row);
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: invoiceId,
          isOwner: _owner,
          roleCode: widget.roleCode,
          initialTab: 'payment',
        ),
      ),
    );
    if (mounted) {
      unawaited(_load(showLoading: false, refreshReceipts: true));
    }
  }

  Future<void> _viewInvoiceReceipt(Map<String, dynamic> row) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row['counterparty']?.toString() ?? 'Customer',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Invoice #${row['document_number'] ?? '—'}'),
              Text('Payment method: ${row['payment_method_name'] ?? 'Payment'}'),
              Text('Amount: ${_money(row['amount'])}'),
              Text('Date: ${row['transaction_date'] ?? '—'}'),
              const SizedBox(height: 12),
              const Text('Payment details and finalization are managed on the invoice.'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context),
                    child: const Text('Close')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final epoch = _loadEpoch;
    final businessId = widget.businessId;
    final local = _showingLocal;
    final offset = _transactions.length;
    setState(() => _loadingMore = true);
    try {
      // Offline has the same paginated browsing as online. Only page the
      // locally saved ledger; never connect merely to reveal older records.
      if (local) {
        final cached = _offlineMatches ?? await _localFinancial.loadTransactions(
          businessId,
          startDate: _selectedRangeStart,
          endDate: _selectedRangeEnd,
          search: _searching ? _appliedSearch : null,
          direction: _filter == 'all' ? null : _filter,
          accountId: _accountFilterId,
          categoryId: _categoryFilterId,
          counterpartyId: _counterpartyFilterId,
          includeCachedDetails: true,
        );
        if (!_isCurrentLoad(epoch, businessId) || !_showingLocal) return;
        final next = cached.skip(offset).take(_pageSize)
            .map(WarrantyReceiptReporting.unverified).toList();
        setState(() {
          _transactions = [..._transactions, ...next];
          _visibleCount += next.length;
          _hasMore = cached.length > _transactions.length;
          _loadingMore = false;
        });
        return;
      }
      final rows = await _fetchTransactions(offset: offset);
      final reversed = {
        ...await _localFinancial.reversedPayrollExpenseIds(businessId),
        ...await _localFinancial.locallyVoidedExpenseIds(businessId),
      };
      if (!_isCurrentLoad(epoch, businessId) || _showingLocal) return;
      setState(() {
        _serverConfirmedTransactionIds.addAll(
          rows.map((row) => row['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty),
        );
        _transactions = LocalFinancialCache.overlayPending(
          [..._transactions, ...rows].where((row) => !reversed.contains(row['id'])).toList(),
          _transactions.where((row) => !reversed.contains(row['id'])).toList(),
        );
        _hasMore = rows.length == _pageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!_isCurrentLoad(epoch, businessId)) return;
      setState(() {
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _downloadSavedHistory() async {
    if (!_owner || _downloadingHistory) return;
    // One explicit download fills every historical period, regardless of
    // the active period, account, direction or search filter.
    final end = _dateOnly(DateTime.now());
    final allowed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BriskersDialog(
        title: 'Download saved history?',
        icon: Icons.download_for_offline_outlined,
        content: const Text(
          'Download all posted income and expenses through today, plus the '
          'invoice list. The download can renew your Owner session if needed. '
          'Force Offline stays enabled and queued changes stay on the device.',
        ),
        actions: [
          OutlinedButton(style: BriskersDialog.cancelStyle,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel')),
          FilledButton(style: BriskersDialog.confirmStyle(),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Download')),
        ],
      ),
    ) ?? false;
    if (!allowed || !mounted) return;
    setState(() {
      _downloadingHistory = true;
      _downloadedHistoryCount = 0;
      _historyRecoveryMessage = null;
    });
    try {
      final business = widget.businessId;
      final recovery = FinancialHistoryRecovery(cache: _localFinancial);
      final count = await recovery.download(
        businessId: business,
        start: null,
        end: end,
        onPage: (count) {
          if (mounted) setState(() => _downloadedHistoryCount = count);
        },
      );
      if (!mounted || business != widget.businessId) return;
      var message = 'Saved $count posted transactions.';
      try {
        final invoices = await recovery.downloadInvoices(business);
        message += ' Saved $invoices invoice records.';
      } catch (error) {
        message += ' Invoice history could not be downloaded. '
            '${FinancialHistoryRecovery.failureMessage(error)}';
      }
      if (!mounted || business != widget.businessId) return;
      setState(() => _historyRecoveryMessage = message);
      await _load(showLoading: false, forceTotals: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _historyRecoveryMessage =
        'Download incomplete. ${FinancialHistoryRecovery.failureMessage(error)} '
        'Saved records were retained and queued payments stayed on this device.');
      // Refresh the local view only, never toggle connection mode.
      await _load(showLoading: false);
    } finally {
      if (mounted) setState(() => _downloadingHistory = false);
    }
  }

  List<Map<String, dynamic>> _matchOfflineSearch(
    List<Map<String, dynamic>> rows,
  ) {
    if (!_searching) return rows;
    final query = _appliedSearch.toLowerCase();
    final words = query.split(RegExp(r'\s+'));
    return rows.where((row) {
      final saved = _searchIndex[row] ??= LocalTransactionSearch.fields(row);
      final fullName = _owner ? _payrollDisplayNames.forExpense(row) : null;
      final fields = fullName == null ? saved : '$saved ${fullName.toLowerCase()}';
      return fields.contains(query) || words.every(fields.contains);
    }).toList();
  }

  void _applySearch() {
    _searchDebounce?.cancel();
    final saved = _offlineScopeRows;
    if (saved == null || !BriskersConnectionModeController.instance.forceOffline) {
      unawaited(_load(showLoading: false));
      return;
    }
    ++_loadEpoch;
    setState(() {
      _appliedSearch = _searchController.text.trim();
      final matches = _matchOfflineSearch(saved);
      _offlineMatches = matches;
      _transactions = matches.take(_pageSize)
          .map(WarrantyReceiptReporting.unverified).toList();
      _visibleCount = _pageSize;
      _loadingMore = false;
      _hasMore = matches.length > _pageSize;
    });
  }

  void _searchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _applySearch();
    });
  }

  Future<void> _chooseDirection() async {
    if (_restoringFilters) return;
    final filterScope = (widget.businessId, widget.roleCode);
    FocusManager.instance.primaryFocus?.unfocus();
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
                trailing: _filter == option.$1 ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, option.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || filterScope != (widget.businessId, widget.roleCode) ||
        selected == null || selected == _filter) {
      return;
    }
    if (!mounted) return;
    setState(() => _filter = selected);
    await _saveFilters();
    if (mounted) await _load();
  }

  Future<void> _chooseDateRange() async {
    if (_restoringFilters) return;
    final filterScope = (widget.businessId, widget.roleCode);
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final business = widget.businessId;
    final years = <int>{now.year - 1};
    try {
      final saved = await _localFinancial.loadTransactions(business);
      for (final row in saved) {
        final date = DateTime.tryParse(row['transaction_date']?.toString() ?? '');
        if (date != null && date.year < now.year) years.add(date.year);
      }
    } catch (_) {
      // Custom date ranges remain available when saved history can't be read.
    }
    if (!mounted || widget.businessId != business) return;
    final calendarYears = years.toList()..sort((a, b) => b.compareTo(a));
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Select date range',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
            for (final option in [
              ('all', 'All Time'),
              ('30d', 'Last 30 days'),
              ('60d', 'Last 60 days'),
              ('90d', 'Last 90 days'),
              ('thisMonth', 'This Month'),
              ('lastMonth', 'Last Month'),
              ('3m', 'Last 3 Months'),
              ('6m', 'Last 6 months'),
              ('ytd', 'Year to Date'),
              ('1y', 'Last 1 year'),
              for (final year in calendarYears) ('$year', '$year calendar year'),
              ('custom', 'Custom date range'),
            ])
              ListTile(
                title: Text(option.$2),
                trailing: _dateRange == option.$1
                    ? const Icon(Icons.check, color: BriskersColors.invoices)
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
    if (!mounted || filterScope != (widget.businessId, widget.roleCode) ||
        selected == null) {
      return;
    }

    if (selected == 'custom') {
      if (!mounted) return;
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(calendarYears.last < now.year - 10
            ? calendarYears.last : now.year - 10),
        lastDate: now,
        initialDateRange: _customStartDate != null && _customEndDate != null
            ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
            : DateTimeRange(
                start: now.subtract(const Duration(days: 30)),
                end: now,
              ),
      );
      if (!mounted || filterScope != (widget.businessId, widget.roleCode) ||
          picked == null) {
        return;
      }
      _customStartDate = _dateOnly(picked.start);
      _customEndDate = _dateOnly(picked.end);
    }

    if (!mounted) return;
    setState(() => _dateRange = selected);
    await _saveFilters();
    if (mounted) await _load();
  }

  Future<void> _showAdvancedFilters() async {
    if (_restoringFilters) return;
    final filterScope = (widget.businessId, widget.roleCode);
    FocusManager.instance.primaryFocus?.unfocus();
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
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
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
                    if (accountId != null && !_accounts.any(
                      (item) => item['id']?.toString() == accountId))
                      DropdownMenuItem<String?>(
                        value: accountId,
                        child: const Text('Saved account (unavailable)'),
                      ),
                    ..._accounts.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item['id']?.toString(),
                        child: Text(item['name']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (value) => setSheetState(() => accountId = value),
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
                    if (categoryId != null && !_categories.any(
                      (item) => item['id']?.toString() == categoryId))
                      DropdownMenuItem<String?>(
                        value: categoryId,
                        child: const Text('Saved category (unavailable)'),
                      ),
                    ..._categories.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item['id']?.toString(),
                        child: Text(item['name']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (value) => setSheetState(() => categoryId = value),
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
                    if (counterpartyId != null && !_counterparties.any(
                      (item) => item['id']?.toString() == counterpartyId))
                      DropdownMenuItem<String?>(
                        value: counterpartyId,
                        child: const Text('Saved payee (unavailable)'),
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
                        onPressed: () => Navigator.pop(sheetContext, true),
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

    if (applied != true || !mounted ||
        filterScope != (widget.businessId, widget.roleCode)) {
      return;
    }
    setState(() {
      _accountFilterId = accountId;
      _categoryFilterId = categoryId;
      _counterpartyFilterId = counterpartyId;
    });
    await _saveFilters();
    if (mounted) await _load();
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
    if (changed == true && mounted) {
      // Keep the existing list visible while the locally saved transaction
      // is picked up and the authoritative server snapshot reconciles.
      // A full-screen spinner here made successful saves appear delayed.
      unawaited(_load(showLoading: false, forceTotals: true));
    }
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
    NavigationContentTiming.start('expense_detail');
    var changed = false;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseDetailScreen(
          businessId: widget.businessId,
          transactionId: id,
          onChanged: () => changed = true,
          allowRecurring: _allowRecurring,
          canDeleteTransaction: widget.roleCode == 'owner',
          // The tapped list row is safe to show as a non-editable preview.
          // Waiting for the server here caused an empty full-screen spinner.
          cachedDetail: Map<String, dynamic>.from(transaction),
          payrollDisplayName: _owner ? _payrollDisplayNames.forExpense(transaction) : null,
        ),
      ),
    );
    // Reading a detail does not invalidate the entire list. Actual mutations
    // refresh in the background while preserving the existing first frame.
    if (changed && mounted) {
      unawaited(_load(showLoading: false, forceTotals: true));
    }
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
    if (changed == true && mounted) {
      // Transaction changes have already been durably committed to SQLite.
      // Do not delay returning to the usable local Expenses list for totals
      // pagination, processor-fee verification or network reconciliation.
      unawaited(_load(showLoading: false, forceTotals: true));
    }
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
    if (changed == true && mounted) {
      // Transaction changes have already been durably committed to SQLite.
      // Do not delay returning to the usable local Expenses list for totals
      // pagination, processor-fee verification or network reconciliation.
      unawaited(_load(showLoading: false, forceTotals: true));
    }
  }

  Future<void> _deleteTransactionFromList(String transactionId) async {
    final confirmed =
        await showDialog<bool>(
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
      if (mounted) await _load(forceTotals: true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _deleteStandaloneExpenseFromList(
    String id, Map<String, dynamic> detail,
  ) async {
    final businessId = widget.businessId;
    try {
      final grant = await DeviceOwnerAuthorization.instance.authority
          .authorizeLocal(businessId);
      if (!mounted || widget.businessId != businessId) return;
      await _localFinancial.saveTransactionDetail(businessId, id, detail);
      final writes = OfflineFinancialWriteService();
      await writes.deleteStandaloneExpense(
        businessId, id,
        assertAuthorized: () => grant.assertValid(
          businessId, supabase.auth.currentUser?.id ?? '',
        ),
      );
      if (!mounted || widget.businessId != businessId) return;
      setState(() {
        _transactions = _transactions.where((row) => row['id'] != id).toList();
      });
      unawaited(_load(showLoading: false, forceTotals: true));
      unawaited(writes.syncExpenseDeletions(businessId).catchError((Object _) {}));
    } catch (error) {
      if (mounted && widget.businessId == businessId) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _showTransactionActions(Map<String, dynamic> transaction) async {
    final id = transaction['id']?.toString() ?? '';
    if (id.isEmpty) return;

    Map<String, dynamic> detail;
    if (_showingLocal) {
      detail =
          await _localFinancial.loadTransactionDetail(widget.businessId, id) ??
          Map<String, dynamic>.from(transaction);
    } else {
      try {
        detail = await _api.transactionDetail(widget.businessId, id);
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
        return;
      }
    }
    if (!mounted) return;

    final payroll = LocalFinancialCache.requiresOwnerAccountEdit(detail) ||
        LocalFinancialCache.requiresOwnerAccountEdit(transaction);
    final editable = payroll ? _owner : _showingLocal || detail['editable'] == true;
    final standaloneDelete = _owner &&
        LocalFinancialCache.canDeleteStandaloneExpense(detail);
    final deletable = standaloneDelete ||
        (!_showingLocal && _owner && detail['deletable'] == true);

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _ActionSectionLabel('Transaction'),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('View transaction'),
              onTap: () => Navigator.pop(sheetContext, 'view'),
            ),
            if (editable)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(payroll ? 'Edit account' : 'Edit transaction'),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
            if (editable && !payroll)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy transaction'),
                onTap: () => Navigator.pop(sheetContext, 'copy'),
              ),
            if (deletable) ...[
              const Divider(height: 1),
              const _ActionSectionLabel('Delete'),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
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
    if (action == 'delete') {
      if (standaloneDelete) {
        await _deleteStandaloneExpenseFromList(id, detail);
      } else {
        await _deleteTransactionFromList(id);
      }
    }
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

  /// Safe to restart: the server excludes expenses with finalized photos.
  /// The source photos are never moved or deleted.
  Future<void> _refreshPhotoCounts({bool force = false}) async {
    if (!_owner ||
        !Platform.isAndroid ||
        _photoCountsReading ||
        (_importing && !force)) {
      return;
    }
    _photoCountsReading = true;
    try {
      final counts = await _photoSync.counts(widget.businessId);
      if (mounted) {
        setState(() {
          _photoCounts = counts;
          _photoQueueError = null;
        });
      }
    } catch (error) {
      // Never silently leave the owner stuck on "Reading local photo queue".
      if (mounted) {
        setState(() => _photoQueueError = error.toString());
      }
    } finally {
      _photoCountsReading = false;
    }
  }

  Future<void> _togglePhotoSync(bool enabled) async {
    await _photoSync.setOptions(widget.businessId, enabled: enabled);
    await _refreshPhotoCounts();
    if (enabled) {
      try {
        await ExpenseIqBackgroundScheduler.schedule(widget.businessId);
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _toggleWifiOnly(bool wifiOnly) async {
    await _photoSync.setOptions(widget.businessId, wifiOnly: wifiOnly);
    await _refreshPhotoCounts();
    if (_photoCounts?.enabled == true) {
      try {
        await ExpenseIqBackgroundScheduler.schedule(widget.businessId);
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _requestPhotoSync() async {
    if (_requestingPhotoSync) return;
    setState(() => _requestingPhotoSync = true);
    try {
      await ExpenseIqBackgroundScheduler.scheduleNext(widget.businessId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Android will upload when network and battery conditions allow.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _requestingPhotoSync = false);
    }
  }

  Future<void> _importExpenseIqReceipts() async {
    if (_importing || !_owner || !Platform.isAndroid) return;
    if (BriskersConnectionModeController.instance.forceOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect once to index the photo mappings.'),
        ),
      );
      return;
    }

    List<Map<String, dynamic>> candidates;
    try {
      candidates = await _api.expenseReceiptImportCandidates(widget.businessId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All mapped ExpenseIQ receipts are already uploaded.'),
        ),
      );
      return;
    }

    List<dynamic>? picked;
    try {
      picked = await _expenseIqChannel.invokeMethod<List<dynamic>>(
        'pickExpenseIqFolder',
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not scan ExpenseIQ folder: $error');
      }
      return;
    }
    if (picked == null || !mounted) return;
    final files = picked
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList();
    final fileKeys = files
        .map((x) => _photoKey(x['name']?.toString() ?? ''))
        .where((key) => key.isNotEmpty)
        .toSet();
    final matches = candidates
        .where(
          (candidate) => fileKeys.contains(
            candidate['photo_id']?.toString().trim().toLowerCase() ?? '',
          ),
        )
        .length;
    final missing = candidates.length - matches;

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Index ExpenseIQ photos locally?'),
        content: SingleChildScrollView(
          child: Text(
            'Matched: $matches photos\n'
            'Unmatched: $missing references\n\n'
            'Briskers will save original photo locations and their existing '
            'expense links to SQLite; it will NOT duplicate or move files. '
            'Do not move or delete the ExpenseIQ folder.\n\n'
            'Background sync will use Wi-Fi by default and can be paused. '
            'Photos already uploaded to Supabase will be skipped.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Index locally'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    setState(() {
      _importing = true;
      _indexProcessed = 0;
      _indexExpected = candidates.length;
      _photoQueueError = null;
    });
    try {
      final index = await _photoSync.indexPhotos(
        widget.businessId,
        candidates: candidates,
        files: files,
        onProgress: (processed, total) {
          if (!mounted) return;
          setState(() {
            _indexProcessed = processed;
            _indexExpected = total;
          });
        },
      );
      await _refreshPhotoCounts(force: true);
      String scheduleError = '';
      try {
        await ExpenseIqBackgroundScheduler.schedule(widget.businessId);
      } catch (error) {
        scheduleError = ' Scheduling error: $error';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 10),
            content: Text(
              'Indexed ${index.matched} photos locally; '
              '${index.missing} unmatched.$scheduleError',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  List<Map<String, dynamic>> get _combinedTransactions {
    final scope = (_transactions, _invoiceReceipts, _selectedRangeStart,
      _selectedRangeEnd, _appliedSearch, _filter, _accountFilterId,
      _categoryFilterId, _counterpartyFilterId);
    if (_combinedScope != scope) {
      _combinedRows = InvoicePaymentFeed.combine(
        financial: _transactions,
        receipts: _invoiceReceipts,
        startDate: _selectedRangeStart,
        endDate: _selectedRangeEnd,
        search: _appliedSearch,
        direction: _filter == 'all' ? null : _filter,
        filteredAccount: _accountFilterId != null ||
            _categoryFilterId != null || _counterpartyFilterId != null,
      );
      _combinedScope = scope;
    }
    return _combinedRows;
  }

  String get _searchSubtotal {
    final rows = _offlineMatches ?? _transactions;
    final cents = rows.fold<int>(0, (sum, row) {
      final amount = num.tryParse(row['amount']?.toString() ?? '') ?? 0;
      if (!amount.isFinite) return sum;
      return sum + (amount * 100).round() *
          (row['direction'] == 'expense' ? -1 : 1);
    });
    final scope = _offlineMatches == null ? 'Loaded' : 'Saved';
    return '$scope posted search subtotal · ${rows.length} matches · '
        '${_money(cents / 100)} net before fees';
  }

  @override
  Widget build(BuildContext context) {
    final allVisible = _combinedTransactions;
    final visible = allVisible.take(_visibleCount).toList();
    final moreReceiptPages = allVisible.length > _visibleCount;
    final receiptsUnverified = _periodTotals?.feesUnverified == true;
    final unverifiedCount = _periodTotals?.unverifiedIncomeReceipts;

    return Scaffold(
      // Keep the primary action anchored at lower-right, independent of
      // the transaction search/filter row and above the regular navigation.
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('expenses-new-floating'),
        onPressed: _importing ? null : _showAddMenu,
        backgroundColor: BriskersColors.expenses,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New',
          style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: widget.showAppBar
          ? AppBar(
              toolbarHeight: 68,
              backgroundColor:
                  const Color(0xFFC62828).withValues(alpha: 0.08),
              title: BriskersPageTitle(
                  title: tr('expensesIncome'), logoHeight: 40),
            )
          : null,

      // Keep the Expenses page mounted and visible while the local first
      // page hydrates. Blocking the whole body on a spinner looks blank on
      // some Android startup paths and prevents immediate navigation.
      body: RefreshIndicator(
              onRefresh: () => _load(forceTotals: true),
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    sliver: SliverList.list(children: [
                  if (!widget.showAppBar) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 2, 6, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('expensesIncome'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          // No tall banner in Auto: preserve list position.
                          // A compact icon still exposes a genuine failure.
                          if (_showingLocal &&
                              (BriskersConnectionModeController
                                      .instance.forceOffline ||
                                  _transactionRefreshFailed))
                            Tooltip(
                              message: BriskersConnectionModeController
                                      .instance.forceOffline
                                  ? 'Offline mode • showing saved transactions'
                                  : 'Unable to refresh transactions • showing saved data',
                              child: const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(Icons.cloud_off_outlined, size: 20),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
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
                                    _periodTotals == null
                                        ? (_periodCalculating
                                            ? 'Calculating…' : 'Unavailable')
                                        : _money(_periodTotals!.income),
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
                                    _periodTotals == null
                                        ? (_periodCalculating
                                            ? 'Calculating…' : 'Unavailable')
                                        : _money(_periodTotals!.expenses),
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
                  if (_showFinancialSummary)
                    Padding(
                      // Size to the status message rather than reserving a
                      // permanent blank block above Recurring Transactions.
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                      child: Text(
                        _periodError ??
                            (_periodCalculating
                                ? _periodTotals == null
                                    ? 'Calculating complete posted totals…'
                                    : 'Refreshing previously verified totals…'
                                : _lastPeriodAt == null
                                        ? 'Saved totals may be incomplete until posted history is downloaded and verified'
                                        : 'Posted totals for $_rangeLabel · verified ${DateFormat('h:mm a').format(_lastPeriodAt!)} · pending offline entries excluded'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: Color(0xFF667085),
                        ),
                      ),
                    ),
                  // Search uses the former blank area beneath the totals.
                  // A full-width input makes transaction lookup practical.
                  const SizedBox(height: 10),
                  SearchBar(
                    controller: _searchController,
                    hintText: 'Search transactions…',
                    leading: const Icon(Icons.search),
                    elevation: const WidgetStatePropertyAll<double>(3),
                    shadowColor: const WidgetStatePropertyAll<Color>(Colors.black26),
                    onChanged: _searchChanged,
                    onSubmitted: (_) => _applySearch(),
                    trailing: [
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _searchController,
                        builder: (_, value, child) =>
                            value.text.isEmpty ? const SizedBox.shrink() : child!,
                        child: IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            _applySearch();
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                  if (_owner) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _downloadingHistory
                            ? null : _downloadSavedHistory,
                        icon: _downloadingHistory
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_for_offline_outlined),
                        label: Text(_downloadingHistory
                            ? 'Saving history… $_downloadedHistoryCount records'
                            : 'Download missing history to this device'),
                      ),
                    ),
                    if (_historyRecoveryMessage != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 3, 4, 5),
                        child: Text(_historyRecoveryMessage!,
                          style: const TextStyle(fontSize: 12,
                            color: Color(0xFF526171))),
                      ),
                  ],
                  if (_searching)
                    Padding(
                      padding: const EdgeInsets.only(top: 5, left: 4),
                      child: Text(
                        _showFinancialSummary
                          ? _searchSubtotal
                          : 'Search checks saved transactions in the selected date range.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
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
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          12,
                        ),
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
                                    builder: (_) => _owner
                                        ? OfflineRecurringScreen(businessId: widget.businessId)
                                        : RecurringTransactionsScreen(businessId: widget.businessId),
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
                          'ExpenseIQ photos • Local & sync',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          12,
                        ),
                        children: [
                          Text(
                            _importing
                                ? 'Indexing locally: $_indexProcessed '
                                      'of $_indexExpected references saved'
                                : _photoQueueError != null
                                ? 'Local photo queue error: $_photoQueueError'
                                : _photoCounts == null
                                ? 'Reading local photo queue...'
                                : 'Indexed: ${_photoCounts!.indexed}  •  '
                                      'Uploaded: ${_photoCounts!.uploaded}  •  '
                                      'Waiting: ${_photoCounts!.pending}\n'
                                      'Uploading: ${_photoCounts!.uploading}  •  '
                                      'Failed: ${_photoCounts!.failed}  •  '
                                      'Unmatched: ${_photoCounts!.missing}',
                          ),
                          if (_importing && _indexExpected > 0) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _indexProcessed / _indexExpected,
                            ),
                          ],
                          const SizedBox(height: 8),
                          SwitchListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Automatic background sync'),
                            subtitle: const Text(
                              'Android uploads in small batches',
                            ),
                            value: _photoCounts?.enabled ?? true,
                            onChanged: _importing || _photoCounts == null
                                ? null
                                : _togglePhotoSync,
                          ),
                          SwitchListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Wi-Fi only'),
                            value: _photoCounts?.wifiOnly ?? true,
                            onChanged: _importing || _photoCounts == null
                                ? null
                                : _toggleWifiOnly,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _importing
                                      ? null
                                      : _importExpenseIqReceipts,
                                  icon: _importing
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.folder_outlined),
                                  label: Text(
                                    _importing
                                        ? 'Indexing...'
                                        : 'Index locally',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed:
                                      _requestingPhotoSync ||
                                          _photoCounts == null ||
                                          _photoCounts?.enabled == false ||
                                          _photoCounts?.pending == 0
                                      ? null
                                      : _requestPhotoSync,
                                  icon: const Icon(Icons.cloud_upload_outlined),
                                  label: Text(
                                    _requestingPhotoSync
                                        ? 'Scheduling...'
                                        : 'Sync now',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Leave the original ExpenseIQ folder in place. '
                            'Android may postpone background transfers to '
                            'save battery; the queue will resume later.',
                            style: TextStyle(fontSize: 12),
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
                  if (_owner)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Review payroll expenses'),
                        onPressed: () => showPayrollExpenseReview(context,
                          database: localDatabase, business: widget.businessId,
                          onReconciled: () => unawaited(_load(showLoading: false, forceTotals: true))),
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
                          color:
                              _accountFilterId != null ||
                                  _categoryFilterId != null ||
                                  _counterpartyFilterId != null
                              ? BriskersColors.invoices
                              : null,
                        ),
                      ),
                    ],
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
                  const SizedBox(height: 12),
                  if (receiptsUnverified)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        unverifiedCount == null
                  ? 'Some income receipts lack verified invoice/payment evidence. Gross amounts remain shown; processing-fee adjustments are not assumed.'
                  : '$unverifiedCount income receipt${unverifiedCount == 1 ? '' : 's'} need${unverifiedCount == 1 ? 's' : ''} verification. Gross amounts remain shown for those rows; no processing fee is assumed.',
                      ),
                    ),
                  if (_loading && visible.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Opening saved transactions on this device…'),
                      ),
                    )
                  else if (visible.isEmpty)
                     Card(
                       child: Padding(
                         padding: const EdgeInsets.all(20),
                         child: Text(_showingLocal
                             ? (_postedRangeVerified
                                 ? 'No matches. Posted history was checked for this date range.'
                                 : 'No matches in saved records. This device cannot confirm whether older records exist elsewhere.')
                             : 'No transactions in this view.'),
                       ),
                     )
                    ]),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                      final transaction = visible[index];
                      final incomeRow =
                          transaction['direction']?.toString() == 'income';
                      final payee =
                          (_owner ? _payrollDisplayNames.forExpense(transaction) : null) ??
                          transaction['counterparty']?.toString() ??
                          (incomeRow ? 'Income' : 'Expense');
                      final copyNumber = transaction['copy_number'];
                      final counterparty = copyNumber == null ? payee : '$payee (Copy $copyNumber)';
                      final category =
                          transaction['category']?.toString() ?? '';
                      final date =
                          transaction['transaction_date']?.toString() ?? '';
                      final jobNumber =
                          transaction['job_number']?.toString().trim() ?? '';
                      final jobTitle =
                          transaction['job_title']?.toString().trim() ?? '';
                      final customerName =
                          transaction['job_customer_name']?.toString().trim() ??
                          '';
                      final documentNumber =
                          transaction['document_number']?.toString().trim() ??
                          '';
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
                      final receiptCount =
                          int.tryParse(
                            transaction['receipt_count']?.toString() ?? '',
                          ) ??
                          0;
                      final invoiceReceipt = transaction['_invoice_receipt'] == true;
                      final directionColor = incomeRow
                          ? const Color(0xFF169B62)
                          : const Color(0xFFC62828);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => invoiceReceipt
                              ? _openInvoiceReceipt(transaction)
                              : _openTransaction(transaction),
                          onLongPress: invoiceReceipt
                              ? null
                              : () => _showTransactionActions(transaction),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: directionColor.withValues(
                                    alpha: 0.10,
                                  ),
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
                                      if (invoiceReceipt) Text(
                                        InvoicePaymentFeed.paymentLabel(transaction),
                                        style: TextStyle(
                                          color: InvoicePaymentFeed.paymentLabel(transaction) == 'Paid'
                                              ? const Color(0xFF168A4B)
                                              : InvoicePaymentFeed.paymentLabel(transaction) == 'Partial'
                                                ? const Color(0xFFD56D08)
                                                : const Color(0xFF64748B),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      if (!invoiceReceipt) ...[
                                        // Always show the actual saved date,
                                        // even when imported remarks exist.
                                        Text(
                                          date.isEmpty ? 'Date unavailable' : date,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        if (category.isNotEmpty)
                                          Text(
                                            category,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        if (remarks.isNotEmpty &&
                                            !remarks.startsWith('S36 Active Screen, Snap TBL-'))
                                          Text(
                                            remarks,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${incomeRow ? '+' : '-'}${_money(WarrantyReceiptReporting.amount(transaction))}',
                                      style: TextStyle(
                                        fontSize: 17.5,
                                        fontWeight: FontWeight.w900,
                                        color: directionColor,
                                      ),
                                    ),
                                    if (invoiceReceipt) ...[
                                      const SizedBox(height: 6),
                                      Tooltip(
                                        message: InvoicePaymentFeed.syncLabel(transaction),
                                        child: Stack(alignment: Alignment.center, children: [
                                        Icon(
                                          transaction['_receipt_state'] == 'posted'
                                              ? Icons.cloud : Icons.cloud_outlined,
                                          size: 32,
                                          color: transaction['_receipt_state'] == 'posted'
                                              ? const Color(0xFF169B62)
                                              : transaction['_receipt_state'] == 'pending'
                                                  ? const Color(0xFFD56D08)
                                                  : const Color(0xFF667085),
                                        ),
                                        Icon(
                                          transaction['_receipt_state'] == 'posted'
                                              ? Icons.check
                                              : transaction['_receipt_state'] == 'pending'
                                                  ? Icons.schedule
                                                  : Icons.priority_high,
                                          size: 17,
                                          color: transaction['_receipt_state'] == 'posted'
                                              ? Colors.white
                                              : transaction['_receipt_state'] == 'pending'
                                                  ? const Color(0xFFD56D08)
                                                  : const Color(0xFF667085),
                                        ),
                                      ]),
                                      ),
                                    ],
                                    if (!invoiceReceipt) ...[
                                      const SizedBox(height: 6),
                                      Builder(builder: (context) {
                                        final state = transaction['sync_state']
                                            ?.toString().toLowerCase() ?? '';
                                        final pending = state == 'pending' ||
                                            state == 'pending_sync' ||
                                            state == 'queued';
                                        final failed = state == 'error' ||
                                            state == 'failed' ||
                                            state == 'conflict';
                                        // Do not infer transaction sync from
                                        // the list switching cache -> server.
                                        // An unreported state stays unknown.
                                        final verifiedId =
                                            transaction['id']?.toString() ?? '';
                                        final previouslyConfirmed =
                                            verifiedId.isNotEmpty &&
                                            _previousServerTransactionProofs[
                                              verifiedId] ==
                                            LocalFinancialCache
                                                .serverTransactionSignature(
                                                  transaction);
                                        final currentConfirmed =
                                            _serverConfirmedTransactionIds
                                                .contains(verifiedId);
                                        final synced = state == 'synced' ||
                                            (!pending && !failed &&
                                                verifiedId.isNotEmpty &&
                                                (currentConfirmed ||
                                                    previouslyConfirmed));
                                        return Tooltip(
                                          message: failed
                                              ? 'Transaction sync needs attention'
                                              : pending
                                                  ? 'Transaction awaiting sync'
                                                  : currentConfirmed || state == 'synced'
                                                      ? 'Transaction confirmed in shop database'
                                                      : previouslyConfirmed
                                                          ? 'Previously confirmed on server; refresh to recheck'
                                                          : 'Transaction sync not verified',
                                          child: Icon(
                                            failed
                                                ? Icons.cloud_off_outlined
                                                : pending
                                                    ? Icons.cloud_upload_outlined
                                                    : synced
                                                        ? Icons.cloud_done
                                                        : Icons.cloud_outlined,
                                            color: failed
                                                ? const Color(0xFFC62828)
                                                : synced
                                                    ? const Color(0xFF169B62)
                                                    : const Color(0xFF667085),
                                            size: 26,
                                          ),
                                        );
                                      }),
                                    ],
                                    if (!invoiceReceipt && (num.tryParse(
                                              transaction['reporting_processor_fee']
                                                      ?.toString() ??
                                                  '',
                                            ) ??
                                            0) >
                                        0)
                                      Text(
                                        'Net · fee ${_money(transaction['reporting_processor_fee'])}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    if (!invoiceReceipt && incomeRow &&
                                        transaction['reporting_status'] !=
                                            'verified')
                                      const Text(
                                        'Gross · fee unverified',
                                        style: TextStyle(fontSize: 11),
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
                                if (!invoiceReceipt) ...[
                                  const SizedBox(height: 3),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      tr('longPressForOptions'),
                                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                      },
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    sliver: SliverList.list(children: [
                  if (_loadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (!_hasMore && !moreReceiptPages && visible.isNotEmpty)
                     Padding(
                       padding: const EdgeInsets.symmetric(vertical: 12),
                       child: Center(
                         child: Text(
                           _showingLocal
                               ? (_postedRangeVerified
                                   ? 'End of verified posted history for this date range.'
                                   : 'End of saved records. Older history has not been verified on this device.')
                               : 'No more transactions',
                           textAlign: TextAlign.center,
                           style: const TextStyle(color: Color(0xFF667085)),
                         ),
                       ),
                     ),
                    ]),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ActionSectionLabel extends StatelessWidget {
  const _ActionSectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
    child: Align(alignment: Alignment.centerLeft,
      child: Text(label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.8, fontWeight: FontWeight.w700))),
  );
}

