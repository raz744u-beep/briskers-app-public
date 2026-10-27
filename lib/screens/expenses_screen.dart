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
import '../services/briskers_api.dart';
import '../services/warranty_receipt_reporting.dart';
import '../services/local_financial_cache.dart';
import '../services/invoice_payment_feed.dart';
import '../services/expenses_period_totals.dart';
import '../services/verified_expense_totals_cache.dart';
import '../services/local_financial_totals_journal.dart';
import '../services/expenseiq_local_photo_sync.dart';
import '../services/expenseiq_background_scheduler.dart';
import '../widgets/briskers_page_header.dart';
import 'expenses/expense_detail_screen.dart';
import 'jobs/job_document_screen.dart';
import 'expenses/expense_entry_screen.dart';
import 'settings/expense_settings_screen.dart';

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
    _load();
    _refreshPhotoCounts();
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
      ++_periodEpoch;
      _pendingPeriodScope = null;
      _periodTotals = null;
      _serverPeriodBase = null;
      _lastPeriodScope = null;
      _lastPeriodAt = null;
      _periodCalculating = false;
      _periodError = null;
      _serverConfirmedTransactionIds.clear();
      _previousServerTransactionProofs = {};
      _transactionRefreshFailed = false;
      _serverConfirmedBusinessId = null;
    }
    if (oldWidget.dockResetToken != widget.dockResetToken) {
      _searchDebounce?.cancel();
      _filter = 'all';
      _dateRange = '30d';
      _customStartDate = null;
      _customEndDate = null;
      _accountFilterId = null;
      _categoryFilterId = null;
      _counterpartyFilterId = null;
      _searchController.clear();
      _visibleCount = _pageSize;
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
    final count = InvoicePaymentFeed.combine(
      financial: _transactions, receipts: _invoiceReceipts,
      startDate: _rangeStartDate, endDate: _rangeEndDate,
      search: _searchController.text,
      direction: _filter == 'all' ? null : _filter,
      filteredAccount: _accountFilterId != null ||
          _categoryFilterId != null || _counterpartyFilterId != null,
    ).length;
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

  DateTime? get _rangeStartDate {
    if (_searchController.text.trim().isNotEmpty) return null;
    final today = _dateOnly(DateTime.now());
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
    if (_dateRange == 'lastMonth') {
      final today = _dateOnly(DateTime.now());
      return DateTime(today.year, today.month, 0);
    }
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
        return 'All history';
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

  Future<void> _prefetchReceiptDetails(
    List<Map<String, dynamic>> snapshot,
  ) async {
    // A large imported history may have thousands of receipts. Do not start
    // hundreds of photo downloads every time the user opens Expenses.
    // Download a small number of missing detail *metadata* in foreground;
    // charging/Wi-Fi WorkManager separately mirrors their photo files.
    final rows = snapshot.where((row) {
      final count = int.tryParse(row['receipt_count']?.toString() ?? '') ?? 0;
      return count > 0 &&
          (row['id']?.toString() ?? '').isNotEmpty &&
          !row['id'].toString().startsWith('local-') &&
          row['sync_state'] != 'pending' &&
          row['sync_state'] != 'conflict';
    }).take(8).toList();

    for (final row in rows) {
      final id = row['id'].toString();
      try {
        if (await _localFinancial.loadTransactionDetail(
            widget.businessId, id) != null) {
          continue;
        }
        final detail = await _api.transactionDetail(widget.businessId, id);
        if (detail['id']?.toString() != id) continue;
        // Recheck before writing so a locally edited expense detail cannot be
        // replaced by the outcome of an older in-flight download.
        if (await _localFinancial.loadTransactionDetail(
            widget.businessId, id) == null) {
          await _localFinancial.saveTransactionDetail(
              widget.businessId, id, detail);
        }
      } catch (_) {
        // Saved transactions stay usable if metadata prefetch fails.
      }
    }
  }

  Future<void> _load({
    bool showLoading = true,
    bool refreshReceipts = false,
    bool forceTotals = false,
  }) async {
    final epoch = ++_loadEpoch;
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

    // Cached financial rows paint quickly. Restore separately persisted,
    // previously authenticated server evidence before those rows render.
    // Absence of a proof remains an unknown gray cloud, never a green guess.
    try {
      final proofs = await _localFinancial.loadServerConfirmedTransactions(
        businessId,
      );
      if (_isCurrentLoad(epoch, businessId)) {
        setState(() => _previousServerTransactionProofs = proofs);
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
          _invoiceReceipts = _invoiceReceipts.isEmpty
              ? receipts
              : InvoicePaymentFeed.mergeReceipts(_invoiceReceipts, receipts);
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
    final forceOnline = BriskersConnectionModeController.instance.forceOnline;

    if (!forceOnline) {
      try {
        var localRows = await _localFinancial.loadTransactions(
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
        // The first offline frame displays at most 50 transactions.
        // Enrich only those rows. Enriching the entire ~1,000-row snapshot
        // first can delay the page and unnecessarily process many receipts.
        final hasMoreLocal = localRows.length > _pageSize;
        // Display cached transactions immediately; full processor-fee
        // verification is asynchronous and scoped to this navigation epoch.
        localRows = localRows.take(_pageSize).map(
          WarrantyReceiptReporting.unverified).toList();
        final localOptions = await _localFinancial.loadOptions(
          widget.businessId,
        );

        if (_isCurrentLoad(epoch, businessId) &&
            (localRows.isNotEmpty || localOptions.isNotEmpty)) {
          setState(() {
            _transactions = localRows.take(_pageSize).toList();
            _hasMore = hasMoreLocal;
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
          _hasMore = false;
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
      if (!_isCurrentLoad(epoch, businessId)) return;
      setState(() {
        _serverConfirmedTransactionIds.addAll(
          rows.map((row) => row['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty),
        );
        // Retain locally committed, not-yet-synced financial entries if
        // the authenticated server's first page has not received them.
        // Identity-scoped replacement avoids duplicate list cards.
        final localPending = {
          for (final row in _transactions)
            if (row['sync_state']?.toString() == 'pending')
              row['id']?.toString(): row,
        };
        final seen = <String>{};
        _transactions = [
          for (final row in rows)
            if (seen.add(row['id']?.toString() ?? ''))
              localPending[row['id']?.toString()] ?? row,
          for (final entry in localPending.entries)
            if (!seen.contains(entry.key)) entry.value,
        ];
        _hasMore = rows.length == _pageSize;
        _loading = false;
        _showingLocal = false;
        _transactionRefreshFailed = false;
        _error = null;
      });
      unawaited(_enrichVisiblePage(epoch, businessId, rows));
      // Only the successful authenticated server response can add durable
      // proof. Saving this first page makes a later app restart stable even
      // if the optional 1,000-row history download does not finish.
      unawaited(_localFinancial.saveServerConfirmedTransactions(
        businessId, rows,
      ).catchError((Object _) {}));
      // Options and the complete offline cache are not prerequisites for
      // showing a transaction or an invoice payment in Expenses & Income.
      unawaited(_hydrateFinancialHistory(epoch, businessId, rows));
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
    final search = _searchController.text.trim();
    final direction = _filter == 'all' ? null : _filter;
    final accountId = _accountFilterId;
    final categoryId = _categoryFilterId;
    final counterpartyId = _counterpartyFilterId;
    final scope = [
      businessId,
      widget.roleCode,
      startDate?.toIso8601String() ?? '',
      endDate?.toIso8601String() ?? '',
      search,
      direction ?? '',
      accountId ?? '',
      categoryId ?? '',
      counterpartyId ?? '',
    ].join('|');
    // Restore complete stored totals and add all locally committed deltas.
    // The server is NOT a prerequisite for entering the Expenses screen.
    if (_pendingPeriodScope == scope) return;
    final epoch = ++_periodEpoch;
    final journal = LocalFinancialTotalsJournal();
    _pendingPeriodScope = scope;
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
    int localChanges = 0;
    try {
      local = baseline == null ? null : await journal.apply(
        businessId, baseline,
        startDate: startDate, endDate: endDate,
        search: search.isEmpty ? null : search, direction: direction,
        accountId: accountId, categoryId: categoryId,
        counterpartyId: counterpartyId,
      );
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
    final fresh = !rolloverPending && !needsDailySeed && lastVerified != null &&
        DateTime.now().difference(lastVerified) < const Duration(minutes: 30);
    setState(() {
      _serverPeriodBase = baseline;
      _periodTotals = local;
      _lastPeriodScope = scope;
      _lastPeriodAt = lastVerified;
      _periodCalculating = false;
      _periodError = local == null
          ? (offline ? 'Complete baseline not yet saved on this device.'
              : 'Preparing first complete local baseline…')
          : rolloverPending
              ? 'Saved local totals through ${DateFormat('MMM d').format(rolling.verifiedThrough)} · today not yet verified'
              : localChanges > 0
                  ? 'Includes $localChanges locally saved change(s) · sync pending'
                  : offline
                      ? 'Offline · saved totals verified ${DateFormat('MMM d, h:mm a').format(lastVerified!)}'
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
      final completeRows = <Map<String, dynamic>>[];
      final totals = await ExpensesPeriodTotals.calculate(
        isCurrent: current,
        readPage: (offset, limit) async {
          final rows = await _api.transactionsPaged(
            businessId,
            offset: offset, limit: limit,
            startDate: startDate, endDate: endDate,
            search: search.isEmpty ? null : search,
            direction: direction,
            accountId: accountId,
            categoryId: categoryId,
            counterpartyId: counterpartyId,
          );
          completeRows.addAll(rows);
          return rows;
        },
        enrichPage: (rows) => const WarrantyReceiptReporting().enrich(
          businessId, rows, refresh: false,
        ),
      );
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
        search: search.isEmpty ? null : search, direction: direction,
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

  Future<void> _hydrateFinancialHistory(
    int epoch,
    String businessId,
    List<Map<String, dynamic>> firstPage,
  ) async {
    try {
      final results = await Future.wait<dynamic>([
        _api.transactionOptions(businessId),
        _api.transactions(businessId, limit: 1000),
      ]);
      if (!_isCurrentLoad(epoch, businessId) ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }
      final options = Map<String, dynamic>.from(results[0] as Map);
      final verified = {for (final row in firstPage)
        row['id']?.toString(): row};
      final snapshot = List<Map<String, dynamic>>.from(results[1] as List)
          .map((row) => verified[row['id']?.toString()] ?? row)
          .toList();
      setState(() {
        _serverConfirmedTransactionIds.addAll(
          snapshot.map((row) => row['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty),
        );
        _quickTemplates = List<dynamic>.from(
          options['quick_templates'] ?? const [],
        ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
        _accounts = List<dynamic>.from(options['accounts'] ?? const [])
            .map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
        _categories = List<dynamic>.from(options['categories'] ?? const [])
            .map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
        _counterparties = List<dynamic>.from(
          options['counterparties'] ?? const [],
        ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
      });
      // The offline cache remains durable, but does not block first paint.
      await _localFinancial.mergeServerTransactions(businessId, snapshot);
      await _localFinancial.saveServerConfirmedTransactions(
        businessId, snapshot,
      );
      if (!_isCurrentLoad(epoch, businessId)) return;
      await _localFinancial.saveOptions(businessId, options);
      if (_isCurrentLoad(epoch, businessId)) {
        unawaited(_prefetchReceiptDetails(snapshot));
      }
    } catch (_) {
      // Keep already visible authoritative rows, receipts and cached options.
    }
  }

  Future<void> _recoverCachedInvoiceReceipts() async {
    if (_recoveringCachedReceipts) return;
    _recoveringCachedReceipts = true;
    try {
      final rows =
          await _invoiceFeed.pendingFromCachedInvoices(widget.businessId);
      if (!mounted || rows.isEmpty) return;
      setState(() => _invoiceReceipts = InvoicePaymentFeed.mergeReceipts(
        rows, _invoiceReceipts,
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
      const pageSize = 250;
      final rows = <Map<String, dynamic>>[];
      var exhausted = false;
      // Never replace the saved receipt inventory with a truncated response.
      for (var offset = 0; offset < 20000; offset += pageSize) {
        if (!_isCurrentReceipt(epoch, businessId) ||
            BriskersConnectionModeController.instance.forceOffline) {
          return;
        }
        final page = await _api.invoiceReceipts(
          businessId, limit: pageSize, offset: offset,
        );
        if (!_isCurrentReceipt(epoch, businessId)) return;
        rows.addAll(page);
        if (offset == 0) {
          // Show the latest server payments after the first short page;
          // continue filling the historical offline snapshot in background.
          setState(() {
            _invoiceReceipts = InvoicePaymentFeed.reconcileOnlineFirstPage(
              page, _invoiceReceipts,
            );
            if (_invoiceReceipts.isNotEmpty) _loading = false;
          });
        }
        if (page.length < pageSize) {
          exhausted = true;
          break;
        }
      }
      if (!exhausted ||
          !_isCurrentReceipt(epoch, businessId) ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }
      await _invoiceFeed.saveServerReceipts(businessId, rows);
      if (!_isCurrentReceipt(epoch, businessId)) return;
      final merged = await _invoiceFeed.load(businessId);
      if (_isCurrentReceipt(epoch, businessId)) {
        setState(() => _invoiceReceipts = merged);
      }
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
    if (_showingLocal || _loading || _loadingMore || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final rows = await _fetchTransactions(offset: _transactions.length);
      if (!mounted) return;
      setState(() {
        _serverConfirmedTransactionIds.addAll(
          rows.map((row) => row['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty),
        );
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
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _load(showLoading: false);
    });
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
                trailing: _filter == option.$1 ? const Icon(Icons.check) : null,
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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
            for (final option in const [
              ('30d', 'Last 30 days'),
              ('60d', 'Last 60 days'),
              ('90d', 'Last 90 days'),
              ('thisMonth', 'This Month'),
              ('lastMonth', 'Last Month'),
              ('3m', 'Last 3 Months'),
              ('6m', 'Last 6 months'),
              ('ytd', 'Year to Date'),
              ('1y', 'Last 1 year'),
              ('custom', 'Custom date range'),
              ('all', 'All history'),
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
    if (selected == null) return;

    if (selected == 'custom') {
      if (!mounted) return;
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 10),
        lastDate: now,
        initialDateRange: _customStartDate != null && _customEndDate != null
            ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
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
    if (changed == true && mounted) await _load(forceTotals: true);
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
    if (changed == true && mounted) await _load(forceTotals: true);
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

    final editable = _showingLocal ? true : detail['editable'] == true;
    final deletable = !_showingLocal && _owner && detail['deletable'] == true;

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

  @override
  Widget build(BuildContext context) {
    final allVisible = InvoicePaymentFeed.combine(
      financial: _transactions,
      receipts: _invoiceReceipts,
      startDate: _rangeStartDate,
      endDate: _rangeEndDate,
      search: _searchController.text,
      direction: _filter == 'all' ? null : _filter,
      filteredAccount: _accountFilterId != null ||
          _categoryFilterId != null || _counterpartyFilterId != null,
    );
    final visible = allVisible.take(_visibleCount).toList();
    final moreReceiptPages = allVisible.length > _visibleCount;
    final receiptsUnverified = _periodTotals?.feesUnverified == true;
    final unverifiedCount = _periodTotals?.unverifiedIncomeReceipts;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              toolbarHeight: 68,
              backgroundColor:
                  const Color(0xFFC62828).withValues(alpha: 0.08),
              title: BriskersPageTitle(
                  title: tr('expensesIncome'), logoHeight: 40),
            )
          : null,
      floatingActionButton: MediaQuery.viewInsetsOf(context).bottom == 0
          ? FloatingActionButton.extended(
              heroTag: 'expenses-quick-create',
              tooltip: 'Add transaction',
              onPressed: _importing || _loading ? null : _showAddMenu,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              backgroundColor: BriskersColors.expenses,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(forceTotals: true),
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                children: [
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
                    SizedBox(
                      // The accounting truth may arrive after the first local
                      // frame or after returning from a transaction. Reserve
                      // the same space for pending/verified/error states so
                      // rows below never jump when status text changes.
                      height: 54,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                        _periodError ??
                            (_periodCalculating
                                ? _periodTotals == null
                                    ? 'Calculating complete posted totals…'
                                    : 'Refreshing previously verified totals…'
                                : _searchController.text.trim().isNotEmpty
                                    ? 'Search totals include all dates.'
                                    : _lastPeriodAt == null
                                        ? 'Complete posted totals · pending offline entries excluded'
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SearchBar(
                          controller: _searchController,
                          hintText: 'Search transactions…',
                          leading: const Icon(Icons.search),
                          elevation: const WidgetStatePropertyAll<double>(3),
                          shadowColor: const WidgetStatePropertyAll<Color>(
                            Colors.black26,
                          ),
                          onChanged: (value) {
                            setState(() {});
                            _searchChanged(value);
                          },
                          onSubmitted: (_) {
                            _searchDebounce?.cancel();
                            _load(showLoading: false);
                          },
                          trailing: [
                            if (_searchController.text.isNotEmpty)
                              IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchDebounce?.cancel();
                                  _searchController.clear();
                                  setState(() {});
                                  _load(showLoading: false);
                                },
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        ),
                      ),

                    ],
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
                            child: Row(
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
                                        transaction['_receipt_state'] != 'posted'
                                            ? 'Recorded • awaiting finalization'
                                            : transaction['_payment_coverage'] == 'paid'
                                                ? 'Paid' : 'Partial',
                                        style: TextStyle(
                                          color: transaction['_receipt_state'] == 'posted' &&
                                                  transaction['_payment_coverage'] == 'paid'
                                              ? const Color(0xFF168A4B)
                                              : const Color(0xFFD56D08),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      if (!invoiceReceipt) Text(
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
                                      '${incomeRow ? '+' : '-'}${_money(WarrantyReceiptReporting.amount(transaction))}',
                                      style: TextStyle(
                                        fontSize: 17.5,
                                        fontWeight: FontWeight.w900,
                                        color: directionColor,
                                      ),
                                    ),
                                    if (invoiceReceipt) ...[
                                      const SizedBox(height: 6),
                                      Stack(alignment: Alignment.center, children: [
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
                          ),
                        ),
                      );
                    }),
                  if (_loadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (!_hasMore && !moreReceiptPages && visible.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text(
                          'No more transactions',
                          style: TextStyle(color: Color(0xFF667085)),
                        ),
                      ),
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
