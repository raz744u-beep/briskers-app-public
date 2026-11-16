import '../../services/local_payroll_repository.dart' show VerifiedPayrollWeek;
import 'employee_work_review.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'approved_tasks_ui.dart';

String payrollMoney(int cents) =>
    NumberFormat.simpleCurrency(locale: 'en_US').format(cents / 100);

/// Display-only arithmetic identical to the existing settlement's cumulative
/// minute rounding. This never creates or authorizes a payment.
int selectedLaborCents(Map<String, dynamic> row, double hours, {int? rate}) {
  final paid = row['paid_minutes'] as int? ?? 0;
  final minutes = (hours * 60).round();
  final cents =
      rate ??
      row['payment_rate_cents'] as int? ??
      row['rate_cents'] as int? ??
      0;
  return ((paid + minutes) * cents + 30) ~/ 60 - (paid * cents + 30) ~/ 60;
}

class LaborBalanceTiles extends StatelessWidget {
  const LaborBalanceTiles({
    super.key,
    required this.total,
    required this.paid,
    required this.remaining,
    this.compact = false,
    this.totalLabel = 'Total',
    this.paidLabel = 'Paid',
    this.remainingLabel = 'Remaining',
  });
  final double total, paid, remaining;
  final bool compact;
  final String totalLabel, paidLabel, remainingLabel;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final item in [
        (totalLabel, total, const Color(0xFFE7F2FF), taskBlue),
        (paidLabel, paid, const Color(0xFFE4F7DE), taskGreen),
        (remainingLabel, remaining, const Color(0xFFFFEBD1), taskAmber),
      ])
        Expanded(
          child: Container(
            height: compact ? 56 : 88,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: compact ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4) : const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: item.$3,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.$1,
                    style: TextStyle(
                      height: compact ? 1.1 : null,
                      fontWeight: FontWeight.w700,
                      color: item.$4,
                    ),
                  ),
                ),
                if (compact) const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${item.$2.toStringAsFixed(2)} h',
                    style: TextStyle(
                      fontSize: 23,
                      height: compact ? 1.1 : null,
                      fontWeight: FontWeight.w800,
                      color: item.$4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class PayableHoursDialog extends StatefulWidget {
  const PayableHoursDialog({
    super.key,
    required this.task,
    required this.selected,
    required this.total,
    required this.paid,
    required this.remaining,
  });
  final Map<String, dynamic> task;
  final double selected, total, paid, remaining;
  @override
  State<PayableHoursDialog> createState() => _PayableHoursDialogState();
}

class _PayableHoursDialogState extends State<PayableHoursDialog> {
  late final input = TextEditingController(
    text: (double.parse(widget.selected.toStringAsFixed(2))>widget.remaining ? (widget.remaining*100).floor()/100 : widget.selected).toStringAsFixed(2),
  );
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(input.text.trim());
    final valid =
        value != null &&
        value.isFinite &&
        value >= 0 &&
        value <= widget.remaining &&
        RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(input.text.trim());
    return Dialog(
      backgroundColor:Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF174D91), taskNavy],
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, color: Colors.white),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Edit Payable Hours',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close payable hours',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: taskCanvas,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.task['job_number'] ?? 'Job'} · ${widget.task['customer_name'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text('${widget.task['description'] ?? 'Labor'}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    LaborBalanceTiles(
                      total: widget.total,
                      paid: widget.paid,
                      remaining: widget.remaining,
                      compact: true,
                      totalLabel: 'Total Hours',
                      paidLabel: 'Previously Paid',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Hours to Pay This Week',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('payable-hours-input'),
                      controller: input,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      onTapAlwaysCalled: true,
                      onTap: () => input.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: input.text.length,
                      ),
                      decoration: InputDecoration(
                        suffixText: 'h',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        errorText: valid
                            ? null
                            : 'Enter 0.00 to ${widget.remaining.toStringAsFixed(2)} hours.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: taskGreen,
                            ),
                            onPressed: valid
                                ? () {final current=double.tryParse(input.text.trim());if(current!=null&&current.isFinite&&current>=0&&current<=widget.remaining&&RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(input.text.trim()))Navigator.pop(context,current);}
                                : null,
                            icon: const Icon(Icons.check),
                            label: const Text('Save'),
                          ),
                        ),
                      ],
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

class WorkPayrollSummary extends StatefulWidget {
  const WorkPayrollSummary({
    super.key,
    required this.week,
    required this.rows,
    this.recorded,
    this.historyLoaded = true,
    this.historyLoading = false,
    required this.loadDraft,
    required this.onReview,
    required this.revision,
  });
  final DateTime week;
  final List<Map<String, dynamic>> rows;
  final VerifiedPayrollWeek? recorded;
  final bool historyLoaded, historyLoading;
  final Future<Map<String, dynamic>?> Function(DateTime) loadDraft;
  final VoidCallback onReview;
  final int revision;
  @override
  State<WorkPayrollSummary> createState() => _WorkPayrollSummaryState();
}

class _WorkPayrollSummaryState extends State<WorkPayrollSummary> {
  Map<String, dynamic>? draft;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WorkPayrollSummary old) {
    super.didUpdateWidget(old);
    if (old.week != widget.week || old.revision != widget.revision) _load();
  }

  Future<void> _load() async {
    final token = ++generation;
    draft = null;
    try {
      final value = await widget.loadDraft(widget.week);
      if (mounted && token == generation) setState(() => draft = value);
    } catch (_) {
      if (mounted && token == generation) setState(() => draft = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recorded = widget.recorded;
    String state = widget.historyLoaded
        ? 'Not calculated'
        : widget.historyLoading ? 'Loading history' : 'History unavailable';
    double? hours;
    int? amount;
    if (recorded != null) {
      state = 'Paid';
      hours = recorded.minutes / 60;
      amount = recorded.netCents;
    } else if (draft != null && widget.historyLoaded) {
      final saved = draft!['hours'] as Map? ?? {};
      final byId = {for (final r in widget.rows) r['id']: r};
      final valid = saved.entries.every((e) {
        final r = byId[e.key];
        return r != null &&
            e.value is num &&
            (e.value as num).isFinite &&
            (e.value as num) >= 0 &&
            (e.value as num) * 60 <= (r['remaining_minutes'] as int? ?? 0) &&
            r['archived_labor'] != 1 &&
            r['assignment_conflict'] != 1 &&
            r['payroll_treatment'] != 'review';
      });
      if (valid) {
        state = 'Draft';
        hours = saved.values.fold<double>(
          0,
          (n, v) => n + (v as num).toDouble(),
        );
        amount =
            saved.entries.fold<int>(
              0,
              (n, e) =>
                  n +
                  selectedLaborCents(byId[e.key]!, (e.value as num).toDouble()),
            ) +
            (draft!['adjustment'] as int? ?? 0) -
            (draft!['repayment'] as int? ?? 0);
      }
    }
    final paidInFull = state == 'Paid' && !widget.rows.any((row) =>
        (row['remaining_minutes'] as int? ?? 0) > 0 &&
        EmployeeWorkReview.fallsInWeek(row, widget.week) &&
        row['state'] == 'Done' && row['archived_labor'] != 1 &&
        row['assignment_conflict'] != 1 && row['payroll_treatment'] != 'review');
    return Card(
      key: const Key('work-payroll-summary'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.payments_outlined, color: taskGreen),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Payroll This Week',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
                Text(
                  state,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: state == 'Paid' ? taskGreen : taskNavy,
                  ),
                ),
              ],
            ),
            Text(EmployeeWorkReview.weekLabel(widget.week),
              style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            if (hours == null)
              Text(widget.historyLoaded
                ? 'No verified payments or saved calculation for this week.'
                : widget.historyLoading
                  ? 'Checking saved payroll for the selected week.'
                  : 'Saved payroll history could not be loaded.')
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${state == 'Paid' ? 'Recorded' : 'Selected'} hours: ${hours.toStringAsFixed(2)}',
                  ),
                  Text(
                    payrollMoney(amount!),
                    style: const TextStyle(
                      color: taskGreen,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: taskGreen),
              onPressed: widget.onReview,
              icon: const Icon(Icons.check),
              label: Text(paidInFull ? 'View Payroll Details' : 'Review & Pay'),
            ),
          ],
        ),
      ),
    );
  }
}
