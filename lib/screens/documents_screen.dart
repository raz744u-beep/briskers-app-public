import 'dart:async';

import 'package:flutter/material.dart' hide showDialog, showModalBottomSheet;

import '../core/module_modal_theme.dart';

import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/connection_mode.dart';
import '../core/invoice_status_style.dart';
import '../core/briskers_i18n.dart';
import '../core/document_search.dart';
import '../core/document_list_refresh.dart';
import '../core/navigation_content_timing.dart';
import '../core/document_future_date.dart';
import '../core/document_presentation.dart';
import '../core/estimate_list_description.dart';
import '../services/briskers_api.dart';
import '../services/invoice_payment_feed.dart';
import '../services/local_job_retirement.dart';
import '../local/local_database_provider.dart';
import '../services/local_financial_cache.dart';
import '../services/local_document_repository.dart';
import '../services/local_document_detail_cache.dart';
import '../services/verified_invoice_close_events.dart';
import '../services/offline_document_draft_service.dart';
import '../services/local_invoice_status_styles_cache.dart';
import '../services/invoice_finalization_guard.dart';
import '../widgets/briskers_page_header.dart';
import '../widgets/connection_header_toggle.dart';
import '../widgets/stale_keyboard_inset_guard.dart';
import 'jobs/blank_invoice_setup_screen.dart';
import 'shell_screen.dart';
import 'jobs/job_document_screen.dart';
import 'jobs/invoice_deletion_choice.dart';
import 'expenses/expense_detail_screen.dart';

/// Stable, language-independent values shared by filters, counts and cards.
/// Estimate statuses retain their independent workflow and display names.
String documentListStage(Map<String, dynamic> row, {required bool estimate}) {
  if (estimate) return row['display_status']?.toString() ?? '';
  final presentation = DocumentPresentation({...row, 'kind': 'invoice'});
  switch (presentation.statusCode) {
    case 'closed':
      return 'Closed';
    case 'pending_close':
      return 'Pending Close';
    case 'reopened':
      return 'Reopened';
    case 'void':
      return 'Void';
    default:
      return 'Open';
  }
}

/// The confirmed document lifecycle state outranks a stale receipt index.
/// For an unclosed invoice, retain the existing receipt-based Open/Pending
/// Close distinction without ever inventing Closed.
String invoiceListStageWithReceipts(
  Map<String, dynamic> row, {
  required num receipts,
}) {
  final existing = documentListStage(row, estimate: false);
  if (const {'Closed', 'Void', 'Reopened'}.contains(existing)) {
    return existing;
  }
  if (invoiceNeedsPayment(row, receipts: receipts)) {
    return 'Open';
  }
  return existing == 'Open' ? 'Pending Close' : existing;
}

const invoiceListStatusFilters = [
  'Open',
  'Pending Close',
  'Closed',
  'Reopened',
  'Void',
];
const estimateListStatusFilters = [
  'Open',
  'Draft',
  'Issued',
  'Accepted',
  'Declined',
  'Expired',
  'Void',
];

/// The local index supplies placeholder zeroes, not payment aggregates. Keep
/// unavailable financial details unknown so they cannot contradict a server
/// display hint or be mistaken for a verified outstanding balance.
Map<String, dynamic> documentListIndexPresentation(Map<String, dynamic> row) {
  final result = Map<String, dynamic>.from(row);
  if (row['_local_snapshot'] == true) {
    result.remove('paid_amount');
    result.remove('pending_payment');
  }
  return result;
}

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    required this.businessId,
    required this.kind,
    required this.isOwner,
    this.canManageExpenses = false,
    this.showAppBar = true,
    this.businessName = 'Briskers',
    required this.roleCode,
    this.onPrimaryDestinationSelected,
    this.sharedBottomNavigationBar,
    this.detailBottomNavigationBar,
    this.customerId,
    this.customerName,
    this.customerVehicles = const [],
    this.dockDefaultsToOpen = false,
    this.dockResetToken = 0,
    this.localDocuments,
    this.paymentFeed,
    this.api,
    this.blockedDocumentIds,
  });

  final LocalDocumentRepository? localDocuments;
  final InvoicePaymentFeed? paymentFeed;
  final BriskersApi? api;
  final Future<Set<String>> Function(String businessId)? blockedDocumentIds;
  final bool dockDefaultsToOpen;
  final int dockResetToken;
  final String? customerId;
  final String? customerName;
  final List<dynamic> customerVehicles;
  final bool showAppBar;
  final String businessName;
  final String roleCode;
  final ValueChanged<int>? onPrimaryDestinationSelected;
  final Widget? sharedBottomNavigationBar;
  /// Navigation dock for pushed invoice/estimate detail routes only.
  /// Avoids duplicating the parent Shell dock on the document list.
  final Widget? detailBottomNavigationBar;
  final String businessId;
  final String kind;
  final bool isOwner;
  final bool canManageExpenses;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen>
    with ModuleModalState<DocumentsScreen> {
  @override
  Color get modalAccent =>
      _estimate ? BriskersColors.estimates : BriskersColors.invoices;
  late final BriskersApi _api = widget.api ?? const BriskersApi();
  late final LocalDocumentRepository _localDocuments =
      widget.localDocuments ?? LocalDocumentRepository();
  final LocalDocumentDetailCache _localDetailCache = const LocalDocumentDetailCache();
  late final OfflineDocumentDraftService _offlineDrafts =
      OfflineDocumentDraftService();
  final LocalInvoiceStatusStylesCache _localInvoiceStyles =
      LocalInvoiceStatusStylesCache();
  static final Map<String, List<Map<String, dynamic>>> _styleCache = {};
  late final InvoiceFinalizationGuard _finalizationGuard =
      InvoiceFinalizationGuard();

  List<Map<String, dynamic>>? _rows;
  // Keep authoritative snapshots separate from local description enrichment.
  // A warm refresh need not rewrite the complete SQLite index.
  List<Map<String, dynamic>>? _serverRows;
  List<Map<String, dynamic>>? _indexRows;
  List<Map<String, dynamic>>? _savedRows;
  List<Map<String, dynamic>>? _orderedSource;
  List<Map<String, dynamic>> _orderedRows = const [];
  bool? _orderedEstimate;
  final DocumentListRefresh _refresh = DocumentListRefresh();
  int _loadEpoch = 0;
  int _descriptionEpoch = 0;
  int _receiptEpoch = 0;
  StreamSubscription<({String businessId, Set<String> jobIds})>? _retirement;
  StreamSubscription<VerifiedInvoiceClosed>? _invoiceCloseEvents;
  List<Map<String, dynamic>> _invoiceStyles = const [];
  String? _selectedStatus;
  Map<String, num> _receiptTotals = const {};
  late final InvoicePaymentFeed _paymentFeed =
      widget.paymentFeed ?? InvoicePaymentFeed();
  bool _futureDatedOnly = false;
  String? _error;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'document-search');

  bool get _estimate => widget.kind == 'estimate';

  String _invoiceStage(Map<String, dynamic> row) {
    if (_estimate) {
      return documentListStage(row, estimate: true);
    }
    return invoiceListStageWithReceipts(
      row, receipts: _receiptTotals[row['id']?.toString()] ?? 0,
    );
  }

  bool _matchesStatus(Map<String, dynamic> row, String status) {
    if (_estimate && status == 'Open') {
      final raw = row['status']?.toString().toLowerCase() ?? '';
      return row['converted'] != true &&
          !const {'accepted','declined','expired','void'}.contains(raw);
    }
    return _invoiceStage(row) == status;
  }

  Future<void> _refreshReceiptTotals(
    int epoch,
    String businessId, {
    required bool estimate,
  }) async {
    if (estimate) return;
    final receiptEpoch = ++_receiptEpoch;
    try {
      final receipts = await _paymentFeed.load(businessId);
      if (!mounted || epoch != _loadEpoch || receiptEpoch != _receiptEpoch) {
        return;
      }
      final totals = invoiceRecordedReceiptTotals(receipts);
      if (!documentListDataEquals(_receiptTotals, totals)) {
        setState(() => _receiptTotals = totals);
      }
    } catch (_) {
      // Unknown payment data never fabricates a fully paid state.
    }
  }


  List<String> get _statuses =>
      _estimate ? estimateListStatusFilters : invoiceListStatusFilters;

  String get _title => _estimate ? tr('estimates') : tr('invoices');

  String _localizedStatusLabel(String status) {
    switch (status) {
      case 'Open':
        return tr('invoiceOpen');
      case 'Pending Close':
        return tr('invoicePendingClose');
      case 'Paid':
        return tr('invoicePaid');
      case 'Closed':
        return tr('invoiceClosed');
      case 'Reopened':
        return 'Reopened';
      case 'Partial':
        return tr('invoicePartial');
      case 'Draft':
        return tr('documentDraft');
      case 'Issued':
        return tr('documentIssued');
      case 'Accepted':
        return tr('documentAccepted');
      case 'Declined':
        return tr('documentDeclined');
      case 'Expired':
        return tr('documentExpired');
      case 'Void':
        return tr('documentVoid');
      default:
        return status;
    }
  }

  Map<String, dynamic>? _invoiceStyleByName(String status) {
    for (final item in _invoiceStyles) {
      if (item['name']?.toString() == status) return item;
    }
    return null;
  }

  Color _statusColor(String status) {
    if (!_estimate && const {'Open', 'Pending Close', 'Closed', 'Reopened'}.contains(status)) {
      return invoiceStatusDefaultColor(status);
    }
    if (!_estimate) {
      final style = _invoiceStyleByName(status);
      if (style != null) {
        return invoiceStatusColorFromHex(
          style['color_hex']?.toString(),
          fallback: invoiceStatusDefaultColor(status),
        );
      }
      return invoiceStatusDefaultColor(status);
    }

    switch (status) {
      case 'Accepted':
        return const Color(0xFF169B62);
      case 'Issued':
        return const Color(0xFF1976D2);
      case 'Declined':
      case 'Expired':
      case 'Void':
        return const Color(0xFFC62828);
      case 'Draft':
        return const Color(0xFF667085);
      default:
        return _estimate ? BriskersColors.estimates : BriskersColors.invoices;
    }
  }

  IconData _statusIcon(String status) {
    if (!_estimate) {
      final style = _invoiceStyleByName(status);
      if (style != null) {
        return invoiceStatusIcon(style['icon_key']?.toString());
      }
      return invoiceStatusDefaultIcon(status);
    }
    return Icons.circle;
  }

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.dockDefaultsToOpen ? 'Open' : null;
    final cachedStyles = _styleCache[widget.businessId];
    if (!_estimate && cachedStyles != null) {
      _invoiceStyles = List<Map<String, dynamic>>.from(cachedStyles);
    }
    if (!_estimate) {
      _invoiceCloseEvents = VerifiedInvoiceCloseEvents.changes.listen((event) {
        if (!mounted || event.businessId != widget.businessId) return;
        // Do not create a card for a different customer or a hidden invoice:
        // patch only the matching existing row. Preserve all amount/receipt
        // fields, and invalidate any remote read begun before this closure.
        Map<String, dynamic> markClosed(Map<String, dynamic> row) =>
            row['id']?.toString() == event.invoiceId
                ? <String, dynamic>{
                    ...row,
                    'status': 'closed',
                    'display_status_code': 'closed',
                  }
                : row;
        if (_rows == null ||
            !_rows!.any((row) => row['id']?.toString() == event.invoiceId)) {
          return;
        }
        ++_loadEpoch;
        setState(() {
          _rows = _rows!.map(markClosed).toList();
          if (_serverRows != null) {
            _serverRows = _serverRows!.map(markClosed).toList();
          }
          if (_indexRows != null) {
            _indexRows = _indexRows!.map(markClosed).toList();
          }
          _orderedSource = null;
          _descriptionEpoch++;
        });
        // Refresh in the background, without gating the Closed pill. A
        // pre-closure HTTP response is already invalidated by the epoch.
        unawaited(_load());
      });
    }
    _retirement = LocalJobRetirement.events.listen((event) {
      if (event.businessId == widget.businessId && mounted) {
        // Hide known retired jobs immediately, even when a pre-retirement
        // network request is still pending or its replacement will fail.
        if (!_estimate && _rows != null) {
          setState(() {
            _rows = _rows!.where((row) =>
                !event.jobIds.contains(row['job_id']?.toString())).toList();
            _serverRows = null;
            _indexRows = null;
            _descriptionEpoch++;
          });
        }
        unawaited(_load());
        // The repository also enforces exact invoice tombstones (including
        // stale reassignment rows). Do not wait for the serialized network
        // request before applying that durable visibility fence.
        unawaited(_loadLocalRows(
          _loadEpoch, widget.businessId, widget.kind, estimate: _estimate,
        ));
      }
    });
    BriskersConnectionModeController.instance.addListener(_connectionChanged);
    unawaited(_load(freshAfterCurrent: false));
  }

  void _connectionChanged() {
    if (!mounted) return;
    unawaited(_load());
    if (BriskersConnectionModeController.instance.forceOffline) {
      // A stalled remote read must not delay switching to usable offline
      // content. Its epoch has already been invalidated by _load above.
      final epoch = _loadEpoch;
      unawaited(_loadLocalRows(
        epoch, widget.businessId, widget.kind, estimate: _estimate,
      ));
      unawaited(_refreshReceiptTotals(
        epoch, widget.businessId, estimate: _estimate,
      ));
    }
  }

  @override
  void didUpdateWidget(covariant DocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.kind != widget.kind) {
      _rows = null;
      _descriptionEpoch++;
      _serverRows = null;
      _indexRows = null;
      _savedRows = null;
      _receiptTotals = const {};
      _selectedStatus = widget.dockDefaultsToOpen ? 'Open' : null;
      _futureDatedOnly = false;
      _search.clear();
      _invoiceStyles = const [];
      _error = null;
      unawaited(_load());
    } else if (oldWidget.dockResetToken != widget.dockResetToken) {
      // The Shell retains this page. Returning to it checks freshness without
      // discarding the user's status, search, or scroll position. Edits may
      // have happened in another module after an existing read started.
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    BriskersConnectionModeController.instance.removeListener(_connectionChanged);
    _retirement?.cancel();
    _invoiceCloseEvents?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // Populate visible estimates from their existing local details, not a full
  // historical scan. This is read-only and runs after the list first paints.
  Future<void> _enrichEstimateDescriptions(
    int epoch, List<Map<String, dynamic>> snapshot,
  ) async {
    if (!_estimate) return;
    final shown = _selectedStatus == null ? snapshot
        : snapshot.where((row) => _matchesStatus(row, _selectedStatus!)).toList();
    final summaries = <String, String>{};
    for (final row in shown.take(75)) {
      if (!mounted || epoch != _descriptionEpoch) return;
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final indexed = estimateListDescription(row);
      if (indexed.isNotEmpty) {
        summaries[id] = indexed;
        continue;
      }
      try {
        final detail = await _localDetailCache.load(widget.businessId, id);
        if (detail == null) continue;
        final summary = estimateListDescription(row, detail: detail);
        if (summary.isNotEmpty) summaries[id] = summary;
      } catch (_) {
        // Missing detail must not block opening Estimates.
      }
    }
    if (!mounted || epoch != _descriptionEpoch || summaries.isEmpty) return;
    setState(() {
      _rows = [
        for (final row in _rows ?? <Map<String, dynamic>>[])
          if (summaries.containsKey(row['id']?.toString()))
            {...row, '_estimate_list_description': summaries[row['id']?.toString()]}
          else
            row,
      ];
    });
  }

  Future<void> _load({bool freshAfterCurrent = true}) {
    if (freshAfterCurrent) {
      // Manual refresh and return from a mutation/detail must supersede a
      // request that started before that action, even if it is still running.
      _loadEpoch++;
    }
    return _refresh.run(_loadOnce, afterCurrent: freshAfterCurrent);
  }

  Future<void> _loadOnce() async {
    if (!mounted) return;
    final epoch = ++_loadEpoch;
    final businessId = widget.businessId;
    final kind = widget.kind;
    final estimate = _estimate;
    final receipts = _refreshReceiptTotals(
      epoch,
      businessId,
      estimate: estimate,
    );
    try {
      await _loadRows(epoch, businessId, kind, estimate: estimate);
    } finally {
      // Receipt work participates in coalescing and cannot outlive the pass
      // that promises fresh status/payment state to the caller.
      await receipts;
    }
  }

  Future<void> _loadRows(
    int epoch,
    String businessId,
    String kind, {
    required bool estimate,
  }) async {
    var localShown = false;
    final forceOnline = BriskersConnectionModeController.instance.forceOnline;
    final forceOffline = BriskersConnectionModeController.instance.forceOffline;

    // Warm online refreshes never replace richer API rows with index-only
    // placeholders. Offline entries must read the index to pick up edits made
    // in another module, since there is no server refresh in that mode.
    if (!forceOnline && (_rows == null || forceOffline)) {
      localShown = await _loadLocalRows(
        epoch, businessId, kind, estimate: estimate,
      );
    }

    // Status colors are cosmetic and must not block the first offline-first
    // document list frame, including in Auto mode after a cold start.
    if (!estimate && !forceOnline && _invoiceStyles.isEmpty) {
      unawaited(_localInvoiceStyles.load(businessId).then((styles) {
        if (mounted && epoch == _loadEpoch && styles.isNotEmpty) {
          setState(() => _invoiceStyles = styles);
        }
      }).catchError((Object _) {}));
    }

    if (!mounted || epoch != _loadEpoch) return;
    if (forceOffline) {
      if (mounted && epoch == _loadEpoch && !localShown) {
        setState(() {
          _rows ??= const [];
          _error = null;
        });
      }
      return;
    }

    try {
      // The document payload is authoritative. Optional invoice colors must
      // not delay or fail the list when that independent endpoint is slow.
      final fetched = await _api.documents(businessId, kind: kind);

      if (!mounted || epoch != _loadEpoch) return;
      final blocked = await (widget.blockedDocumentIds?.call(businessId) ??
          LocalJobRetirement.blockedDocumentIds(localDatabase, businessId));
      final rows = List<Map<String, dynamic>>.from(fetched)
          .where((row) => !blocked.contains('${row['id'] ?? ''}'))
          .toList();
      if (!mounted || epoch != _loadEpoch) return;
      final styles = _invoiceStyles;

      // Preserve first paint and scroll position when the remote response
      // contains no changes, including financial fields absent in the index.
      final sameRows = documentListDataEquals(_serverRows, rows);
      final sameStyles = documentListDataEquals(_invoiceStyles, styles);
      if (!sameRows || !sameStyles || _error != null) {
        setState(() {
          if (!sameRows) {
            _rows = rows;
            _descriptionEpoch++;
          }
          _serverRows = rows;
          _invoiceStyles = styles;
          _error = null;
        });
      }
      if (estimate && !sameRows) {
        unawaited(_enrichEstimateDescriptions(_descriptionEpoch, rows));
      }

      // Paint the authoritative result before doing potentially expensive
      // persistence. Only changed snapshots replace the complete index; local
      // pending documents remain protected by the repository.
      if (!documentListDataEquals(_savedRows, rows)) {
        try {
          await _localDocuments.replaceFromServer(businessId, rows, kind: kind);
          // Track what actually reached disk even if a later refresh has
          // invalidated this read. Otherwise A -> B (saving) -> A could skip
          // the final write while the index incorrectly still contains B.
          if (mounted && widget.businessId == businessId && widget.kind == kind) {
            _savedRows = rows;
          }
        } catch (_) {
          // Keep the server result; a later refresh retries the failed cache.
        }
      }
      if (!mounted || epoch != _loadEpoch) return;
      if (!estimate) {
        unawaited(_api.invoiceStatusStyles(businessId).then((fetchedStyles) async {
          if (!mounted || epoch != _loadEpoch) return;
          if (!documentListDataEquals(_invoiceStyles, fetchedStyles)) {
            setState(() => _invoiceStyles = fetchedStyles);
          }
          if (!mounted || widget.businessId != businessId || widget.kind != kind || epoch != _loadEpoch) return;
          _styleCache[businessId] = fetchedStyles;
          try {
            await _localInvoiceStyles.save(businessId, fetchedStyles);
          } catch (_) {
            // Status styles are nonessential to document availability.
          }
        }).catchError((Object _) {}));
      }
    } catch (_) {
      if (!mounted || epoch != _loadEpoch) return;
      if (!forceOnline) {
        // Auto may have lost connectivity while another module changed local
        // work. Re-read protected local state only after online refresh fails.
        localShown = await _loadLocalRows(
          epoch, businessId, kind, estimate: estimate,
        ) || localShown;
      }
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _rows ??= const [];
        _error = (_rows!.isEmpty && !localShown)
            ? 'Could not refresh documents. Pull down to try again.'
            : null;
      });
    }
  }

  Future<bool> _loadLocalRows(
    int epoch,
    String businessId,
    String kind, {
    required bool estimate,
  }) async {
    final authoritativeAtStart = _serverRows;
    try {
      final local = await _localDocuments.listByKind(businessId, kind: kind);
      if (!mounted || epoch != _loadEpoch ||
          !identical(_serverRows, authoritativeAtStart)) {
        return false;
      }
      final rows = local.map(documentListIndexPresentation).toList();
      final sameRows = _serverRows == null &&
          documentListDataEquals(_indexRows, rows);
      if (!sameRows || _error != null) {
        setState(() {
          if (!sameRows) {
            _rows = rows;
            _descriptionEpoch++;
          }
          _indexRows = rows;
          _serverRows = null;
          _error = null;
        });
      }
      if (estimate && !sameRows) {
        unawaited(_enrichEstimateDescriptions(_descriptionEpoch, _rows!));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _hasFutureDateTag(Map<String, dynamic> row) =>
      isFutureDatedDocument(row);

  int get _futureDatedCount =>
      (_rows ?? const <Map<String, dynamic>>[])
          .where((row) => widget.customerId == null ||
              row['customer_id']?.toString() == widget.customerId)
          .where(_hasFutureDateTag).length;

  List<Map<String, dynamic>> get _visibleRows {
    final source = _rows ?? const <Map<String, dynamic>>[];
    if (!identical(_orderedSource, source) || _orderedEstimate != _estimate) {
      _orderedSource = source;
      _orderedEstimate = _estimate;
      _orderedRows = orderDocumentListRows(source, estimate: _estimate);
    }
    final rows = _orderedRows.where((row) => widget.customerId == null ||
        row['customer_id']?.toString() == widget.customerId).toList();

    var filtered = _selectedStatus == null
        ? rows
        : rows.where((row) => _matchesStatus(row, _selectedStatus!)).toList();

    if (_futureDatedOnly) {
      filtered = filtered.where(_hasFutureDateTag).toList();
    }

    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered
          .where((row) => matchesDocumentSearch(row, query))
          .toList();
    }

    return filtered;
  }

  int _statusCount(String status) {
    final rows = _rows ?? const <Map<String, dynamic>>[];
    return rows.where((row) => widget.customerId == null ||
        row['customer_id']?.toString() == widget.customerId)
        .where((row) => _matchesStatus(row, status)).length;
  }

  Widget _menuCount(int count, {bool alwaysShow = false}) {
    if (count <= 0 && !alwaysShow) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Text(
        '$count',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF405064),
        ),
      ),
    );
  }

  Future<void> _open(Map<String, dynamic> row, {String? initialAction}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          sharedBottomNavigationBar: widget.detailBottomNavigationBar ??
              widget.sharedBottomNavigationBar,
          roleCode: widget.roleCode,
          businessId: widget.businessId,
          documentId: row['id'].toString(),
          initialDocumentSummary: Map<String, dynamic>.from(row),
          isOwner: widget.isOwner,
          canManageExpenses: widget.canManageExpenses,
          initialAction: initialAction == 'payment' ? null : initialAction,
          initialTab: initialAction == 'payment' ? 'payment' : 'items',
        ),
      ),
    );

    if (mounted) unawaited(_load());
  }

  Future<void> _deleteDocument(Map<String, dynamic> row) async {
    if (!widget.isOwner) return;

    final isEstimate = row['kind']?.toString() == 'estimate';
    final paid = num.tryParse(row['paid_amount']?.toString() ?? '') ?? 0;
    final pending = num.tryParse(row['pending_payment']?.toString() ?? '') ?? 0;

    if (!isEstimate && paid > 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Paid invoice'),
          content: const Text(
            'This invoice has finalized payment activity and cannot be '
            'deleted. Use the correction/reversal workflow instead.',
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

    if (!isEstimate && pending > 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Payments entered'),
          content: const Text(
            'Remove the entered payments first. Once there are no payments '
            'on this invoice, it can be deleted.',
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

    final label = isEstimate ? 'estimate' : 'invoice';
    final number = row['document_number']?.toString().trim() ?? '';
    final documentId = row['id']?.toString() ?? '';
    final localDraft = _offlineDrafts.isLocalDraftId(documentId);
    bool deleteJob = false;
    if (!isEstimate && !localDraft) {
      if (BriskersConnectionModeController.instance.forceOffline) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reconnect to delete an already-synced invoice.'),
            ),
          );
        }
        return;
      }
      Map<String, dynamic>? plan;
      final jobId = row['job_id']?.toString() ?? '';
      if (jobId.isNotEmpty) {
        try {
          plan = await _api.jobDeletionPlan(widget.businessId, jobId);
        } catch (_) {
          // Invoice-only remains available; the RPC will verify permission.
        }
      }
      if (!mounted) return;
      final choice = await showInvoiceDeletionChoice(
        context,
        invoiceNumber: number,
        jobPlan: plan,
      );
      if (choice == null) return;
      deleteJob = choice;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Delete $label?'),
          content: Text(
            number.isEmpty
                ? 'This $label will be permanently deleted.'
                : 'Delete $label #$number? This cannot be undone.',
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
              child: Text('Delete $label'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;
    final progress = ValueNotifier<String>('Deleting…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Please wait'),
          content: ValueListenableBuilder<String>(
            valueListenable: progress,
            builder: (context, message, child) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Flexible(child: Text(message)),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      if (!isEstimate && _offlineDrafts.isLocalDraftId(row['id'].toString())) {
        await _offlineDrafts.cancelNeverSyncedQuickInvoice(
          widget.businessId,
          row['id'].toString(),
        );
      } else if (isEstimate) {
        await _api.deleteEstimate(widget.businessId, row['id'].toString());
      } else {
        await _api.deleteInvoiceManaged(
          widget.businessId,
          row['id'].toString(),
          deleteJob: deleteJob,
        );
      }

      progress.value = 'Refreshing…';
      await _load();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleteJob
                ? 'Invoice and Job deleted.'
                : '${isEstimate ? 'Estimate' : 'Invoice'} deleted.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            '${isEstimate ? 'Estimate' : 'Invoice'} could not be deleted',
          ),
          content: Text(error.toString()),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(value);
  }

  String _shortDate(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return '';
    return DateFormat('MMM d, yyyy').format(date.toLocal());
  }

  Future<void> _showDocumentActions(Map<String, dynamic> row) async {
    final canExpenses =
        !_estimate && (widget.isOwner || widget.canManageExpenses);
    final estimateConverted = _estimate && row['converted'] == true;
    final canDelete = widget.isOwner;
    final status = _invoiceStage(row);
    final total = num.tryParse(row['total_amount']?.toString() ?? '') ?? 0;
    final paid = num.tryParse(row['paid_amount']?.toString() ?? '') ?? 0;
    final pending = num.tryParse(row['pending_payment']?.toString() ?? '') ?? 0;
    final canPayment =
        !_estimate &&
        status == 'Open' &&
        !DocumentPresentation(row).requiresReconciliation &&
        total - paid - pending > 0.005;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: ListTileTheme(
            dense: true,
            minVerticalPadding: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _ActionSectionLabel('Edit and copy'),
              if (!estimateConverted)
                ListTile(
                  leading: Icon(
                    Icons.edit_outlined,
                    color: _estimate
                        ? BriskersColors.estimates
                        : BriskersColors.invoices,
                  ),
                  title: Text(
                    _estimate ? tr('editEstimate') : tr('editInvoice'),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'edit'),
                ),
              if (_estimate && !estimateConverted) ...[
                ListTile(
                  leading: const Icon(
                    Icons.receipt_long_outlined,
                    color: BriskersColors.invoices,
                  ),
                  title: const Text('Convert to New Invoice'),
                  onTap: () => Navigator.pop(sheetContext, 'convert_new'),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.post_add_outlined,
                    color: BriskersColors.invoices,
                  ),
                  title: const Text('Add to Existing Invoice'),
                  onTap: () => Navigator.pop(sheetContext, 'add_to_invoice'),
                ),
              ],
              ListTile(
                leading: Icon(
                  Icons.copy_outlined,
                  color: _estimate
                      ? BriskersColors.estimates : BriskersColors.invoices,
                ),
                title: Text(_estimate ? 'Copy Estimate' : tr('copyInvoice')),
                onTap: () => Navigator.pop(sheetContext, 'copy'),
              ),
              if (canPayment) ...[
                const Divider(height: 1),
                const _ActionSectionLabel('Payment'),
                ListTile(
                  leading: const Icon(
                    Icons.credit_card_outlined,
                    color: Colors.green,
                  ),
                  title: Text(tr('addPayment')),
                  onTap: () => Navigator.pop(sheetContext, 'payment'),
                ),
              ],
              if (canExpenses) ...[
                const Divider(height: 1),
                const _ActionSectionLabel('Expenses'),
              ],
              if (canExpenses)
                ListTile(
                  leading: const Icon(
                    Icons.add_card_outlined,
                    color: BriskersColors.expenses,
                  ),
                  title: Text(tr('addExpense')),
                  onTap: () => Navigator.pop(sheetContext, 'add_expense'),
                ),
              if (canExpenses)
                ListTile(
                  leading: const Icon(
                    Icons.payments_outlined,
                    color: BriskersColors.expenses,
                  ),
                  title: Text(tr('viewExpenses')),
                  onTap: () => Navigator.pop(sheetContext, 'expenses'),
                ),
              if (!_estimate) ...[
                const Divider(height: 1),
                const _ActionSectionLabel('Repair'),
                ListTile(
                  leading: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFC62828),
                  ),
                  title: Text(tr('vehicleFindings')),
                  onTap: () => Navigator.pop(sheetContext, 'findings'),
                ),
              ],
              const Divider(height: 1),
              const _ActionSectionLabel('Output'),
              ListTile(
                leading: Icon(
                  Icons.visibility_outlined,
                  color: _estimate
                      ? BriskersColors.estimates
                      : BriskersColors.invoices,
                ),
                title: Text(tr('preview')),
                onTap: () => Navigator.pop(sheetContext, 'preview'),
              ),
              ListTile(
                leading: Icon(
                  Icons.outbox_outlined,
                  color: _estimate
                      ? BriskersColors.estimates
                      : BriskersColors.invoices,
                ),
                title: Text(tr('send')),
                onTap: () => Navigator.pop(sheetContext, 'send'),
              ),
              if (canDelete) ...[
                const Divider(height: 1),
                const _ActionSectionLabel('Delete'),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(
                    _estimate ? tr('deleteEstimate') : tr('deleteInvoice'),
                    style: const TextStyle(color: Colors.red),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
                ),
              ],
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'expenses') {
      await _showExpensesFromList(row);
    } else if (action == 'delete') {
      await _deleteDocument(row);
    } else {
      await _open(row, initialAction: action);
    }
  }

  Future<void> _showCloseInvoices() async {
    if (_estimate || !widget.isOwner) return;

    final eligible = (_rows ?? const <Map<String, dynamic>>[])
        .where((row) => _invoiceStage(row) == 'Pending Close')
        .toList();

    if (eligible.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Close invoices'),
          content: const Text(
            'There are no fully paid invoices ready to close right now.',
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

    final selected = <String>{
      for (final row in eligible) row['id']?.toString() ?? '',
    }..remove('');

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedRows = eligible
              .where((row) => selected.contains(row['id']?.toString() ?? ''))
              .toList();
          final selectedTotal = selectedRows.fold<num>(
            0,
            (sum, row) =>
                sum +
                (num.tryParse(row['total_amount']?.toString() ?? '') ?? 0),
          );
          final allSelected = selected.length == eligible.length;

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.78,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Close invoices',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(sheetContext, false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Fully paid invoices are shown here. Pending payments are posted during closeout, then the invoice is marked Closed.',
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    activeColor: BriskersColors.invoices,
                    checkColor: Colors.white,
                    value: allSelected,
                    onChanged: (value) {
                      setSheetState(() {
                        selected.clear();
                        if (value == true) {
                          selected.addAll(
                            eligible
                                .map((row) => row['id']?.toString() ?? '')
                                .where((id) => id.isNotEmpty),
                          );
                        }
                      });
                    },
                    title: Text(
                      'Select all (${eligible.length})',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    secondary: Text(
                      _money(selectedTotal),
                      style: const TextStyle(
                        color: BriskersColors.invoices,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: eligible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = eligible[index];
                        final id = row['id']?.toString() ?? '';
                        final number = row['document_number']?.toString() ?? '';
                        final customer = row['customer_name']?.toString() ?? '';
                        final vehicle = row['vehicle']?.toString() ?? '';
                        return CheckboxListTile(
                          activeColor: BriskersColors.invoices,
                          checkColor: Colors.white,
                          value: selected.contains(id),
                          onChanged: id.isEmpty
                              ? null
                              : (value) {
                                  setSheetState(() {
                                    if (value == true) {
                                      selected.add(id);
                                    } else {
                                      selected.remove(id);
                                    }
                                  });
                                },
                          title: Text(
                            <String>[
                              if (number.isNotEmpty)
                                number.toUpperCase().startsWith('I-')
                                    ? number
                                    : 'I-$number',
                              customer,
                            ].where((value) => value.isNotEmpty).join('  '),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(vehicle),
                          secondary: Text(
                            _money(row['total_amount']),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${selected.length} selected • ${_money(selectedTotal)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: BriskersColors.invoices,
                          ),
                          onPressed: selected.isEmpty
                              ? null
                              : () => Navigator.pop(sheetContext, true),
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('Close selected'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirmed != true || selected.isEmpty || !mounted) return;

    final ok =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Close selected invoices?'),
            content: Text(
              'This will close ${selected.length} selected invoice'
              '${selected.length == 1 ? '' : 's'}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: BriskersColors.invoices,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Close invoices'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;

    try {
      // Check the entire selection before closing any invoice, then recheck
      // each RPC so a later receipt or connection-mode change cannot bypass it.
      await _finalizationGuard.check(
        businessId: widget.businessId,
        invoiceIds: selected,
        isOwner: widget.isOwner,
      );
      for (final id in selected) {
        if (!mounted) return;
        await _finalizationGuard.run(
          businessId: widget.businessId,
          invoiceIds: [id],
          isOwner: widget.isOwner,
          action: () => _api.closeInvoice(widget.businessId, id),
        );
        // The backend acknowledged this exact close. Update the cached
        // index and live list now; don't wait for the full invoice query.
        try {
          await _localDocuments.recordServerConfirmedClosed(
            widget.businessId, id,
          );
        } catch (_) {
          // Server confirmation remains valid; cache refresh can retry.
        }
        VerifiedInvoiceCloseEvents.serverConfirmed(VerifiedInvoiceClosed(
          businessId: widget.businessId, invoiceId: id,
        ));
      }
      unawaited(_load());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${selected.length} invoice${selected.length == 1 ? '' : 's'} closed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _showExpensesFromList(Map<String, dynamic> row) async {
    try {
      final offline = BriskersConnectionModeController.instance.forceOffline;
      final cached = await LocalFinancialCache().loadLinkedExpenses(
        widget.businessId,
      );
      final related =
          cached
              ?.where(
                (item) =>
                    item['document_id']?.toString() == row['id'].toString() ||
                    (row['job_id']?.toString() != null &&
                        item['job_id']?.toString() ==
                            row['job_id']?.toString()),
              )
              .toList() ??
          const <Map<String, dynamic>>[];
      final expenses = offline
          ? related
          : await _api.documentExpenses(
              widget.businessId,
              row['id'].toString(),
            );
      if (!mounted) return;

      if (offline && cached == null) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Offline expenses not synchronized'),
            content: const Text(
              'Connect using Auto and run Local Database Sync to save '
              'the linked expense history before working offline.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      if (expenses.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(tr('noRelatedExpenses')),
            content: Text(
              (row['job_number']?.toString() ?? '').isEmpty
                  ? 'There are no expenses linked to this invoice.'
                  : 'There are no expenses linked to this invoice or its job.',
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      tr('viewExpenses'),
                      style: const TextStyle(
                        color: BriskersColors.expenses,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: expenses.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final expense = expenses[index];
                      final id = expense['id']?.toString() ?? '';
                      final vendor = expense['vendor']?.toString() ?? 'Expense';
                      final category = expense['category']?.toString() ?? '';
                      final date =
                          expense['transaction_date']?.toString() ?? '';
                      final scope = expense['scope']?.toString() ?? 'invoice';
                      final jobNumber = expense['job_number']?.toString() ?? '';
                      final scopeLabel = scope == 'invoice'
                          ? tr('invoiceLinked')
                          : (jobNumber.isEmpty
                                ? tr('jobExpense')
                                : '${tr('jobLabel')} $jobNumber');
                      final income =
                          expense['direction']?.toString() == 'income';

                      final expenseColor = income
                          ? const Color(0xFF169B62)
                          : BriskersColors.expenses;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: expenseColor.withValues(alpha: 0.14),
                          child: Icon(
                            income ? Icons.south_west : Icons.north_east,
                            color: expenseColor,
                          ),
                        ),
                        title: Text(
                          vendor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (category.isNotEmpty)
                              Text(
                                category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            Text(
                              <String>[
                                if (scopeLabel.isNotEmpty) scopeLabel,
                                if (date.isNotEmpty) date,
                              ].join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        trailing: Text(
                          '${income ? '+' : '-'}${_money(expense['amount'])}',
                          style: TextStyle(
                            color: expenseColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
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
                                      cachedDetail: offline
                                          ? Map<String, dynamic>.from(expense)
                                          : null,
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

  Future<void> _createBlankInvoice() async {
    if (_estimate || !(widget.isOwner || widget.canManageExpenses)) return;

    final invoiceId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BlankInvoiceSetupScreen(
          businessId: widget.businessId,
          initialCustomerId: widget.customerId,
          initialCustomerName: widget.customerName,
          initialVehicles: widget.customerVehicles,
        ),
      ),
    );
    if (!mounted || invoiceId == null || invoiceId.isEmpty) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          sharedBottomNavigationBar: widget.detailBottomNavigationBar ??
              widget.sharedBottomNavigationBar,
          roleCode: widget.roleCode,
          businessId: widget.businessId,
          documentId: invoiceId,
          isOwner: widget.isOwner,
          canManageExpenses: widget.canManageExpenses,
          initialAction: 'edit',
        ),
      ),
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _createStandaloneEstimate() async {
    if (!widget.isOwner && !widget.canManageExpenses) return;
    final documentId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BlankInvoiceSetupScreen(
          businessId: widget.businessId,
          kind: 'estimate',
          initialCustomerId: widget.customerId,
          initialCustomerName: widget.customerName,
          initialVehicles: widget.customerVehicles,
        ),
      ),
    );
    if (!mounted) return;
    if (documentId != null && documentId.isNotEmpty) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => JobDocumentScreen(
          sharedBottomNavigationBar: widget.detailBottomNavigationBar ??
              widget.sharedBottomNavigationBar,
            roleCode: widget.roleCode,
            businessId: widget.businessId,
            documentId: documentId,
            isOwner: widget.isOwner,
            canManageExpenses: widget.canManageExpenses,
          ),
        ),
      );
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_rows != null) {
      NavigationContentTiming.contentVisible(
        _estimate ? 'estimates' : 'invoices',
        context: context,
        source: _serverRows == null ? 'local-or-retained' : 'server-or-retained',
      );
    }
    final visible = _visibleRows;
    final selectedLabel = _futureDatedOnly
        ? 'Future-dated'
        : (_selectedStatus == null
              ? tr('all')
              : _localizedStatusLabel(_selectedStatus!));
    final accent = _estimate
        ? BriskersColors.estimates : BriskersColors.invoices;
    final scopedRows = (_rows ?? const <Map<String, dynamic>>[])
        .where((row) => widget.customerId == null ||
            row['customer_id']?.toString() == widget.customerId).toList();

    return StaleKeyboardInsetGuard(
      child: Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.customerId != null
          ? AppBar(
              title: Text(widget.customerName?.trim().isNotEmpty == true
                  ? widget.customerName! : _title,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800)),
              backgroundColor: accent.withValues(alpha: 0.08),
            )
          : widget.showAppBar
          ? AppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: 78,
              titleSpacing: 10,
              backgroundColor: accent.withValues(alpha: 0.08),
              title: Row(
                children: [
                  const BriskersLogo(height: 44, maxWidth: 148),
                  const Spacer(),
                  ConnectionHeaderToggle(businessId: widget.businessId),
                ],
              ),
              actions: [
                if (widget.isOwner)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFFF6EAD5),
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Text(
                            'OWNER',
                            style: TextStyle(
                              color: Color(0xFFC47A12),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : null,
      // The module dock belongs to Shell. Nested customer views may supply
      // their own dock; never reserve bottom space for New Estimate/Invoice.
      // Creation lives beside Search for every view, just like Customers.
      bottomNavigationBar: widget.customerId != null &&
              widget.sharedBottomNavigationBar != null
          ? widget.sharedBottomNavigationBar!
          : widget.showAppBar && _estimate
          ? (widget.sharedBottomNavigationBar ??
                NavigationBar(
                  selectedIndex: 5,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
                  onDestinationSelected: (index) {
                    final selectDestination =
                        widget.onPrimaryDestinationSelected;
                    if (selectDestination != null) {
                      selectDestination(index);
                      return;
                    }
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ShellScreen(
                          businessId: widget.businessId,
                          businessName: widget.businessName,
                          roleCode: widget.roleCode,
                          initialIndex: index,
                        ),
                      ),
                    );
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      label: 'Customers',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      label: 'Schedule',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.build_outlined),
                      label: 'Jobs',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      label: 'Invoices',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.more_horiz),
                      label: 'More',
                    ),
                  ],
                ))
          : null,
      floatingActionButton: (widget.isOwner || widget.canManageExpenses) &&
              MediaQuery.viewInsetsOf(context).bottom == 0
          ? FloatingActionButton.extended(
              heroTag: _estimate ? 'estimates-quick-create' : 'invoices-quick-create',
              tooltip: _estimate ? 'New Estimate' : 'New Invoice',
              onPressed: _estimate ? _createStandaloneEstimate : _createBlankInvoice,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              backgroundColor: accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          itemCount: visible.length + 1,
          itemBuilder: (context, index) {
            if (index > 0) return _documentCard(visible[index - 1]);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Row(
              children: [
                Text(
                  _title,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800, color: accent),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Filter $_title',
                  onSelected: (value) => setState(() {
                    _futureDatedOnly = value == '__future__';
                    _selectedStatus =
                        value == '__all__' || value == '__future__'
                        ? null
                        : value;
                  }),
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      value: '__all__',
                      child: Row(
                        children: [
                          const Icon(Icons.all_inclusive),
                          const SizedBox(width: 10),
                          Expanded(child: Text(tr('all'))),
                          _menuCount(scopedRows.length, alwaysShow: true),
                        ],
                      ),
                    ),
                    if (!_estimate)
                      PopupMenuItem<String>(
                        value: '__future__',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.flag_outlined,
                              color: Color(0xFFB26A00),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('Future-dated')),
                            _menuCount(_futureDatedCount, alwaysShow: true),
                          ],
                        ),
                      ),
                    ..._statuses.map((status) {
                      final count = _statusCount(status);
                      return PopupMenuItem<String>(
                        value: status,
                        child: Row(
                          children: [
                            Icon(
                              _statusIcon(status),
                              size: 16,
                              color: _statusColor(status),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_localizedStatusLabel(status)),
                            ),
                            _menuCount(count),
                          ],
                        ),
                      );
                    }),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color:
                            (_futureDatedOnly
                                    ? const Color(0xFFB26A00)
                                    : (_selectedStatus == null
                                          ? accent
                                          : _statusColor(_selectedStatus!)))
                                .withValues(alpha: 0.50),
                      ),
                      color:
                          (_futureDatedOnly
                                  ? const Color(0xFFB26A00)
                                  : (_selectedStatus == null
                                        ? accent
                                        : _statusColor(_selectedStatus!)))
                              .withValues(alpha: 0.08),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedLabel,
                          style: TextStyle(
                            color: _futureDatedOnly
                                ? const Color(0xFFB26A00)
                                : (_selectedStatus == null
                                      ? accent
                                      : _statusColor(_selectedStatus!)),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: _futureDatedOnly
                              ? const Color(0xFFB26A00)
                              : (_selectedStatus == null
                                    ? accent
                                    : _statusColor(_selectedStatus!)),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (_rows != null)
                  Text(
                    '${tr('total')} ${scopedRows.length}',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            if (!_estimate && widget.isOwner) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: BriskersColors.invoices,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _showCloseInvoices,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Close invoices'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SearchBar(
                    key: const ValueKey('persistent-document-search'),
                    controller: _search,
                    focusNode: _searchFocus,
                    hintText: _estimate
                        ? 'Search estimate #, customer, job or vehicle'
                        : 'Search invoice #, customer, job or vehicle',
                    leading: const Icon(Icons.search),
                    trailing: [
                      if (_search.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),

              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 10),
            if (_rows == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (visible.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    _futureDatedOnly
                        ? 'No future-dated invoices found. Refresh to check for updates.'
                        : 'No ${_title.toLowerCase()} in this status.',
                  ),
                ),
              )
              ],
            );
          },
        ),
      ),
      ),
    );
  }

  Widget _documentCard(Map<String, dynamic> row) {
    final status = _invoiceStage(row);
    final statusLabel = _localizedStatusLabel(status);
    final color = _statusColor(status);
    final number = row['document_number']?.toString() ?? '';
    final customer = row['customer_name']?.toString() ?? '';
    final documentTitle =
        (row['title'] ?? row['job_title'])?.toString().trim() ?? '';
    final estimateDescription = _estimate
        ? (row['_estimate_list_description']?.toString().trim() ??
            estimateListDescription(row))
        : '';
    final vehicle = row['vehicle']?.toString() ?? '';
    final jobNumber = row['job_number']?.toString() ?? '';
    final documentDate = _shortDate(row['document_date']);
    final displayNumber = number.isEmpty
        ? ''
        : (_estimate
              ? (number.toUpperCase().startsWith('E-')
                    ? number
                    : 'E-$number')
              : (number.toUpperCase().startsWith('I-')
                    ? number
                    : 'I-$number'));

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      color: Color.alphaBlend(
        color.withValues(alpha: 0.08),
        Colors.white,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(row),
        onLongPress: () => _showDocumentActions(row),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (displayNumber.isNotEmpty) ...[
                          Text(
                            displayNumber,
                            style: const TextStyle(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            customer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (row['customer_problem_flag'] ==
                            true) ...[
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.flag,
                            color: Colors.red,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                    if (documentTitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        documentTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (estimateDescription.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        estimateDescription,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w400,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    if (vehicle.isNotEmpty)
                      Text(
                        vehicle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (_hasFutureDateTag(row)) ...[
                      const SizedBox(height: 4),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag_outlined,
                            size: 14,
                            color: Color(0xFFB26A00),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Future-dated',
                            style: TextStyle(
                              color: Color(0xFFB26A00),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (jobNumber.isNotEmpty ||
                        documentDate.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        <String>[
                          if (jobNumber.isNotEmpty)
                            '${tr('jobLabel')} $jobNumber',
                          if (documentDate.isNotEmpty) documentDate,
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 98,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _money(row['total_amount']),
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
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

class _ActionSectionLabel extends StatelessWidget {
  const _ActionSectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 5),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
