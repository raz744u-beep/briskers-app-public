import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/briskers_colors.dart';
import '../../core/owner_report_models.dart';
import '../jobs/job_document_screen.dart';
import '../payroll/approved_tasks_ui.dart';

class OwnerReportTransactionsScreen extends StatefulWidget {
  const OwnerReportTransactionsScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
    required this.data,
    required this.period,
    this.initialBasis = ReportTransactionBasis.invoices,
    this.reload,
    this.sharedBottomNavigationBar,
  });
  final String businessId;
  final bool isOwner;
  final OwnerReportData data;
  final ReportPeriod period;
  final ReportTransactionBasis initialBasis;
  final Future<OwnerReportData> Function()? reload;
  final Widget? sharedBottomNavigationBar;
  @override
  State<OwnerReportTransactionsScreen> createState() =>
      _OwnerReportTransactionsScreenState();
}

class _OwnerReportTransactionsScreenState
    extends State<OwnerReportTransactionsScreen> {
  late OwnerReportData _data;
  late ReportTransactionBasis _basis;
  bool _loading = false;
  String? _error;
  static final _currency = NumberFormat.simpleCurrency(locale: 'en_US');
  String _money(int? n) =>
      n == null ? 'Not recorded' : _currency.format(n / 100);
  @override
  void initState() {
    super.initState();
    _data = widget.data;
    _basis = widget.initialBasis;
  }

  Future<void> _refresh() async {
    if (!widget.isOwner || widget.reload == null || _loading) return;
    setState(() => _loading = true);
    try {
      final next = await widget.reload!();
      if (next.business != widget.businessId) {
        throw StateError('Business changed');
      }
      if (mounted) {
        setState(() {
          _data = next;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Saved transactions could not be refreshed.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _invoice(ReportPeriodEntry entry) async {
    final doc = entry.invoice;
    if (doc == null || !widget.isOwner) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: doc['id'].toString(),
          isOwner: true,
          roleCode: 'owner',
          canManageExpenses: true,
          initialDocumentSummary: doc,
          sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Widget _registerRow(List<String> values, {bool header = false, VoidCallback? onTap}) {
    const widths = [110.0, 100.0, 210.0, 130.0, 120.0, 120.0, 120.0];
    return Material(color: header ? const Color(0xFFE1EEFD) : Colors.white,
      child: InkWell(onTap: onTap, child: Row(children: [
        for (var i = 0; i < values.length; i++) SizedBox(width: widths[i],
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Text(values[i], textAlign: i >= 4 ? TextAlign.right : TextAlign.left,
              style: TextStyle(fontWeight: header ? FontWeight.w700 : FontWeight.w500)))),
      ])));
  }
  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner || widget.data.business != widget.businessId) {
      return const Scaffold(
        body: Center(child: Text('Owner access is required.')),
      );
    }
    final report = OwnerReportPeriod(_data, widget.period, _basis);
    final entries = report.entries, totals = report.totals;
    final payments = _basis == ReportTransactionBasis.payments;
    final range =
        '${DateFormat('MMM d').format(widget.period.start)} – ${DateFormat('MMM d, yyyy').format(widget.period.end)}';
    return Scaffold(
      backgroundColor: taskCanvas,
      appBar: ApprovedTasksHeader(
        title: payments ? 'Payments Received' : 'Sales Register',
        subtitle: range,
        actions: [
          IconButton(
            tooltip: 'Refresh local transactions',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      bottomNavigationBar: widget.sharedBottomNavigationBar,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<ReportTransactionBasis>(
                  key: const ValueKey('report-transaction-basis'),
                  initialValue: _basis,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Show',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ReportTransactionBasis.invoices,
                      child: Text('Sales register'),
                    ),
                    DropdownMenuItem(
                      value: ReportTransactionBasis.payments,
                      child: Text('Payments received'),
                    ),
                    DropdownMenuItem(
                      value: ReportTransactionBasis.unpaid,
                      child: Text('Unpaid / Needs Review'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _basis = v);
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  payments
                      ? 'Payments are selected by payment date. They may include older invoices or other income.'
                      : _basis == ReportTransactionBasis.unpaid
                      ? 'Outstanding invoices through the selected end date. These are separate from money received.'
                      : 'Invoices by invoice date. Paid and balance are through the selected end date. Swipe sideways for all columns.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: BriskersColors.secondaryText,
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: BriskersColors.destructive),
                  ),
                if (report.undated)
                  const Text(
                    'Some entries have no date. Period totals need review.',
                    style: TextStyle(color: BriskersColors.destructive),
                  ),
                if (entries.any((r) => r.review))
                  const Text(
                    'Some payment references need review. Their amounts cannot yet be confirmed as separate receipts.',
                    style: TextStyle(color: BriskersColors.destructive),
                  ),
              ],
            ),
          ),
          Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: SizedBox(width: 910, child: Column(children: [
              _registerRow(['Date', 'Invoice', 'Customer', 'Status', payments ? 'Received' : 'Amount', 'Paid', 'Balance'], header: true),
              Expanded(child: ListView.builder(
                key: ValueKey('period-transaction-list-${_basis.name}'),
                itemCount: entries.length + 1,
                itemBuilder: (context, index) {
                  if (index == entries.length) {
                    return Column(children: [
                      _registerRow(['', '', '${entries.length} ${payments ? 'payments' : 'invoices'}', 'Totals', _money(totals.gross), _money(totals.paid), _money(totals.amountDue)], header: true),
                      _registerRow(['', '', 'Total excluding tax', '', _money(totals.net), '', ''], header: true),
                      _registerRow(['', '', payments ? 'Tax collected' : 'Tax billed', '', _money(totals.tax), '', ''], header: true),
                    ]);
                  }
                  final entry = entries[index];
                  final status = entry.paid == null || entry.amountDue == null ? 'Needs review'
                    : entry.amountDue == 0 ? 'Paid' : entry.paid! > 0 ? 'Partly paid' : 'Open';
                  return _registerRow([
                    entry.date == null ? 'Date missing' : DateFormat('MMM d, yyyy').format(entry.date!),
                    entry.invoiceNumber.isEmpty ? '—' : '#${entry.invoiceNumber}', entry.name,
                    status, _money(entry.gross), _money(entry.paid),
                    entry.invoice == null ? '—' : _money(entry.amountDue),
                  ], onTap: entry.invoice == null ? null : () => _invoice(entry));
                },
              )),
            ])),
          )),
        ],
      ),
    );
  }
}
