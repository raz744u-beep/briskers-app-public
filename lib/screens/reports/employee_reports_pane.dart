import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/owner_report_models.dart';
import '../../local/briskers_local_database.dart' show BriskersLocalDatabase;
import '../../services/local_employee_reports.dart';
import '../../services/local_financial_cache.dart' as finance;
import '../expenses/expense_detail_screen.dart';
import '../jobs/job_detail_screen.dart';
import '../jobs/job_document_screen.dart';
import '../payroll/approved_tasks_ui.dart';

class EmployeeReportsPane extends StatefulWidget {
  const EmployeeReportsPane({
    super.key,
    required this.businessId,
    required this.isOwner,
    this.database,
    this.employeeId,
    this.initialPeriod,
    this.sharedBottomNavigationBar,
    this.onPaymentTools,
  });

  final String businessId;
  final bool isOwner;
  final BriskersLocalDatabase? database;
  final String? employeeId;
  final ReportPeriod? initialPeriod;
  final Widget? sharedBottomNavigationBar;
  final VoidCallback? onPaymentTools;

  static ReportPeriod shopWeek(DateTime date) {
    final monday = DateTime(date.year, date.month, date.day - date.weekday + 1);
    return ReportPeriod(
      monday,
      DateTime(monday.year, monday.month, monday.day + 4),
      preset: 'shopWeek',
    );
  }

  @override
  State<EmployeeReportsPane> createState() => EmployeeReportsPaneState();
}

class EmployeeReportsPaneState extends State<EmployeeReportsPane> {
  static const _choices = {
    'shopWeek': 'This Shop Week',
    'thisMonth': 'This Month',
    'lastMonth': 'Last Month',
    'last3Months': 'Last 3 Months',
    'last6Months': 'Last 6 Months',
    'thisYear': 'Year to Date',
    'lastYear': 'Last Year',
    'priorYear': 'Previous Years',
    'custom': 'Custom Dates',
  };
  static final _money = NumberFormat.simpleCurrency(locale: 'en_US');
  static final _shortDate = DateFormat('MMM d');
  static final _fullDate = DateFormat('MMM d, yyyy');
  late ReportPeriod _period;
  late Future<EmployeeReportData> _data;

  bool get _individual => widget.employeeId != null;

  @override
  void initState() {
    super.initState();
    _period =
        widget.initialPeriod ?? EmployeeReportsPane.shopWeek(DateTime.now());
    _data = _load();
  }

  @override
  void didUpdateWidget(covariant EmployeeReportsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.employeeId != widget.employeeId ||
        oldWidget.isOwner != widget.isOwner ||
        oldWidget.database != widget.database) {
      _period =
          widget.initialPeriod ?? EmployeeReportsPane.shopWeek(DateTime.now());
      _data = _load();
    }
  }

  Future<EmployeeReportData> _load() =>
      LocalEmployeeReports(database: widget.database)
          .load(widget.businessId, _period, isOwner: widget.isOwner);

  Future<void> refresh() async {
    if (!mounted || !widget.isOwner) return;
    final future = _load();
    setState(() => _data = future);
    try {
      await future;
    } catch (_) {
      // The report shows the read failure and a retry action.
    }
  }

  Future<void> _selectPeriod(
    String? selection,
    List<int> availableYears,
  ) async {
    if (selection == null) return;
    final now = DateTime.now();
    final today = ReportPeriod.day(now);
    ReportPeriod? next;
    if (selection == 'custom') {
      final dates = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100, 12, 31),
        initialDateRange: DateTimeRange(start: _period.start, end: _period.end),
      );
      if (dates != null) next = ReportPeriod(dates.start, dates.end);
    } else if (selection == 'priorYear') {
      final years = {
        for (final year in availableYears)
          if (year < now.year - 1) year,
        now.year - 2,
      }.toList()..sort((a, b) => b.compareTo(a));
      final year = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Previous Years'),
          children: [
            for (final year in years)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, year),
                child: Text('$year'),
              ),
          ],
        ),
      );
      if (year != null) {
        next = ReportPeriod(
          DateTime(year),
          DateTime(year, 12, 31),
          preset: selection,
        );
      }
    } else if (selection == 'shopWeek') {
      next = EmployeeReportsPane.shopWeek(today);
    } else if (selection == 'lastYear') {
      next = ReportPeriod(
        DateTime(now.year - 1),
        DateTime(now.year - 1, 12, 31),
        preset: selection,
      );
    } else if (selection == 'last3Months' || selection == 'last6Months') {
      final months = selection == 'last3Months' ? 3 : 6;
      final month = DateTime(today.year, today.month - months);
      final lastDay = DateTime(month.year, month.month + 1, 0).day;
      final firstDay = today.day > lastDay ? lastDay : today.day;
      next = ReportPeriod(
        DateTime(month.year, month.month, firstDay),
        today,
        preset: selection,
      );
    } else {
      next = ReportPeriod.preset(selection, today);
    }
    if (!mounted || next == null) return;
    _period = next;
    await refresh();
  }

  String _hours(int? minutes, {bool historical = false}) => minutes == null
      ? 'Review'
      : historical && minutes == 0
      ? '—'
      : '${(minutes / 60).toStringAsFixed(1)} h';

  String _amount(int? cents) =>
      cents == null ? 'Not recorded' : _money.format(cents / 100);

  Widget _card(Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      side: BorderSide(
        color: BriskersColors.secondaryText.withValues(alpha: .28),
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );

  Widget _metric(String label, String value, {bool labelFirst = false}) {
    final caption = Text(
      label,
      style: const TextStyle(color: BriskersColors.secondaryText),
    );
    final amount = Text(
      value,
      style: const TextStyle(
        color: BriskersColors.tabBlue,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: labelFirst ? [caption, amount] : [amount, caption],
    );
  }

  Widget _periodPicker(List<int> years) {
    final date = _period.start == _period.end
        ? _fullDate.format(_period.end)
        : '${_shortDate.format(_period.start)} – ${_fullDate.format(_period.end)}';
    final isOtherWeek =
        _period.preset == 'shopWeek' &&
        _period.start != EmployeeReportsPane.shopWeek(DateTime.now()).start;
    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 2,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _period.preset,
                items: [
                  for (final entry in _choices.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(
                        entry.key == 'shopWeek' && isOtherWeek
                            ? 'Shop Week'
                            : entry.value,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => _selectPeriod(value, years),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            date,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _employeeCard(EmployeeReportRow employee) {
    final displayHours =
        employee.historical ||
        (employee.labor.isEmpty && employee.payments.isNotEmpty);
    return _card(
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: ApprovedTasksHeader(title: employee.name),
                backgroundColor: taskCanvas,
                bottomNavigationBar: widget.sharedBottomNavigationBar,
                body: EmployeeReportsPane(
                  businessId: widget.businessId,
                  isOwner: widget.isOwner,
                  database: widget.database,
                  employeeId: employee.id,
                  initialPeriod: _period,
                  sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
                ),
              ),
            ),
          );
          await refresh();
        },
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      employee.name,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: BriskersColors.tabBlue,
                  ),
                ],
              ),
              if (employee.historical)
                const Text('Historical payroll name')
              else if (employee.inactive)
                const Text('Former employee'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      'Completed',
                      _hours(employee.completed, historical: displayHours),
                    ),
                  ),
                  Expanded(
                    child: _metric(
                      'Paid',
                      _hours(employee.paid, historical: displayHours),
                    ),
                  ),
                  Expanded(
                    child: _metric(
                      'Unpaid',
                      _hours(employee.unpaid, historical: displayHours),
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),
              Row(
                children: [
                  const Text('Payroll paid'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _amount(employee.paidCents),
                      style: const TextStyle(
                        color: BriskersColors.tabBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLabor(EmployeeReportLabor labor) async {
    final invoice = labor.invoiceId;
    final job = labor.jobId;
    if (invoice == null && job == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => invoice != null
            ? JobDocumentScreen(
                businessId: widget.businessId,
                documentId: invoice,
                isOwner: true,
                roleCode: 'owner',
                sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
              )
            : JobDetailScreen(
                businessId: widget.businessId,
                jobId: job!,
                roleCode: 'owner',
                bottomNavigationBar: widget.sharedBottomNavigationBar,
              ),
      ),
    );
    await refresh();
  }

  Future<void> _openPayment(EmployeeReportPayment payment) async {
    final expense = payment.expense;
    final id = expense?['id']?.toString();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => id != null && id.isNotEmpty
            ? ExpenseDetailScreen(
                businessId: widget.businessId,
                transactionId: id,
                cachedDetail: expense,
                allowRecurring: false,
                financialCache: finance.LocalFinancialCache(
                  database: widget.database,
                ),
              )
            : Scaffold(
                appBar: const ApprovedTasksHeader(title: 'Payroll payment'),
                bottomNavigationBar: widget.sharedBottomNavigationBar,
                body: SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ListTile(
                        title: const Text('Employee'),
                        subtitle: Text(payment.savedName),
                      ),
                      ListTile(
                        title: const Text('Payment date'),
                        subtitle: Text(
                          payment.date == null
                              ? 'Not recorded'
                              : _fullDate.format(payment.date!),
                        ),
                      ),
                      ListTile(
                        title: const Text('Payment method'),
                        subtitle: Text(
                          payment.method.isEmpty
                              ? 'Not recorded'
                              : payment.method,
                        ),
                      ),
                      ListTile(
                        title: const Text('Payroll paid'),
                        subtitle: Text(_amount(payment.cents)),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
    await refresh();
  }

  Widget _paymentTile(EmployeeReportPayment payment, {bool review = false}) {
    final label = payment.date == null
        ? 'Date unavailable'
        : _shortDate.format(payment.date!);
    return ListTile(
      title: Text(
        payment.method.isEmpty ? label : '$label · ${payment.method}',
      ),
      subtitle: review
          ? Text(
              payment.savedName.isEmpty
                  ? 'Employee name unavailable'
                  : payment.savedName,
            )
          : null,
      trailing: Text(
        _amount(payment.cents),
        style: const TextStyle(
          color: BriskersColors.tabBlue,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      onTap: () => _openPayment(payment),
    );
  }

  List<Widget> _detail(EmployeeReportRow employee) {
    final hoursUnknown =
        employee.historical ||
        (employee.labor.isEmpty && employee.payments.isNotEmpty);
    Widget stat(String label, String value) => Expanded(
      child: _card(
        Padding(
          padding: const EdgeInsets.all(10),
          child: _metric(label, value, labelFirst: true),
        ),
      ),
    );
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          stat(
            'Completed labor',
            _hours(employee.completed, historical: hoursUnknown),
          ),
          const SizedBox(width: 8),
          stat('Paid labor', _hours(employee.paid, historical: hoursUnknown)),
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          stat(
            'Unpaid labor',
            _hours(employee.unpaid, historical: hoursUnknown),
          ),
          const SizedBox(width: 8),
          stat('Payroll paid', _amount(employee.paidCents)),
        ],
      ),
      _heading('Completed labor'),
      if (employee.labor.isEmpty)
        const Text('No saved completed labor for this period.')
      else
        _card(
          Column(
            children: [
              for (final (index, labor) in employee.labor.indexed) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 14, endIndent: 14),
                ListTile(
                  title: Text(
                    [
                      if (labor.jobNumber != null) labor.jobNumber!,
                      if (labor.invoiceNumber != null)
                        'Invoice ${labor.invoiceNumber}',
                      if (labor.jobNumber == null &&
                          labor.invoiceNumber == null)
                        'Labor',
                    ].join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    labor.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _hours(labor.minutes),
                    style: const TextStyle(
                      color: BriskersColors.tabBlue,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: labor.invoiceId == null && labor.jobId == null
                      ? null
                      : () => _openLabor(labor),
                ),
              ],
            ],
          ),
        ),
      _heading('Payment history'),
      if (employee.payments.isEmpty)
        const Text('No saved payments for this period.')
      else
        _card(
          Column(
            children: [
              for (final (index, payment) in employee.payments.indexed) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 14, endIndent: 14),
                _paymentTile(payment),
              ],
            ],
          ),
        ),
      if (employee.unpaid == null)
        const Text('Some historical labor has no verified payment coverage.'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) {
      return const Center(child: Text('Owner access is required.'));
    }
    return FutureBuilder<EmployeeReportData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final rows = data?.employees ?? const <EmployeeReportRow>[];
        final person = rows
            .where((row) => row.id == widget.employeeId)
            .firstOrNull;
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.all(12),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _periodPicker(data?.years ?? const []),
              _heading(
                _period.preset == 'shopWeek'
                    ? 'Weekly Labor & Payroll'
                    : 'Labor & Payroll',
              ),
              if (snapshot.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('Reading saved employee reports…')),
                )
              else if (snapshot.hasError)
                ListTile(
                  title: const Text(
                    'Saved employee reports could not be read.',
                  ),
                  trailing: TextButton(
                    onPressed: refresh,
                    child: const Text('Retry'),
                  ),
                )
              else if (_individual)
                ..._detail(
                  person ?? EmployeeReportRow(widget.employeeId!, 'Employee'),
                )
              else if (data != null) ...[
                if (rows.isEmpty)
                  const Text(
                    'No saved employees or payroll payments for this period.',
                  ),
                for (final row in rows) _employeeCard(row),
                if (data.review.isNotEmpty) ...[
                  _heading('Payments to review'),
                  for (final payment in data.review)
                    _card(_paymentTile(payment, review: true)),
                ],
              ],
              if (widget.onPaymentTools != null)
                TextButton(
                  onPressed: widget.onPaymentTools,
                  child: const Text('Payroll payment tools'),
                ),
            ],
          ),
        );
      },
    );
  }
}
