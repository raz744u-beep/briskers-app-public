import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/invoice_status_style.dart';
import '../services/briskers_api.dart';
import '../widgets/briskers_page_header.dart';
import 'jobs/job_document_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    required this.businessId,
    required this.kind,
    required this.isOwner,
  });

  final String businessId;
  final String kind;
  final bool isOwner;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  static const _api = BriskersApi();

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

  String get _title => _estimate ? 'Estimates' : 'Invoices';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.documents(
        widget.businessId,
        kind: widget.kind,
      );
      final styles = _estimate
          ? const <Map<String, dynamic>>[]
          : await _api.invoiceStatusStyles(widget.businessId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _invoiceStyles = styles;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _error = error.toString();
      });
    }
  }

  List<Map<String, dynamic>> get _visibleRows {
    final rows = _rows ?? const <Map<String, dynamic>>[];
    if (_selectedStatus == null) return rows;
    return rows
        .where((row) => row['display_status']?.toString() == _selectedStatus)
        .toList();
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
        ),
      ),
    );
    await _load();
  }

  String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleRows;
    final selectedLabel = _selectedStatus ?? 'All';
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
                if (_rows != null)
                  Text(
                    'Total ${_rows!.length}',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
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
                        const Expanded(child: Text('All')),
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
                          Expanded(child: Text(status)),
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
                        if (jobNumber.isNotEmpty) 'Job $jobNumber',
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _money(row['total_amount']),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
