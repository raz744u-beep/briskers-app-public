import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/connection_mode.dart';
import '../../services/briskers_api.dart';
import '../../services/local_financial_cache.dart';
import '../../services/local_invoice_task_store.dart';

typedef ArchiveSearch = Future<List<Map<String, dynamic>>> Function(
  String search, int offset, int limit,
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

  static Future<void> open(BuildContext context, {
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
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      HistoricalExpenseReview(
        initialSearch: employeeName, access: access, canView: canView,
        exactDate: exactDate,
        source: offline ? 'Expenses saved on this device' : 'Shop expense records',
        search: (query, offset, limit) async {
          if (!canView()) throw StateError('Owner access required.');
          if (offline) {
            final rows = await cache.loadTransactions(businessId,
              startDate: exactDate, endDate: exactDate ?? end,
              search: query, direction: 'expense');
            return rows.skip(offset).take(limit).toList();
          }
          return const BriskersApi().transactionsPaged(businessId,
            startDate: exactDate, endDate: exactDate ?? end,
            search: query.isEmpty ? null : query,
            direction: 'expense', offset: offset, limit: limit);
        },
      )));
  }

  @override
  State<HistoricalExpenseReview> createState() => _HistoricalExpenseReviewState();
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
        _rows.addAll(page.where((row) =>
          row['id'] != null && ids.add(row['id'])));
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Historical expense review')),
    body: !widget.access.value || !widget.canView()
      ? const Center(child: Text('Owner access required.'))
      : ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.source),
        Text(widget.exactDate == null
          ? 'Search original expenses before November 7, 2026. A matching payee does not verify an employee payment. These records do not affect payroll balances.'
          : 'Original expense entries for ${widget.exactDate!.month}/${widget.exactDate!.day}/${widget.exactDate!.year}. Verify the payee, amount and original transaction ID. This read-only review does not mark payroll paid.'),
        TextField(controller: _text, textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(reset: true),
          decoration: InputDecoration(labelText: 'Payee, category or remarks',
            suffixIcon: IconButton(icon: const Icon(Icons.search),
              tooltip: 'Search expenses', onPressed: () => _load(reset: true)))),
        if (_loading) const LinearProgressIndicator(),
        if (_failed) TextButton(onPressed: () => _load(reset: false),
          child: const Text('Expense records could not be loaded. Retry')),
        if (!_loading && !_failed && _rows.isEmpty)
          const Text('No matching expenses in this source.'),
        for (final row in _rows)
          ExpansionTile(key: ValueKey(row['id']),
            title: Text((row['counterparty'] ?? row['payee_text'] ?? 'Unspecified payee').toString()),
            subtitle: Text([row['transaction_date'] ?? 'Date unavailable',
              row['amount'], row['currency_code']].whereType<Object>().join(' · ')),
            children: [ListTile(title: SelectableText('Transaction ID: ${row['id']}'),
              subtitle: Text([row['category'], row['account'], row['status'], row['remarks']]
                .whereType<Object>().join('\n')))]),
        if (_more && !_loading && !_failed) TextButton(onPressed: () => _load(reset: false),
          child: const Text('Load more')),
      ]),
  );
}
