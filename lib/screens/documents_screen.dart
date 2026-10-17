import 'dart:async';

import 'package:flutter/material.dart' hide showDialog, showModalBottomSheet;

import '../core/module_modal_theme.dart';

import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/connection_mode.dart';
import '../core/invoice_status_style.dart';
import '../core/briskers_i18n.dart';
import '../core/document_search.dart';
import '../core/document_future_date.dart';
import '../core/document_presentation.dart';
import '../services/briskers_api.dart';
import '../services/local_job_retirement.dart';
import '../local/local_database_provider.dart';
import '../services/local_financial_cache.dart';
import '../services/local_document_repository.dart';
import '../services/offline_document_draft_service.dart';
import '../services/local_invoice_status_styles_cache.dart';
import '../services/invoice_finalization_guard.dart';
import '../widgets/briskers_page_header.dart';
import '../widgets/connection_header_toggle.dart';
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

const invoiceListStatusFilters = [
  'Open',
  'Pending Close',
  'Closed',
  'Reopened',
  'Void',
];
const estimateListStatusFilters = [
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
    this.customerId,
    this.customerName,
    this.customerVehicles = const [],
  });

  final String? customerId;
  final String? customerName;
  final List<dynamic> customerVehicles;
  final bool showAppBar;
  final String businessName;
  final String roleCode;
  final ValueChanged<int>? onPrimaryDestinationSelected;
  final Widget? sharedBottomNavigationBar;
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
  static const _api = BriskersApi();
  final LocalDocumentRepository _localDocuments = LocalDocumentRepository();
  final OfflineDocumentDraftService _offlineDrafts =
      OfflineDocumentDraftService();
  final LocalInvoiceStatusStylesCache _localInvoiceStyles =
      LocalInvoiceStatusStylesCache();
  static final Map<String, List<Map<String, dynamic>>> _styleCache = {};
  final InvoiceFinalizationGuard _finalizationGuard =
      InvoiceFinalizationGuard();

  List<Map<String, dynamic>>? _rows;
  int _loadEpoch = 0;
  StreamSubscription<({String businessId, Set<String> jobIds})>? _retirement;
  List<Map<String, dynamic>> _invoiceStyles = const [];
  String? _selectedStatus;
  bool _futureDatedOnly = false;
  String? _error;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'document-search');

  bool get _estimate => widget.kind == 'estimate';

  String _invoiceStage(Map<String, dynamic> row) =>
      documentListStage(row, estimate: _estimate);

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
    final cachedStyles = _styleCache[widget.businessId];
    if (!_estimate && cachedStyles != null) {
      _invoiceStyles = List<Map<String, dynamic>>.from(cachedStyles);
    }
    _retirement = LocalJobRetirement.events.listen((event) {
      if (event.businessId == widget.businessId && mounted) {
        // Invalidate any response captured before the durable tombstone.
        _loadEpoch++;
        unawaited(_load());
      }
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant DocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.kind != widget.kind) {
      _loadEpoch++;
      _rows = null;
      _invoiceStyles = const [];
      _error = null;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _retirement?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    var localShown = false;
    final forceOnline = BriskersConnectionModeController.instance.forceOnline;
    final forceOffline = BriskersConnectionModeController.instance.forceOffline;

    if (!_estimate && !forceOnline) {
      try {
        final cachedStyles = await _localInvoiceStyles.load(widget.businessId);
        if (mounted && cachedStyles.isNotEmpty) {
          setState(() => _invoiceStyles = cachedStyles);
        }
      } catch (_) {}
    }

    if (!forceOnline) {
      try {
        final local = await _localDocuments.listByKind(
          widget.businessId,
          kind: widget.kind,
        );
        if (mounted && epoch == _loadEpoch) {
          localShown = true;
          setState(() {
            _rows = local.map(documentListIndexPresentation).toList();
            _error = null;
          });
        }
      } catch (_) {}
    }

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
      final results = await Future.wait<dynamic>([
        _api.documents(widget.businessId, kind: widget.kind),
        if (!_estimate)
          _api.invoiceStatusStyles(widget.businessId)
        else
          Future.value(const <Map<String, dynamic>>[]),
      ]);

      final blocked = await LocalJobRetirement.blockedDocumentIds(
        localDatabase,
        widget.businessId,
      );
      final rows = List<Map<String, dynamic>>.from(results[0] as List)
          .where((row) => !blocked.contains('${row['id'] ?? ''}'))
          .toList();
      if (!mounted || epoch != _loadEpoch) return;
      final styles = List<Map<String, dynamic>>.from(results[1] as List);

      // A complete server snapshot must evict stale synced MobileBiz rows.
      // Any locally pending documents are preserved by the repository.
      await _localDocuments.replaceFromServer(
        widget.businessId,
        rows,
        kind: widget.kind,
      );
      if (!_estimate) {
        _styleCache[widget.businessId] = List<Map<String, dynamic>>.from(
          styles,
        );
        await _localInvoiceStyles.save(widget.businessId, styles);
      }

      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _rows = rows;
        _invoiceStyles = styles;
        _error = null;
      });
    } catch (_) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _rows ??= const [];
        _error = (_rows!.isEmpty && !localShown)
            ? 'Could not refresh documents. Pull down to try again.'
            : null;
      });
    }
  }

  int _estimateStatusRank(String status) {
    switch (status) {
      case 'Draft':
        return 0;
      case 'Issued':
        return 1;
      case 'Accepted':
        return 2;
      case 'Declined':
        return 3;
      case 'Expired':
        return 4;
      case 'Void':
        return 5;
      default:
        return 6;
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
    final rows = List<Map<String, dynamic>>.from(
      _rows ?? const <Map<String, dynamic>>[],
    ).where((row) => widget.customerId == null ||
        row['customer_id']?.toString() == widget.customerId).toList();

    var filtered = _selectedStatus == null
        ? rows
        : rows.where((row) => _invoiceStage(row) == _selectedStatus).toList();

    if (_futureDatedOnly) {
      filtered = filtered.where(_hasFutureDateTag).toList();
    }

    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered
          .where((row) => matchesDocumentSearch(row, query))
          .toList();
    }

    if (!_estimate) {
      // The invoice number sequence must agree online and offline.
      // Import timestamps and anomalous legacy dates are not list order.
      int? invoiceNumber(Map<String, dynamic> row) {
        final value = row['document_number']?.toString() ?? '';
        final matches = RegExp(r'[0-9]+').allMatches(value).toList();
        if (matches.isEmpty) return null;
        return int.tryParse(matches.last.group(0)!);
      }

      filtered.sort((a, b) {
        final aNumber = invoiceNumber(a);
        final bNumber = invoiceNumber(b);
        if (aNumber != null && bNumber != null) {
          final order = bNumber.compareTo(aNumber);
          if (order != 0) return order;
        } else if (aNumber == null && bNumber != null) {
          return -1;
        } else if (aNumber != null && bNumber == null) {
          return 1;
        }
        return (b['created_at']?.toString() ?? '').compareTo(
          a['created_at']?.toString() ?? '',
        );
      });
      return filtered;
    }

    if (_selectedStatus != null) return filtered;

    filtered.sort((a, b) {
      final statusCompare = _estimateStatusRank(
        a['display_status']?.toString() ?? '',
      ).compareTo(_estimateStatusRank(b['display_status']?.toString() ?? ''));
      if (statusCompare != 0) return statusCompare;

      final aDate = DateTime.tryParse(a['document_date']?.toString() ?? '');
      final bDate = DateTime.tryParse(b['document_date']?.toString() ?? '');
      if (aDate != null && bDate != null) {
        return bDate.compareTo(aDate);
      }
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return 0;
    });

    return filtered;
  }

  int _statusCount(String status) {
    final rows = _rows ?? const <Map<String, dynamic>>[];
    return rows.where((row) => widget.customerId == null ||
        row['customer_id']?.toString() == widget.customerId)
        .where((row) => _invoiceStage(row) == status).length;
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
          sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
          roleCode: widget.roleCode,
          businessId: widget.businessId,
          documentId: row['id'].toString(),
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
            visualDensity: const VisualDensity(vertical: -2),
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
      }
      await _load();
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
          sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
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
          sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
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
    final knownAmounts = scopedRows.where((row) =>
        num.tryParse(row['total_amount']?.toString() ?? '') != null).toList();
    final grandTotal = knownAmounts.fold<num>(0, (sum, row) =>
        sum + (num.tryParse(row['total_amount']?.toString() ?? '') ?? 0));
    final missingAmountCount = scopedRows.length - knownAmounts.length;

    return Scaffold(
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
      bottomNavigationBar: (widget.customerId != null || !widget.showAppBar)
          ? SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isOwner || widget.canManageExpenses)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 7, 12, 9),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _estimate ? _createStandaloneEstimate
                              : _createBlankInvoice,
                          icon: const Icon(Icons.add),
                          label: Text(_estimate ? 'New Estimate' : 'New Invoice'),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ),
                  if (widget.sharedBottomNavigationBar != null)
                    widget.sharedBottomNavigationBar!,
                ],
              ),
            )
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
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 84),
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
            if (_rows != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: accent.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_estimate ? 'Total Estimates' : 'Total Invoices',
                          style: TextStyle(fontSize: 18,
                              fontWeight: FontWeight.w800, color: accent)),
                      const SizedBox(height: 4),
                      Text(_money(grandTotal),
                          style: TextStyle(fontSize: 26,
                              fontWeight: FontWeight.w800, color: accent)),
                      Text('${scopedRows.length} records'
                        '${missingAmountCount == 0 ? "" : " • amounts unavailable: $missingAmountCount"}',
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
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
                const SizedBox(width: 8),
                if (widget.isOwner || widget.canManageExpenses)
                  IconButton.filled(
                    tooltip: _estimate ? 'New Estimate' : 'New Invoice',
                    style: IconButton.styleFrom(
                      backgroundColor: _estimate
                          ? BriskersColors.estimates
                          : BriskersColors.invoices,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _estimate
                        ? _createStandaloneEstimate
                        : _createBlankInvoice,
                    icon: const Icon(Icons.add),
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
            else
              ...visible.map((row) {
                final status = _invoiceStage(row);
                final statusLabel = _localizedStatusLabel(status);
                final color = _statusColor(status);
                final number = row['document_number']?.toString() ?? '';
                final customer = row['customer_name']?.toString() ?? '';
                final documentTitle =
                    (row['title'] ?? row['job_title'])?.toString().trim() ?? '';
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
                                          fontWeight: FontWeight.w900,
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
                                          fontWeight: FontWeight.w900,
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
                                      fontWeight: FontWeight.w900,
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
                                        fontWeight: FontWeight.w800,
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
              }),
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
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 5),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.45,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}
