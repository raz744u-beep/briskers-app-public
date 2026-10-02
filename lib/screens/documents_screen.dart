import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/invoice_status_style.dart';
import '../core/briskers_i18n.dart';
import '../services/briskers_api.dart';
import '../widgets/briskers_page_header.dart';
import 'jobs/job_document_screen.dart';
import 'expenses/expense_detail_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    required this.businessId,
    required this.kind,
    required this.isOwner,
    this.canManageExpenses = false,
  });

  final String businessId;
  final String kind;
  final bool isOwner;
  final bool canManageExpenses;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  static const _api = BriskersApi();
  static final Map<String, List<Map<String, dynamic>>> _rowCache = {};
  static final Map<String, List<Map<String, dynamic>>> _styleCache = {};

  List<Map<String, dynamic>>? _rows;
  List<Map<String, dynamic>> _invoiceStyles = const [];
  String? _selectedStatus;
  String? _error;

  bool get _estimate => widget.kind == 'estimate';

  List<String> get _statuses => _estimate
      ? const ['Draft', 'Issued', 'Accepted', 'Declined', 'Expired', 'Void']
      : _invoiceStyles
          .map((item) => item['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();

  String get _title => _estimate ? tr('estimates') : tr('invoices');

  String _localizedStatusLabel(String status) {
    switch (status) {
      case 'Open':
        return tr('invoiceOpen');
      case 'Pending Close':
        return tr('invoicePendingClose');
      case 'Paid':
        return tr('invoicePaid');
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
    if (!_estimate) {
      final style = _invoiceStyleByName(status);
      if (style != null) {
        return invoiceStatusColorFromHex(
          style['color_hex']?.toString(),
          fallback: BriskersColors.invoices,
        );
      }
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
    }
    return Icons.circle;
  }

  String get _cacheKey => '${widget.businessId}:${widget.kind}';

  @override
  void initState() {
    super.initState();
    final cachedRows = _rowCache[_cacheKey];
    final cachedStyles = _styleCache[widget.businessId];
    if (cachedRows != null) {
      _rows = List<Map<String, dynamic>>.from(cachedRows);
    }
    if (!_estimate && cachedStyles != null) {
      _invoiceStyles = List<Map<String, dynamic>>.from(cachedStyles);
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.documents(
          widget.businessId,
          kind: widget.kind,
        ),
        if (!_estimate)
          _api.invoiceStatusStyles(widget.businessId)
        else
          Future.value(const <Map<String, dynamic>>[]),
      ]);

      final rows = List<Map<String, dynamic>>.from(results[0] as List);
      final styles = List<Map<String, dynamic>>.from(results[1] as List);

      _rowCache[_cacheKey] = List<Map<String, dynamic>>.from(rows);
      if (!_estimate) {
        _styleCache[widget.businessId] =
            List<Map<String, dynamic>>.from(styles);
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _invoiceStyles = styles;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _rows ??= _rowCache[_cacheKey] ?? const [];
        _error = _rows!.isEmpty
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

  List<Map<String, dynamic>> get _visibleRows {
    final rows = List<Map<String, dynamic>>.from(
      _rows ?? const <Map<String, dynamic>>[],
    );

    final filtered = _selectedStatus == null
        ? rows
        : rows
            .where(
              (row) =>
                  row['display_status']?.toString() == _selectedStatus,
            )
            .toList();

    if (!_estimate || _selectedStatus != null) return filtered;

    filtered.sort((a, b) {
      final statusCompare = _estimateStatusRank(
        a['display_status']?.toString() ?? '',
      ).compareTo(
        _estimateStatusRank(
          b['display_status']?.toString() ?? '',
        ),
      );
      if (statusCompare != 0) return statusCompare;

      final aDate =
          DateTime.tryParse(a['document_date']?.toString() ?? '');
      final bDate =
          DateTime.tryParse(b['document_date']?.toString() ?? '');
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
    return rows
        .where((row) => row['display_status']?.toString() == status)
        .length;
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

  Future<void> _open(Map<String, dynamic> row) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: row['id'].toString(),
          isOwner: widget.isOwner,
          canManageExpenses: widget.canManageExpenses,
        ),
      ),
    );

    if (mounted) unawaited(_load());
  }

  Future<void> _deleteDocument(Map<String, dynamic> row) async {
    if (!widget.isOwner) return;

    final isEstimate = row['kind']?.toString() == 'estimate';
    final paid = num.tryParse(row['paid_amount']?.toString() ?? '') ?? 0;
    final pending =
        num.tryParse(row['pending_payment']?.toString() ?? '') ?? 0;

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

    try {
      if (isEstimate) {
        await _api.deleteEstimate(
          widget.businessId,
          row['id'].toString(),
        );
      } else {
        await _api.deleteDraftInvoice(
          widget.businessId,
          row['id'].toString(),
        );
      }

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${isEstimate ? 'Estimate' : 'Invoice'} deleted.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
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

  Future<void> _showExpensesFromList(Map<String, dynamic> row) async {
    try {
      final expenses = await _api.documentExpenses(
        widget.businessId,
        row['id'].toString(),
      );
      if (!mounted) return;

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
                      final vendor =
                          expense['vendor']?.toString() ?? 'Expense';
                      final category =
                          expense['category']?.toString() ?? '';
                      final date =
                          expense['transaction_date']?.toString() ?? '';
                      final scope =
                          expense['scope']?.toString() ?? 'invoice';
                      final jobNumber =
                          expense['job_number']?.toString() ?? '';
                      final scopeLabel = scope == 'invoice'
                          ? tr('invoiceLinked')
                          : (jobNumber.isEmpty
                              ? tr('jobExpense')
                              : '${tr('jobLabel')} $jobNumber');
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
                            scopeLabel,
                            if (category.isNotEmpty) category,
                            if (date.isNotEmpty) date,
                          ].join(' • '),
                        ),
                        trailing: Text(
                          '${income ? '+' : '-'}${_money(expense['amount'])}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
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
  @override
  Widget build(BuildContext context) {
    final visible = _visibleRows;
    final selectedLabel = _selectedStatus == null
        ? tr('all')
        : _localizedStatusLabel(_selectedStatus!);
    final accent = _estimate ? BriskersColors.estimates : BriskersColors.invoices;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: BriskersPageTitle(title: _title, logoHeight: 40),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 84),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                tooltip: 'Filter $_title',
                onSelected: (value) => setState(
                  () => _selectedStatus = value == '__all__' ? null : value,
                ),
                itemBuilder: (_) => [
           alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                tooltip: 'Filter $_title',
                onSelected: (value) => setState(
                  () => _selectedStatus = value == '__all__' ? null : value,
                ),
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    value: '__all__',
                    child: Row(
                      children: [
                        const Icon(Icons.all_inclusive),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tr('all'))),
                        _menuCount(_rows?.length ?? 0, alwaysShow: true),
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
                          Expanded(child: Text(_localizedStatusLabel(status))),
                          _menuCount(count),
                        ],
                      ),
                    );
                  }),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: (_selectedStatus == null
                              ? accent
                              : _statusColor(_selectedStatus!))
                          .withValues(alpha: 0.50),
                    ),
                    color: (_selectedStatus == null
                            ? accent
                            : _statusColor(_selectedStatus!))
                        .withValues(alpha: 0.08),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        selectedLabel,
                        style: TextStyle(
                          color: _selectedStatus == null
                              ? accent
                              : _statusColor(_selectedStatus!),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: _selectedStatus == null
                            ? accent
                            : _statusColor(_selectedStatus!),
                      ),
                    ],
                  ),
                ),
              ),
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
                  child: Text('No ${_title.toLowerCase()} in this status.'),
                ),
              )
            else
              ...visible.map((row) {
                final status = row['display_status']?.toString() ?? '';
                final statusLabel = _localizedStatusLabel(status);
                final color = _statusColor(status);
                final number = row['document_number']?.toString() ?? '';
                final customer = row['customer_name']?.toString() ?? '';
                final vehicle = row['vehicle']?.toString() ?? '';
                final jobNumber = row['job_number']?.toString() ?? '';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _open(row),
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(
                        _estimate
                            ? Icons.request_quote_outlined
                            : invoiceStatusIcon(
                                row['status_icon']?.toString(),
                              ),
                        color: color,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            <String>[
                              if (number.isNotEmpty)
                                (_estimate
                                    ? (number.toUpperCase().startsWith('E-')
                                        ? number
                                        : 'E-$number')
                                    : (number.toUpperCase().startsWith('I-')
                                        ? number
                                        : 'I-$number')),
                              if (customer.isNotEmpty) customer,
                            ].join('  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (row['customer_problem_flag'] == true) ...[
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.flag,
                            color: Colors.red,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      <String>[
                        if (vehicle.isNotEmpty) vehicle,
                        if (jobNumber.isNotEmpty)
                          '${tr('jobLabel')} $jobNumber',
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: SizedBox(
                      width: (widget.isOwner ||
                              (!_estimate && widget.canManageExpenses))
                          ? 106
                          : 82,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    _money(row['total_amount']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.isOwner ||
                              (!_estimate && widget.canManageExpenses))
                            SizedBox(
                              width: 28,
                              child: PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                iconSize: 19,
                                tooltip: 'Document actions',
                                onSelected: (value) {
                                  if (value == 'expenses') {
                                    _showExpensesFromList(row);
                                  }
                                  if (value == 'delete') {
                                    _deleteDocument(row);
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (!_estimate && widget.canManageExpenses)
                                    PopupMenuItem<String>(
                                      value: 'expenses',
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(
                                          Icons.payments_outlined,
                                        ),
                                        title: Text(tr('viewExpenses')),
                                      ),
                                    ),
                                  if (widget.isOwner)
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(
                                          Icons.delete_outline,
                                        ),
                                        title: Text(
                                          _estimate
                                              ? tr('deleteEstimate')
                                              : tr('deleteInvoice'),
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
