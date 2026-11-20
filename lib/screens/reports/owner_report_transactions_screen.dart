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
    this.initialBasis = ReportTransactionBasis.payments,
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

  Widget _amountCell(String text) => SizedBox(
    width: 88,
    child: Padding(
      padding: const EdgeInsets.only(left: 6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
  Widget _total(String label, int? n, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _money(n),
          style: TextStyle(
            fontSize: 16,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
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
        title: 'Transactions',
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
                      child: Text('Invoices issued'),
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
                      : 'Invoices are selected by original invoice date, including unpaid invoices.',
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
          Container(
            color: const Color(0xFFE7EDF4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    'Invoice / Name',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    'Amount due',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    'Paid',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                key: ValueKey('period-transaction-list-${_basis.name}'),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: entries.isEmpty ? 1 : entries.length,
                itemBuilder: (context, index) {
                  if (entries.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No transactions in this period.'),
                    );
                  }
                  final e = entries[index];
                  return Material(
                    color: Colors.white,
                    child: InkWell(
                      onTap: e.invoice == null ? null : () => _invoice(e),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: BriskersColors.divider),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.invoiceNumber.isEmpty
                                        ? 'Other income'
                                        : '#${e.invoiceNumber}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    e.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  Text(
                                    e.date == null
                                        ? 'Date missing'
                                        : DateFormat('MMM d').format(e.date!),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: BriskersColors.secondaryText,
                                    ),
                                  ),
                                  if (e.invoice != null)
                                    Text(
                                      'Invoice total ${_money(reportCents(e.invoice!['total_amount']))}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: BriskersColors.secondaryText,
                                      ),
                                    ),
                                  if (e.review)
                                    const Text(
                                      'Payment needs review',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: BriskersColors.destructive,
                                      ),
                                    )
                                  else if (e.tax == null)
                                    const Text(
                                      'Tax details not recorded',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: BriskersColors.secondaryText,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            _amountCell(
                              e.invoice == null
                                  ? '—'
                                  : e.amountDue == null
                                  ? 'Review'
                                  : _money(e.amountDue),
                            ),
                            _amountCell(
                              e.paid == null ? 'Review' : _money(e.paid),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Container(
            key: const ValueKey('period-transaction-totals'),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFE1EEFD),
              border: Border(top: BorderSide(color: BriskersColors.divider)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${entries.length} ${payments ? 'payment entries' : 'invoices'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: BriskersColors.secondaryText,
                    ),
                  ),
                ),
                _total('Total including tax', totals.gross, strong: true),
                _total('Total excluding tax', totals.net),
                _total(payments ? 'Tax collected' : 'Tax billed', totals.tax),
                _total('Amount due', totals.amountDue),
                _total('Amount paid', totals.paid),
                Text(
                  'Balances as of ${DateFormat('MMM d, yyyy').format(widget.period.end)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: BriskersColors.secondaryText,
                  ),
                ),
                if (payments && totals.fees != null && totals.fees != 0) ...[
                  const Divider(),
                  _total('Recorded processor fees', totals.fees),
                  _total(
                    'Income received after fees',
                    totals.retained,
                    strong: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
