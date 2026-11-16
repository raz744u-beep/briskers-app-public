import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'approved_tasks_ui.dart';

import '../../core/connection_mode.dart';
import '../../services/briskers_api.dart';
import '../../services/local_financial_cache.dart';
import '../../services/local_invoice_task_store.dart';

typedef ArchiveSearch =
    Future<List<Map<String, dynamic>>> Function(
      String search,
      int offset,
      int limit,
    );

/// Original expense entries have no verified employee foreign key. This view
/// deliberately has no payment repository, write callback or balance calculation.
class HistoricalExpenseReview extends StatefulWidget {
  const HistoricalExpenseReview({
    super.key,
    required this.initialSearch,
    required this.access,
    required this.canView,
    required this.search,
    required this.source,
    this.exactDate,
  });

  final String initialSearch;
  final ValueListenable<bool> access;
  final bool Function() canView;
  final ArchiveSearch search;
  final String source;
  final DateTime? exactDate;

  static Future<void> open(
    BuildContext context, {
    required String businessId,
    required String employeeName,
    required ValueListenable<bool> access,
    required bool Function() canView,
    required LocalFinancialCache cache,
    DateTime? exactDate,
  }) async {
    if (!canView()) return;
    final offline = BriskersConnectionModeController.instance.forceOffline;
    final cutoff = DateTime.parse(LocalInvoiceTaskStore.payrollCutover);
    final end = DateTime(cutoff.year, cutoff.month, cutoff.day - 1);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HistoricalExpenseReview(
          initialSearch: employeeName,
          access: access,
          canView: canView,
          exactDate: exactDate,
          source: offline
              ? 'Expenses saved on this device'
              : 'Shop expense records',
          search: (query, offset, limit) async {
            if (!canView()) throw StateError('Owner access required.');
            if (offline) {
              final rows = await cache.loadTransactions(
                businessId,
                startDate: exactDate,
                endDate: exactDate ?? end,
                search: query,
                direction: 'expense',
              );
              return rows.skip(offset).take(limit).toList();
            }
            return const BriskersApi().transactionsPaged(
              businessId,
              startDate: exactDate,
              endDate: exactDate ?? end,
              search: query.isEmpty ? null : query,
              direction: 'expense',
              offset: offset,
              limit: limit,
            );
          },
        ),
      ),
    );
  }

  @override
  State<HistoricalExpenseReview> createState() =>
      _HistoricalExpenseReviewState();
}

class _HistoricalExpenseReviewState extends State<HistoricalExpenseReview> {
  late final _text = TextEditingController(text: widget.initialSearch);
  final _rows = <Map<String, dynamic>>[];
  static const _size = 40;
  String _query = '';
  int _offset = 0;
  int _generation = 0;
  bool _more = false;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.access.addListener(_accessChanged);
    _load(reset: true);
  }

  void _accessChanged() {
    if (!widget.access.value || !widget.canView()) {
      _generation++;
      setState(() {
        _rows.clear();
        _loading = false;
        _more = false;
      });
    }
  }

  @override
  void dispose() {
    widget.access.removeListener(_accessChanged);
    _text.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (!widget.access.value || !widget.canView()) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      if (reset) {
        _rows.clear();
        _query = _text.text.trim();
        _offset = 0;
        _more = false;
      }
    });
    try {
      final page = await widget.search(_query, _offset, _size);
      if (!mounted || generation != _generation || !widget.canView()) return;
      final ids = _rows.map((row) => row['id']).toSet();
      setState(() {
        _rows.addAll(
          page.where(
            (row) =>
                row['id'] != null &&
                _matches(row, _query) &&
                ids.add(row['id']),
          ),
        );
        _offset += page.length;
        _more = page.length == _size;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  static bool _matches(Map<String, dynamic> row, String query) {
    final needle = query.trim().toLowerCase();
    return needle.isEmpty ||
        ['counterparty', 'payee_text', 'category', 'remarks'].any(
          (key) => (row[key]?.toString().toLowerCase() ?? '').contains(needle),
        );
  }

  String _amount(Map<String, dynamic> row) {
    final amount = num.tryParse(row['amount']?.toString() ?? '');
    if (amount == null) return 'Amount unavailable';
    final currency = row['currency_code']?.toString() ?? 'USD';
    return NumberFormat.currency(
      locale: 'en_US',
      name: currency,
      symbol: currency == 'USD' ? r'$' : '$currency ',
      decimalDigits: 2,
    ).format(amount);
  }

  String _date(Map<String, dynamic> row) {
    final date = DateTime.tryParse(row['transaction_date']?.toString() ?? '');
    return date == null ? 'Date unavailable' : DateFormat.yMMMd().format(date);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: taskCanvas,
    appBar: AppBar(title: const Text('Historical Expense Review')),
    body: !widget.access.value || !widget.canView()
        ? const Center(child: Text('Owner access required.'))
        : SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                TextField(
                  controller: _text,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(reset: true),
                  decoration: InputDecoration(
                    hintText: 'Payee, category or remarks',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Search expenses',
                      onPressed: () => _load(reset: true),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'A matching payee does not establish a payroll payment. Historical expenses do not change payroll balances.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.exactDate == null
                      ? '${widget.source} · Through Nov 8, 2026'
                      : '${widget.source} · ${DateFormat.yMMMd().format(widget.exactDate!)}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (_loading) const LinearProgressIndicator(),
                if (_failed)
                  TextButton(
                    onPressed: () => _load(reset: false),
                    child: const Text(
                      'Expense records could not be loaded. Retry',
                    ),
                  ),
                if (!_loading && !_failed && _rows.isEmpty)
                  const Text('No matching expenses in this source.'),
                for (final row in _rows)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.white,
                    child: ExpansionTile(
                      key: ValueKey(row['id']),
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              (row['counterparty'] ??
                                      row['payee_text'] ??
                                      'Unspecified payee')
                                  .toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _amount(row),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      subtitle: Text(_date(row)),
                      children: [
                        for (final field in [
                          ('category', 'Category'),
                          ('account', 'Account'),
                          ('remarks', 'Remarks'),
                          ('status', 'Status'),
                        ])
                          if (row[field.$1] != null &&
                              row[field.$1].toString().trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 76,
                                    child: Text(
                                      '${field.$2}:',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(row[field.$1].toString()),
                                  ),
                                ],
                              ),
                            ),
                        const SizedBox(height: 5),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(
                            'Transaction ID: ${row['id']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_more && !_loading && !_failed)
                  TextButton(
                    onPressed: () => _load(reset: false),
                    child: const Text('Load more'),
                  ),
              ],
            ),
          ),
  );
}
