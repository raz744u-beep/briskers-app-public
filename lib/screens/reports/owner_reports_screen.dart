import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/owner_report_models.dart';
import 'owner_report_transactions_screen.dart';
import '../../services/local_owner_reports.dart';
import '../../services/owner_report_preferences.dart';
import '../../widgets/briskers_curved_tabs.dart';
import '../../widgets/briskers_dialog.dart';
import '../../widgets/owner_report_trend.dart';
import '../customers/customer_detail_screen.dart';
import '../jobs/job_detail_screen.dart';
import '../jobs/job_document_screen.dart';
import '../payroll/approved_tasks_ui.dart';
import '../payroll/owner_payroll_screen.dart';

class OwnerReportsScreen extends StatefulWidget {
  const OwnerReportsScreen({super.key, required this.businessId, required this.isOwner,
    this.sharedBottomNavigationBar, this.repository});
  final String businessId;
  final bool isOwner;
  final Widget? sharedBottomNavigationBar;
  final LocalOwnerReports? repository;
  @override
  State<OwnerReportsScreen> createState() => _OwnerReportsScreenState();
}

class _OwnerReportsScreenState extends State<OwnerReportsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs;
  late LocalOwnerReports _repository;
  late OwnerReportPreferences _preferences;
  OwnerReportData? _data;
  late ReportPeriod _period;
  List<OwnerReportMetric> _tiles = [...OwnerReportMetric.defaults];
  Timer? _timer;
  int _revision = -1, _generation = 0, _periodEdits = 0;
  bool _loading = false, _again = false;
  String? _error;
  String _customerQuery = '', _itemQuery = '', _customerRank = 'Sales', _itemRank = 'Revenue', _itemFilter = 'All Items';
  bool _allCustomers = false, _allItems = false;
  final _customerSearch = TextEditingController();
  final _itemSearch = TextEditingController();
  static final _currency = NumberFormat.simpleCurrency(locale: 'en_US');
  String _money(int? cents) => cents == null ? 'Not recorded' : _currency.format(cents / 100);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 5, vsync: this)..addListener(_tabChanged);
    _period = ReportPeriod.preset('thisMonth', DateTime.now());
    _scope();
  }
  void _scope() {
    _generation++;
    _customerQuery = _itemQuery = '';
    _customerSearch.clear(); _itemSearch.clear();
    _repository = widget.repository ?? LocalOwnerReports();
    _preferences = OwnerReportPreferences(widget.businessId);
    _timer?.cancel();
    if (!widget.isOwner) return;
    unawaited(_load(preferences: true));
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_checkRevision()));
  }
  @override
  void didUpdateWidget(covariant OwnerReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId || oldWidget.isOwner != widget.isOwner || oldWidget.repository != widget.repository) {
      _data = null; _revision = -1; _scope();
    }
  }
  void _tabChanged() { if (mounted) setState(() {}); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }
  @override
  void dispose() {
    _generation++; _timer?.cancel(); _tabs.dispose();
    _customerSearch.dispose(); _itemSearch.dispose();
    WidgetsBinding.instance.removeObserver(this); super.dispose();
  }
  Future<void> _checkRevision() async {
    if (!mounted || !widget.isOwner || _loading || ModalRoute.of(context)?.isCurrent == false) return;
    try { if (await _repository.revision() != _revision) await _load(); }
    catch (_) { /* Retain the last consistent snapshot until Refresh succeeds. */ }
  }
  Future<void> _load({bool preferences = false}) async {
    if (!widget.isOwner || !mounted) return;
    if (_loading) { _again = true; return; }
    _loading = true;
    final generation = _generation, business = widget.businessId, periodEdits = _periodEdits;
    try {
      final before = await _repository.revision();
      final data = await _repository.load(business, isOwner: widget.isOwner);
      final tiles = preferences ? await _preferences.tiles() : _tiles;
      final period = preferences ? await _preferences.period(DateTime.now()) : _period;
      if (mounted && generation == _generation && business == widget.businessId && widget.isOwner) {
        setState(() { _data = data; _tiles = tiles; if (periodEdits == _periodEdits) _period = period; _error = null; _revision = before; });
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'Saved reports could not be read. Please refresh.');
    } finally {
      _loading = false;
      if (_again && mounted) { _again = false; unawaited(_load(preferences: generation != _generation)); }
    }
  }
  Future<void> _open(Widget page) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await _load();
  }
  Future<void> _setPeriod(ReportPeriod period) async {
    if (!mounted) return;
    _periodEdits++;
    setState(() => _period = period);
    try {
      await _preferences.savePeriod(period);
    } catch (_) { if (mounted) _notice('The period changed, but could not be saved for next time.'); }
  }
  void _notice(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _choosePeriod() async {
    final choice = await showDialog<String>(context: context, builder: (context) => BriskersDialog(
      title: 'Report period', content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final entry in const {'thisMonth':'This Month','lastMonth':'Last Month','30days':'Last 30 Days',
          '60days':'Last 60 Days','90days':'Last 90 Days','thisYear':'This Year','custom':'Custom Dates'}.entries)
          ListTile(key: ValueKey('report-period-${entry.key}'), selected: _period.preset == entry.key,
            selectedTileColor: const Color(0xFFDCEBFE), title: Text(entry.value),
            trailing: _period.preset == entry.key ? const Icon(Icons.check, color: BriskersColors.tabBlue) : null,
            onTap: () => Navigator.pop(context, entry.key)),
      ]), actions: [OutlinedButton(style: BriskersDialog.cancelStyle,
        onPressed: () => Navigator.pop(context), child: const Text('Cancel'))]));
    if (choice == null || !mounted) return;
    if (choice != 'custom') { await _setPeriod(ReportPeriod.preset(choice, DateTime.now())); return; }
    final dates = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _period.start, end: _period.end),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: BriskersColors.tabBlue)), child: child!));
    if (dates != null && mounted) await _setPeriod(ReportPeriod(dates.start, dates.end));
  }

  static ({IconData icon, Color color}) _style(OwnerReportMetric metric) => switch (metric) {
    OwnerReportMetric.income => (icon: Icons.account_balance_wallet_outlined, color: const Color(0xFF159D2A)),
    OwnerReportMetric.expenses => (icon: Icons.receipt_long_outlined, color: const Color(0xFFF28B0B)),
    OwnerReportMetric.net => (icon: Icons.bar_chart, color: const Color(0xFF1674E9)),
    OwnerReportMetric.sales => (icon: Icons.sell_outlined, color: const Color(0xFF8435C8)),
    OwnerReportMetric.projected => (icon: Icons.auto_graph, color: BriskersColors.confirm),
    OwnerReportMetric.openJobs => (icon: Icons.build_outlined, color: BriskersColors.jobs),
    OwnerReportMetric.averageSale => (icon: Icons.trending_up, color: BriskersColors.tabPurple),
    OwnerReportMetric.salesTax => (icon: Icons.calculate_outlined, color: BriskersColors.tabGray),
    OwnerReportMetric.grossSales => (icon: Icons.receipt_long_outlined, color: BriskersColors.invoices),
    OwnerReportMetric.billedSales => (icon:Icons.sell_outlined,color:BriskersColors.tabPurple),
    OwnerReportMetric.billedTax => (icon:Icons.calculate_outlined,color:BriskersColors.tabGray),
    OwnerReportMetric.billedGross => (icon:Icons.receipt_long_outlined,color:BriskersColors.invoices),
  };

  Future<void> _chooseTile(int slot) async {
    final choice = await showDialog<OwnerReportMetric>(context: context, builder: (context) => BriskersDialog(
      title: 'Choose report for tile ${slot + 1}', icon: Icons.dashboard_customize_outlined,
      content: Column(mainAxisSize: MainAxisSize.min, children: [for (final metric in OwnerReportMetric.values)
        ListTile(key: ValueKey('choose-report-${metric.name}'),
          leading: Icon(_style(metric).icon, color: _style(metric).color),
          title: Text(metric.label), subtitle: Text(metric.description),
          trailing: _tiles[slot] == metric ? const Icon(Icons.check, color: BriskersColors.confirm) : null,
          onTap: () => Navigator.pop(context, metric)),
      ]), actions: [OutlinedButton(style: BriskersDialog.cancelStyle,
        onPressed: () => Navigator.pop(context), child: const Text('Cancel'))]));
    if (choice == null || !mounted) return;
    final next = [..._tiles]..[slot] = choice;
    try { await _preferences.saveTiles(next); if (mounted) setState(() => _tiles = next); }
    catch (_) { if (mounted) _notice('The tile selection could not be saved.'); }
  }

  Widget _tile(String title, String value, IconData icon, Color color, {String? subtitle, VoidCallback? onTap,
    VoidCallback? onEdit, Key? key}) => Material(key: key, color: Colors.white,
      borderRadius: BorderRadius.circular(18), elevation: 1,
      child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, onLongPress: onEdit,
        child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1E8F4), width: 2),
          gradient: LinearGradient(colors: [Colors.white, color.withValues(alpha: .18)])),
          child: onEdit == null ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [CircleAvatar(radius: 15, backgroundColor: color.withValues(alpha: .12),
              child: Icon(icon, color: color, size: 22)), const SizedBox(width: 6),
              Expanded(child: Text(title, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.1, fontWeight: FontWeight.w800))),
            ]), const Spacer(),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value,
              style: const TextStyle(fontSize: 25, height: 1.1, fontWeight: FontWeight.w800, color: Color(0xFF111A31)))),
          ]) : Stack(children: [
            Row(children: [CircleAvatar(radius: MediaQuery.sizeOf(context).width < 350 ? 15 : 21,
                backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color, size: 26)), const SizedBox(width: 8),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(right: 28), child: Text(title, maxLines: 3,
                  style: const TextStyle(fontSize: 13, height: 1.1, fontWeight: FontWeight.w800))),
                const SizedBox(height: 4),
                FittedBox(fit: BoxFit.scaleDown, child: Text(value,
                  style: const TextStyle(fontSize: 25, height: 1.1, fontWeight: FontWeight.w800, color: Color(0xFF111A31)))),
                if (subtitle != null) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, height: 1.1, color: BriskersColors.secondaryText)),
              ])),
            ]),
            Positioned(top: -8, right: -8, child: IconButton(
              key: ValueKey('edit-${key is ValueKey ? key.value : title}'),
              tooltip: 'Change report', iconSize: 16, onPressed: onEdit, icon: const Icon(Icons.edit_outlined))),
          ]))));

  Widget _tableRow({String? index, required String title, required String quantity, required String value,
    VoidCallback? onTap, bool header = false}) {
    final style = TextStyle(fontSize: header ? 11 : 13, fontWeight: header ? FontWeight.w800 : FontWeight.w600);
    return Material(color: header ? const Color(0xFFE8EDF6) : Colors.transparent,
      child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE1E8F4)))),
        child: Row(children: [
          SizedBox(width: 24, child: header ? Text('#', style: style) : CircleAvatar(radius: 12,
            backgroundColor: const Color(0xFFDCEBFE), child: Text(index ?? '', style: style))),
          const SizedBox(width: 6),
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: style)),
          SizedBox(width: 46, child: Text(quantity, textAlign: TextAlign.center, style: style)),
          SizedBox(width: 82, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight,
            child: Text(value, style: style))),
        ]))));
  }

  Widget _card(Widget child) => Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE1E8F4)), boxShadow: const [BoxShadow(color: Color(0x11052749), blurRadius: 4, offset: Offset(0, 2))]), child: Material(color: Colors.transparent, child: child));

  Widget _overview(OwnerReportData data) {
    final summary = data.summary(_period);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: 4,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2,
          mainAxisExtent: MediaQuery.textScalerOf(context).scale(110),
          crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemBuilder: (context, index) {
          final metric = _tiles[index];
          final value = summary.values[metric];
          final style = _style(metric);
          return _tile(metric.label, metric.isCount ? '${value ?? '—'}' : _money(value), style.icon, style.color,
            key: ValueKey('overview-report-tile-$index'),
            subtitle: metric == OwnerReportMetric.projected ? 'Open jobs · known costs' : metric == OwnerReportMetric.net ? 'Received less expenses' :
              metric == OwnerReportMetric.income ? 'By payment date' :
              const {OwnerReportMetric.sales,OwnerReportMetric.salesTax,OwnerReportMetric.grossSales,OwnerReportMetric.averageSale}.contains(metric) ? 'By payment date' :
              const {OwnerReportMetric.billedSales,OwnerReportMetric.billedTax,OwnerReportMetric.billedGross}.contains(metric)?'By invoice date':null,
            onEdit: () => _chooseTile(index), onTap: () => _metricDetails(metric));
        }),
      const SizedBox(height: 9),
      const Text('Tap a tile for details · pencil to choose its report', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: BriskersColors.secondaryText)),
      TextButton.icon(key:const ValueKey('view-period-transactions'),onPressed:()=>_periodTransactions(ReportTransactionBasis.invoices),
        icon:const Icon(Icons.receipt_long_outlined),label:const Text('View sales register')),
      const SizedBox(height: 14),
      _card(OwnerReportTrend(data: data, period: _period)),
      for (final issue in summary.issues) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(issue,
        style: const TextStyle(fontSize: 12, color: BriskersColors.secondaryText))),
    ]);
  }

  Future<void> _periodTransactions(ReportTransactionBasis basis) async {
    final data=_data;if(data==null)return;
    await _open(OwnerReportTransactionsScreen(businessId:widget.businessId,isOwner:widget.isOwner,data:data,period:_period,
      initialBasis:basis,sharedBottomNavigationBar:widget.sharedBottomNavigationBar,
      reload:()=>_repository.load(widget.businessId,isOwner:widget.isOwner)));
  }

  Future<void> _metricDetails(OwnerReportMetric metric) async {
    if(metric==OwnerReportMetric.income) {await _periodTransactions(ReportTransactionBasis.payments);return;}
    if(const {OwnerReportMetric.sales,OwnerReportMetric.salesTax,OwnerReportMetric.grossSales,OwnerReportMetric.averageSale}.contains(metric)) {
      await _periodTransactions(ReportTransactionBasis.payments);return;
    }
    if(const {OwnerReportMetric.billedSales,OwnerReportMetric.billedTax,OwnerReportMetric.billedGross}.contains(metric)){
      await _periodTransactions(ReportTransactionBasis.invoices);return;
    }
    final data = _data; if (data == null) return;
    await showDialog<void>(context: context, builder: (context) => BriskersDialog(title: metric.label,
      icon: _style(metric).icon, content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(metric.description), const SizedBox(height: 12),
          if (metric == OwnerReportMetric.projected || metric == OwnerReportMetric.openJobs) ...[
            const Text('Current open jobs · independent of the date range', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final job in data.openJobs) Builder(builder: (context) {
              final figure = data.jobFigure(job, projected: true);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ListTile(contentPadding: EdgeInsets.zero,
                  title: Text('${job['job_number'] ?? 'Job'} · ${job['customer_name'] ?? job['title'] ?? ''}'),
                  subtitle: Text('Sales ${_money(figure.sales)} · Expenses ${_money(figure.expenses)}\nAssigned labor ${_money(figure.labor)}'),
                  trailing: Text(_money(figure.profit), style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () { Navigator.pop(context); unawaited(_open(JobDetailScreen(businessId: widget.businessId,
                    jobId: job['id'].toString(), roleCode: 'owner', bottomNavigationBar: widget.sharedBottomNavigationBar))); }),
                for (final issue in figure.issues) Text(issue, style: const TextStyle(fontSize: 12, color: BriskersColors.secondaryText)),
                const Divider(),
              ]);
            }),
            if (data.openJobs.isEmpty) const Text('No open jobs.'),
            const Text('This is a known-cost estimate, not money received. Costs not yet recorded and unallocated shop overhead are not included.',
              style: TextStyle(fontSize: 12, color: BriskersColors.secondaryText)),
          ] else if (const {OwnerReportMetric.sales, OwnerReportMetric.salesTax, OwnerReportMetric.averageSale}.contains(metric)) ...[
            for (final doc in data.invoicesIn(_period)) ListTile(contentPadding: EdgeInsets.zero,
              title: Text('Invoice #${doc['document_number'] ?? ''} · ${doc['customer_name'] ?? 'Customer'}'),
              trailing: Text(_money(metric == OwnerReportMetric.salesTax ? reportCents(doc['tax_amount']) : OwnerReportData.salesOf(doc))),
              onTap: () { Navigator.pop(context); unawaited(_invoice(doc)); }),
          ] else ...[
            for (final row in data.transactions.where((r) => _period.contains(r['transaction_date']) &&
              (metric == OwnerReportMetric.net || r['direction'] == (metric == OwnerReportMetric.income ? 'income' : 'expense'))))
              ListTile(contentPadding: EdgeInsets.zero,
                title: Text(row['counterparty']?.toString() ?? row['direction']?.toString() ?? 'Transaction'),
                subtitle: Text(row['transaction_date']?.toString() ?? ''),
                trailing: Text(_money(reportCents(row['reporting_status'] == 'verified' ? row['reporting_amount'] ?? row['amount'] : row['amount'])))),
          ],
        ])), actions: [OutlinedButton(style: BriskersDialog.cancelStyle,
          onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
  }

  Future<void> _invoice(ReportRow doc) => _open(JobDocumentScreen(businessId: widget.businessId,
    documentId: doc['id'].toString(), isOwner: true, roleCode: 'owner', canManageExpenses: true,
    initialDocumentSummary: doc, sharedBottomNavigationBar: widget.sharedBottomNavigationBar));

  Widget _summaries(List<({String title, String value, IconData icon, Color color})> entries) => SizedBox(height: MediaQuery.textScalerOf(context).scale(112),
    child: Row(children: [for (final (index, entry) in entries.indexed) ...[
      if (index != 0) const SizedBox(width: 7),
      Expanded(child: _tile(entry.title, entry.value, entry.icon, entry.color)),
    ]]));
  Widget _selector(String value, List<String> values, ValueChanged<String> changed, {String? label, bool expanded = false}) => DropdownButton<String>(
    value: value, isDense: true, isExpanded: expanded, underline: const SizedBox.shrink(),
    items: [for (final v in values) DropdownMenuItem(value: v, child: Text(v))],
    onChanged: (v) { if (v != null) changed(v); }, hint: label == null ? null : Text(label));

  Widget _customers(OwnerReportData data) {
    final customers = data.customers(_period);
    final rows = customers.where((r) => r.name.toLowerCase().contains(_customerQuery.toLowerCase())).toList();
    rows.sort((a, b) => switch (_customerRank) {
      'Profitability' => (b.profit ?? -0x7FFFFFFFFFFFFFFF).compareTo(a.profit ?? -0x7FFFFFFFFFFFFFFF),
      'Visits' => b.jobs.length.compareTo(a.jobs.length),
      _ => b.sales.compareTo(a.sales),
    });
    final newCount = customers.where((r) => r.newCustomer).length;
    final salesKnown = customers.every((r) => r.salesKnown), balanceKnown = customers.every((r) => r.balanceKnown);
    final sales = customers.fold<int>(0, (sum, r) => sum + r.sales), balance = customers.fold<int>(0, (sum, r) => sum + r.balance);
    final count = customers.fold<int>(0, (sum, r) => sum + r.invoices);
    final shown = _allCustomers ? rows : rows.take(5).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _summaries([
        (title: 'Total Customers', value: '${customers.length}', icon: Icons.people_outline, color: BriskersColors.tabBlue),
        (title: 'New Customers', value: '$newCount', icon: Icons.person_add_alt, color: BriskersColors.confirm),
        (title: 'Repeat Customers', value: '${customers.length - newCount}', icon: Icons.refresh, color: BriskersColors.tabPurple),
      ]),
      const SizedBox(height: 14),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [const Expanded(child: Text('Top Customers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          TextButton(onPressed: () => setState(() => _allCustomers = !_allCustomers), child: Text(_allCustomers ? 'Top 5' : 'View All'))]),
        TextField(key: const ValueKey('report-customer-search'), controller: _customerSearch, decoration: const InputDecoration(
          hintText: 'Search customers', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
          onChanged: (v) => setState(() => _customerQuery = v)),
        const SizedBox(height: 10),
        Row(children: [const Text('Rank by '), const SizedBox(width: 8),
          Expanded(child: _selector(_customerRank, const ['Sales','Profitability','Visits'],
            (v) => setState(() => _customerRank = v), expanded: true))]),
        const Divider(),
        _tableRow(title: 'Customer', quantity: 'Jobs', value: _customerRank == 'Visits' ? 'Visits' : _customerRank == 'Profitability' ? 'Profit' : 'Revenue', header: true),
        for (final (index, r) in shown.indexed) _tableRow(index: '${index + 1}', title: r.name,
          quantity: '${r.jobs.length}', value: _customerRank == 'Visits' ? '${r.jobs.length}' : _money(
            _customerRank == 'Profitability' ? r.profit : r.salesKnown ? r.sales : null),
          onTap: () => _customerDetails(r)),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No customers in this period.')),
        const Divider(),
        Text('Customer sales: ${_money(salesKnown ? sales : null)}\nAverage sale: ${_money(!salesKnown ? null : count == 0 ? 0 : (sales / count).round())}\nOutstanding balances: ${_money(balanceKnown ? balance : null)}',
          style: const TextStyle(fontSize: 12, height: 1.6)),
        const SizedBox(height: 8),
        const Text('New and repeat customers are based on their first saved invoice. Profit uses recorded job costs; incomplete job history is marked Not recorded.',
          style: TextStyle(fontSize: 11, color: BriskersColors.secondaryText)),
      ])),
      _trendLink('Customer Activity Trend', () => _activity(data, customers: true)),
    ]);
  }

  Future<void> _customerDetails(CustomerReportRow row) async {
    await showDialog<void>(context: context, builder: (context) => BriskersDialog(title: row.name,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Sales excluding tax: ${_money(row.salesKnown ? row.sales : null)}\nRecorded job profit: ${_money(row.profit)}\nOutstanding balance: ${_money(row.balanceKnown ? row.balance : null)}'),
        const SizedBox(height: 12),
        for (final doc in row.documents) ListTile(contentPadding: EdgeInsets.zero,
          title: Text('Invoice #${doc['document_number'] ?? ''}'), trailing: Text(_money(OwnerReportData.salesOf(doc))),
          onTap: () { Navigator.pop(context); unawaited(_invoice(doc)); }),
      ]), actions: [OutlinedButton(style: BriskersDialog.cancelStyle, onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(style: BriskersDialog.confirmStyle(), onPressed: () {
          Navigator.pop(context); unawaited(_open(CustomerDetailScreen(businessId: widget.businessId, customerId: row.id,
            roleCode: 'owner', sharedBottomNavigationBar: widget.sharedBottomNavigationBar)));
        }, child: const Text('Customer details'))]));
  }

  Widget _items(OwnerReportData data) {
    final all = data.items(_period);
    final rows = all.where((r) => (_itemFilter != 'Parts Only' || !r.labor) &&
      (_itemFilter != 'Labor Only' || r.labor) && r.name.toLowerCase().contains(_itemQuery.toLowerCase())).toList();
    rows.sort((a, b) => switch (_itemRank) {
      'Quantity' => b.quantity.compareTo(a.quantity),
      'Cost' => (b.cost ?? -1).compareTo(a.cost ?? -1),
      'Profit' => (b.profit ?? -0x7FFFFFFFFFFFFFFF).compareTo(a.profit ?? -0x7FFFFFFFFFFFFFFF),
      _ => b.revenue.compareTo(a.revenue),
    });
    final shown = _allItems ? rows : rows.take(5).toList();
    final parts = rows.where((r) => !r.labor && !r.discount).toList();
    final quantity = parts.fold<double>(0, (sum, r) => sum + r.quantity);
    final partsRevenue = parts.fold<int>(0, (sum, r) => sum + r.revenue);
    final revenue = rows.fold<int>(0, (sum, r) => sum + r.revenue);
    final costKnown = rows.every((r) => r.cost != null);
    final cost = rows.fold<int>(0, (sum, r) => sum + (r.cost ?? 0));
    final profit = costKnown ? revenue - cost : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _summaries([
        (title: 'Items Sold\nParts / Materials', value: NumberFormat('#,##0.##').format(quantity), icon: Icons.inventory_2_outlined, color: BriskersColors.tabBlue),
        (title: 'Item Revenue\nSales Excl. Tax', value: _money(revenue), icon: Icons.payments_outlined, color: BriskersColors.confirm),
        (title: 'Avg. Sale\nper Item', value: _money(quantity == 0 ? 0 : (partsRevenue / quantity).round()), icon: Icons.trending_up, color: BriskersColors.tabPurple),
      ]),
      const SizedBox(height: 14),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [const Expanded(child: Text('Top-Selling Items', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          TextButton(onPressed: () => setState(() => _allItems = !_allItems), child: Text(_allItems ? 'Top 5' : 'View All'))]),
        TextField(key: const ValueKey('report-item-search'), controller: _itemSearch, decoration: const InputDecoration(
          hintText: 'Search items', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
          onChanged: (v) => setState(() => _itemQuery = v)),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 10, children: [
          _selector(_itemFilter, const ['All Items','Parts Only','Labor Only'], (v) => setState(() => _itemFilter = v)),
          _selector(_itemRank, const ['Revenue','Quantity','Cost','Profit'], (v) => setState(() => _itemRank = v)),
        ]),
        const Divider(),
        _tableRow(title: 'Item / Part', quantity: 'Qty Sold', value: _itemRank, header: true),
        for (final (index, r) in shown.indexed) _tableRow(index: '${index + 1}', title: r.name,
          quantity: '${NumberFormat('#,##0.##').format(r.quantity)}${r.labor ? ' hrs' : ''}',
          value: _itemRank == 'Quantity' ? NumberFormat('#,##0.##').format(r.quantity) :
            _money(_itemRank == 'Cost' ? r.cost : _itemRank == 'Profit' ? r.profit : r.revenue),
          onTap: () => _itemDetails(r)),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No items in this period.')),
        const Divider(),
        Text('Cost: ${_money(costKnown ? cost : null)}\nProfit: ${_money(profit)}\nProfit margin: ${profit == null || revenue <= 0 ? 'Not recorded' : '${(profit * 100 / revenue).toStringAsFixed(1)}%'}',
          style: const TextStyle(fontSize: 12, height: 1.6)),
        const SizedBox(height: 8),
        const Text('Parts quantities and labor hours are kept separate. Cost and profit require saved item-level cost information; missing costs are not treated as zero.',
          style: TextStyle(fontSize: 11, color: BriskersColors.secondaryText)),
      ])),
      _trendLink('Item Sales Trend', () => _activity(data, customers: false)),
    ]);
  }

  Future<void> _itemDetails(ItemReportRow row) async {
    await showDialog<void>(context: context, builder: (context) => BriskersDialog(title: row.name,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Revenue excluding tax: ${_money(row.revenue)}\nCost: ${_money(row.cost)}\nProfit: ${_money(row.profit)}\nMargin: ${row.margin == null ? 'Not recorded' : '${row.margin!.toStringAsFixed(1)}%'}'),
        for (final doc in _data!.invoices.where((r) => row.invoiceIds.contains(r['id'])))
          ListTile(contentPadding: EdgeInsets.zero, title: Text('Invoice #${doc['document_number'] ?? ''} · ${doc['customer_name'] ?? ''}'),
            onTap: () { Navigator.pop(context); unawaited(_invoice(doc)); }),
      ]), actions: [OutlinedButton(style: BriskersDialog.cancelStyle, onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
  }
  Widget _trendLink(String title, VoidCallback onTap) => _card(ListTile(contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.bar_chart, color: BriskersColors.tabBlue), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    trailing: const Icon(Icons.chevron_right), onTap: onTap));
  Future<void> _activity(OwnerReportData data, {required bool customers}) async {
    final start = _period.start, end = _period.end;
    final count = (end.year - start.year) * 12 + end.month - start.month + 1;
    await showDialog<void>(context: context, builder: (context) => BriskersDialog(
      title: customers ? 'Customer Activity Trend' : 'Item Sales Trend',
      content: Column(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < count; i++) Builder(builder: (context) {
        final first = DateTime(start.year, start.month + i);
        final last = DateTime(first.year, first.month + 1, 0);
        final p = ReportPeriod(first.isBefore(start) ? start : first, last.isAfter(end) ? end : last);
        final rows = data.customers(p);
        final items = data.items(p);
        return ListTile(contentPadding: EdgeInsets.zero,
          title: Text(DateFormat('MMM yyyy').format(first)),
          subtitle: Text(customers ? '${rows.length} customers · ${rows.fold<int>(0, (sum, r) => sum + r.jobs.length)} jobs' :
            '${items.fold<double>(0, (sum, r) => sum + (r.labor || r.discount ? 0 : r.quantity)).toStringAsFixed(2)} parts / materials'),
          trailing: Text(_money(customers ? rows.fold<int>(0, (sum, r) => sum + r.sales) : items.fold<int>(0, (sum, r) => sum + r.revenue))));
      })]), actions: [OutlinedButton(style: BriskersDialog.cancelStyle, onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
  }

  Widget _otherTab() => _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(_tabs.index == 1 ? 'Financial reports' : 'Tax reports', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
    const SizedBox(height: 8), Text(_tabs.index == 1
      ? 'Income, expenses and profit are available in Overview.'
      : 'Choose Tax Billed in the Overview report selector to see invoice tax totals.'),
    TextButton.icon(onPressed: () => _tabs.animateTo(0), icon: const Icon(Icons.bar_chart),
      label: const Text('View Overview')),
    if (OwnerPayrollScreen.enabled) TextButton.icon(onPressed: () => _open(OwnerPayrollScreen(businessId: widget.businessId,
      reportsOnly: true, sharedBottomNavigationBar: widget.sharedBottomNavigationBar)),
      icon: const Icon(Icons.receipt_long_outlined), label: const Text('Payroll payment reports')),
  ]));

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) return const Scaffold(body: Center(child: Text('Owner access is required.')));
    final label = switch (_period.preset) {'thisMonth' => 'This Month', 'lastMonth' => 'Last Month', '30days' => 'Last 30 Days',
      '60days' => 'Last 60 Days', '90days' => 'Last 90 Days', 'thisYear' => 'This Year', _ => 'Custom'};
    return Scaffold(backgroundColor: taskCanvas,
      appBar: ApprovedTasksHeader(title: 'Owner Reports', actions: [IconButton(tooltip: 'Refresh local reports',
        onPressed: () => _load(), icon: const Icon(Icons.refresh, color: Colors.white))]),
      bottomNavigationBar: widget.sharedBottomNavigationBar,
      body: Column(children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: MediaQuery.sizeOf(context).width < 560 ? 560 : MediaQuery.sizeOf(context).width,
          child: BriskersCurvedTabs(controller: _tabs, entries: const [
            (label:'Overview', color:BriskersColors.tabBlue, icon:Icons.bar_chart),
            (label:'Financial', color:BriskersColors.tabBlue, icon:Icons.payments_outlined),
            (label:'Taxes', color:BriskersColors.tabBlue, icon:Icons.calculate_outlined),
            (label:'Customers', color:BriskersColors.tabBlue, icon:Icons.people_outline),
            (label:'Items', color:BriskersColors.tabBlue, icon:Icons.inventory_2_outlined),
          ]))),
        Expanded(child: RefreshIndicator(onRefresh: _load, child: ListView(key: ValueKey('owner-report-body-${_tabs.index}'), padding: const EdgeInsets.all(12), children: [
          Container(key: const ValueKey('report-date-range'), margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(
            color: const Color(0xFFDCEBFE), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              IconButton(tooltip:'Previous period', onPressed: () => _setPeriod(_period.shift(-1)), icon: const Icon(Icons.chevron_left)),
              Expanded(child: InkWell(onTap: _choosePeriod, child: Padding(padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.calendar_month_outlined, size: 21),
                  const SizedBox(width: 7), Flexible(child: Semantics(liveRegion: true, child: Text('$label: ${DateFormat('MMM d').format(_period.start)} – ${DateFormat('MMM d, yyyy').format(_period.end)}',
                    maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)))),
                  const Icon(Icons.arrow_drop_down),
                ])))),
              IconButton(tooltip:'Next period', onPressed: () => _setPeriod(_period.shift(1)), icon: const Icon(Icons.chevron_right)),
            ])),
          if (_error != null) _card(Column(children: [Text(_error!), TextButton(onPressed: () => _load(), child: const Text('Retry'))])),
          if (_data == null && _error == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Reading local reports…')))
          else if (_data != null) ...[
            if (_tabs.index == 0) _overview(_data!)
            else if (_tabs.index == 3) _customers(_data!)
            else if (_tabs.index == 4) _items(_data!)
            else _otherTab(),
            const Text('Calculated from records saved on this device.', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: BriskersColors.secondaryText)),
          ],
        ]))),
      ]));
  }
}
